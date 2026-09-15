import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/device_properties.dart';
import 'package:sonority/data/sonos/soap_client.dart';
import 'package:sonority/data/sonos/sonority_error.dart';
import 'package:sonority/data/sonos/sonos_repository.dart';
import 'package:sonority/data/sonos/zone_topology.dart';
import 'package:xml/xml.dart';

const a = 'RINCON_A01400';
const b = 'RINCON_B01400';

// Two standalone rooms, then the same two as a stereo pair — the shape
// GetZoneGroupState really returns (see zone_test.dart): the coordinator stays
// visible carrying the ChannelMapSet, the other member goes Invisible.
const _apart = '''
<ZoneGroupState><ZoneGroups>
  <ZoneGroup Coordinator="$a" ID="x">
    <ZoneGroupMember UUID="$a" ZoneName="A"
      Location="http://1.2.3.4:1400/xml/device_description.xml"/>
  </ZoneGroup>
  <ZoneGroup Coordinator="$b" ID="y">
    <ZoneGroupMember UUID="$b" ZoneName="B"
      Location="http://1.2.3.5:1400/xml/device_description.xml"/>
  </ZoneGroup>
</ZoneGroups></ZoneGroupState>''';

const _paired = '''
<ZoneGroupState><ZoneGroups>
  <ZoneGroup Coordinator="$a" ID="x">
    <ZoneGroupMember UUID="$a" ZoneName="A"
      Location="http://1.2.3.4:1400/xml/device_description.xml"
      ChannelMapSet="$a:LF,LF;$b:RF,RF"/>
    <ZoneGroupMember UUID="$b" ZoneName="A" Invisible="1"
      Location="http://1.2.3.5:1400/xml/device_description.xml"
      ChannelMapSet="$a:LF,LF;$b:RF,RF"/>
  </ZoneGroup>
</ZoneGroups></ZoneGroupState>''';

/// Answers `GetZoneAttributes` + `GetZoneGroupState` and lets the test decide
/// what `AddBondedZones` does — the three calls a create makes.
class _Soap extends SonosSoapClient {
  /// Error to throw for the Nth `AddBondedZones` (null = accept it).
  final Object? Function(int call) onBond;

  /// Whether the group exists in topology after [bondCalls] writes.
  final bool Function(int bondCalls) formed;

  int bondCalls = 0;
  int attrCalls = 0;
  int stateCalls = 0;

  /// IPs whose `GetZoneAttributes` should fail. A SOAP fault rather than a
  /// refused socket so the test doesn't sit through `retryUnreachable`'s real
  /// 8×5s — both land in the same catch inside `reassertGroup`.
  final Set<String> attrsFailFor;

  /// What `GetZoneAttributes` answers. Mutable so a test can make the speakers
  /// come back under the coordinator's absorbed name, as Sonos does after a
  /// separate.
  String zoneName = 'Living Room';

  /// `SetZoneAttributes` writes by IP — i.e. whose name was actually restored.
  final renamed = <String, String>{};

  _Soap(this.onBond, {bool Function(int)? formed, this.attrsFailFor = const {}})
      : formed = formed ?? ((n) => n > 0);

  @override
  Future<XmlElement> call({
    required String ip,
    required String controlPath,
    required String serviceType,
    required String action,
    Map<String, String> args = const {},
    Duration timeout = const Duration(seconds: 8),
  }) async {
    switch (action) {
      case 'AddBondedZones':
        final err = onBond(++bondCalls);
        if (err != null) throw err;
        return XmlDocument.parse('<Body/>').rootElement;
      case 'GetZoneGroupState':
        stateCalls++;
        final b = XmlBuilder();
        b.element('Body',
            nest: () => b.element('ZoneGroupState',
                nest: formed(bondCalls) ? _paired : _apart));
        return b.buildDocument().rootElement;
      case 'SetZoneAttributes':
        renamed[ip] = args['DesiredZoneName']!;
        return XmlDocument.parse('<Body/>').rootElement;
      default:
        attrCalls++;
        if (attrsFailFor.contains(ip)) {
          throw SonosSoapException('GetZoneAttributes', faultCode: '500');
        }
        return XmlDocument.parse(
                '<Body><CurrentZoneName>$zoneName</CurrentZoneName></Body>')
            .rootElement;
    }
  }
}

void main() {
  const devA =
      SonosDevice(uuid: a, roomName: 'A', modelName: 'Era 300', ip: '1.2.3.4');
  const devB =
      SonosDevice(uuid: b, roomName: 'B', modelName: 'Era 300', ip: '1.2.3.5');
  final members = [
    (device: devA, channel: GroupChannel.left),
    (device: devB, channel: GroupChannel.right),
  ];
  final before = SonosSystem(
    groups: ZoneTopologyClient.parseZoneGroupState(_apart),
    devicesByUuid: const {a: devA, b: devB},
  );

  Future<SonosSystem> create(_Soap soap,
          {Set<String> skipNameSnapshot = const {}}) =>
      SonosRepository(
        deviceProps: DevicePropertiesClient(soap),
        topology: ZoneTopologyClient(soap),
        // Real cadence is 3s per verify read; the loop is what's under test,
        // not the waiting.
        groupVerifyInterval: Duration.zero,
      ).createGroup(
        members: members,
        previous: before,
        skipNameSnapshot: skipNameSnapshot,
      );

  // A bond write that times out or is refused very often still applies, so
  // createGroup must NOT decide — it verifies. Reporting failure on the write
  // is what failed a user's apply whose write had in fact landed.
  test('a timed-out bond write is not a verdict', () async {
    final soap = _Soap((_) => TimeoutException('AddBondedZones'));
    await expectLater(create(soap), completes);
    expect(soap.bondCalls, 1);
  });

  test('a refused bond write is not a verdict', () async {
    final soap = _Soap((_) => StateError('Connection refused'));
    await expectLater(create(soap), completes);
  });

  test('error 800 (mid-reshuffle) is not a verdict', () async {
    final soap =
        _Soap((_) => SonosSoapException('AddBondedZones', faultCode: '800'));
    await expectLater(create(soap), completes);
  });

  test('any other SOAP fault never converges — surface it', () async {
    final soap =
        _Soap((_) => SonosSoapException('AddBondedZones', faultCode: '402'));
    await expectLater(
      create(soap),
      throwsA(isA<SonosSoapException>()
          .having((e) => e.faultCode, 'faultCode', '402')),
    );
    expect(soap.bondCalls, 1, reason: 'a permanent fault must not be retried');
  });

  test('a clean write completes without retrying', () async {
    final soap = _Soap((_) => null);
    await create(soap);
    expect(soap.bondCalls, 1);
    expect(soap.attrCalls, 2); // one name snapshot per member, no retries
  });

  // The defect, reproduced on hardware: creating a group out of speakers that
  // were bonded elsewhere a moment ago. Sonos accepts AddBondedZones (200 OK)
  // and silently does nothing because the old bond is still tearing down — so a
  // single write left the source home theater stripped and no group built. The
  // identical write succeeded on the user's retry, so we retry it ourselves.
  test('an accepted write that silently no-ops is re-asserted', () async {
    final soap = _Soap((_) => null, formed: (n) => n >= 2);
    final after = await create(soap);
    expect(soap.bondCalls, 2);
    expect(soap.attrCalls, 2, reason: 'names are snapshotted once, up front');
    expect(after.memberByUuid(a)?.isStereoPair, isTrue);
  });

  // A speaker just pulled out of a home theater still answers with the BAR's
  // room name — `RemoveHTSatellite` doesn't restore names and nothing ever
  // captured the original. Storing it would make a later separate rename the
  // speaker into a collision with the live home theater.
  test('a skipped member has no name read at all', () async {
    final soap = _Soap((_) => null);
    await create(soap, skipNameSnapshot: {b});
    expect(soap.attrCalls, 1, reason: 'only A is snapshotted');
  });

  // ...and the consequence: a partial snapshot must still restore the members
  // it DID capture. Keyed by what was captured rather than by the group's full
  // membership, the read (which asks by the live member list) missed the key
  // and NOBODY was renamed — A came back under the coordinator's absorbed name.
  test('a partial snapshot still restores the member it captured', () async {
    final soap = _Soap((_) => null);
    final repo = SonosRepository(
      deviceProps: DevicePropertiesClient(soap),
      topology: ZoneTopologyClient(soap),
      groupVerifyInterval: Duration.zero,
    );
    await repo.createGroup(
        members: members, previous: before, skipNameSnapshot: {b});
    // What Sonos leaves behind on a separate: both members under the group name.
    soap.zoneName = 'Group';
    await repo.separateGroup(
        members: const [devA, devB], channelMapSet: '$a:LF,LF;$b:RF,RF');
    expect(soap.renamed, {'1.2.3.4': 'Living Room'},
        reason: 'A was captured, so A is restored; B was skipped on purpose');
  });

  // The snapshot runs BEFORE the first write, and on the dissolve→recreate path
  // the old group is already torn down by then — rethrowing here left a user
  // with no group at all rather than one member's name unrecorded.
  test('a name read that fails does not abort the bond', () async {
    final soap = _Soap((_) => null, attrsFailFor: {'1.2.3.5'});
    final after = await create(soap);
    expect(after.memberByUuid(a)?.isStereoPair, isTrue);
    expect(soap.bondCalls, 1);
  });

  test('a write that never takes reports failure, not success', () async {
    final soap = _Soap((_) => null, formed: (_) => false);
    await expectLater(
      create(soap),
      throwsA(isA<SonorityError>().having(
          (e) => e.code, 'code', SonorityErrorCode.didNotCreateGroup)),
    );
    expect(soap.bondCalls, greaterThan(1), reason: 'it must re-assert first');
  });
}
