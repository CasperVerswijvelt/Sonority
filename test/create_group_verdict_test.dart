import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/device_properties.dart';
import 'package:sonority/data/sonos/soap_client.dart';
import 'package:sonority/data/sonos/sonos_repository.dart';
import 'package:xml/xml.dart';

/// Answers `GetZoneAttributes` and lets the test decide what `AddBondedZones`
/// does — the two calls `createGroup` makes.
class _Soap extends SonosSoapClient {
  final Object? Function() onBond;
  int bondCalls = 0;
  int attrCalls = 0;
  _Soap(this.onBond);

  @override
  Future<XmlElement> call({
    required String ip,
    required String controlPath,
    required String serviceType,
    required String action,
    Map<String, String> args = const {},
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (action == 'AddBondedZones') {
      bondCalls++;
      final err = onBond();
      if (err != null) throw err;
      return XmlDocument.parse('<Body/>').rootElement;
    }
    attrCalls++;
    return XmlDocument.parse(
            '<Body><CurrentZoneName>Living Room</CurrentZoneName></Body>')
        .rootElement;
  }
}

void main() {
  const a = 'RINCON_A01400';
  const b = 'RINCON_B01400';
  final members = [
    (
      device: const SonosDevice(
          uuid: a, roomName: 'A', modelName: 'Era 300', ip: '1.2.3.4'),
      channel: GroupChannel.left
    ),
    (
      device: const SonosDevice(
          uuid: b, roomName: 'B', modelName: 'Era 300', ip: '1.2.3.5'),
      channel: GroupChannel.right
    ),
  ];

  Future<void> create(Object? Function() onBond) {
    final soap = _Soap(onBond);
    return SonosRepository(deviceProps: DevicePropertiesClient(soap))
        .createGroup(members: members);
  }

  // A bond write that times out or is refused very often still applies, so
  // createGroup must NOT decide — every caller poll-verifies. Reporting failure
  // here is what failed a user's apply whose write had in fact landed.
  test('a timed-out bond write is not a verdict', () async {
    await expectLater(create(() => TimeoutException('AddBondedZones')),
        completes);
  });

  test('a refused bond write is not a verdict', () async {
    await expectLater(create(() => StateError('Connection refused')), completes);
  });

  test('error 800 (mid-reshuffle) is not a verdict', () async {
    await expectLater(
        create(() => SonosSoapException('AddBondedZones', faultCode: '800')),
        completes);
  });

  test('any other SOAP fault never converges — surface it', () async {
    await expectLater(
      create(() => SonosSoapException('AddBondedZones', faultCode: '402')),
      throwsA(isA<SonosSoapException>()
          .having((e) => e.faultCode, 'faultCode', '402')),
    );
  });

  test('a clean write completes without retrying', () async {
    final soap = _Soap(() => null);
    await SonosRepository(deviceProps: DevicePropertiesClient(soap))
        .createGroup(members: members);
    expect(soap.bondCalls, 1);
    expect(soap.attrCalls, 2); // one name snapshot per member, no retries
  });
}
