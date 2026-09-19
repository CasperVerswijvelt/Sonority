// The zones-API repository logic used to be covered only by a live hardware e2e
// that skips itself on any household without the zone service. `ZoneApiClient` is
// injectable, so a fake covers the claims the feature actually rests on: what
// happens on a refusal now that there is NO SOAP fallback, definition reuse (the
// "library can't grow unboundedly" guarantee), the orphan case, the one refusal
// that needs a deactivate first, and which zone a coordinator resolves to.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/sonos/sonos_repository.dart';
import 'package:sonority/data/sonos/zone_api.dart';

const coord = 'RINCON_COORD01400';
const other = 'RINCON_OTHER01400';
const stray = 'RINCON_STRAY01400';

ActiveZoneMember _m(String uuid, {bool disconnected = false}) =>
    ActiveZoneMember(uuid: uuid, disconnected: disconnected);

/// A fake session plus the client that hands it out. Everything the repository
/// does now happens inside one session, so the fake models that shape.
class FakeZoneApi extends ZoneApiClient {
  FakeZoneApi({this.zones = const [], List<ZoneDefinition>? defs, this.throwOn})
      : defs = [...?defs];

  /// null models a household with no zone service at all: the subscribe that
  /// opens a session is refused.
  final List<ActiveZone>? zones;
  final List<ZoneDefinition> defs;

  /// Command name that should blow up, and what to throw.
  final (String, Object)? throwOn;

  final calls = <String>[];
  int next = 0;

  void maybeThrow(String command) {
    calls.add(command);
    final t = throwOn;
    if (t != null && t.$1 == command) throw t.$2;
  }

  /// Subclasses override this to model Sonos' answer to an add.
  void onAdd(String name, String rawMap) =>
      defs.add(ZoneDefinition(zoneId: 'new-${next++}', name: name, rawMap: rawMap));

  @override
  Future<List<ActiveZone>?> activeZones(String ip) async {
    calls.add('activeZones');
    return zones;
  }

  @override
  Future<T> withSession<T>(
      String ip, Future<T> Function(ZoneSession session) body,
      {bool live = false}) async {
    if (!live) throw StateError('needs live: true');
    final z = zones;
    if (z == null) throw const ZoneApiException('unsupported namespace');
    return body(FakeSession(this, z));
  }
}

/// Stands in for a live session. [ZoneApiSession] owns a socket and can't be
/// built off-network, which is why the repository talks to the [ZoneSession]
/// interface.
class FakeSession implements ZoneSession {
  FakeSession(this.api, this._zones);
  final FakeZoneApi api;
  final List<ActiveZone> _zones;

  @override
  List<ActiveZone> get activeZones => _zones;
  @override
  List<ZoneDefinition> get definitions => [...api.defs];

  @override
  Future<List<ZoneDefinition>> nextDefinitions() async => [...api.defs];

  @override
  Future<void> addDefinition(
      {required String name, required String rawMap}) async {
    api.maybeThrow('addDefinition');
    api.onAdd(name, rawMap);
  }

  @override
  Future<void> updateDefinition(
          {required String zoneId, required String rawMap}) async =>
      api.maybeThrow('update:$zoneId');

  @override
  Future<void> activate(String zoneId) async =>
      api.maybeThrow('activate:$zoneId');

  @override
  Future<void> deactivate(String zoneId) async =>
      api.maybeThrow('deactivate:$zoneId');

  @override
  Future<void> removeDefinition(String zoneId) async =>
      api.maybeThrow('remove:$zoneId');
}

SonosRepository _repo(FakeZoneApi api) => SonosRepository(zoneApi: api);

Future<void> _apply(FakeZoneApi api, {void Function(String)? onNote}) =>
    _repo(api).applyBondViaZoneApi(
        ip: '192.0.2.1',
        roomName: 'Kitchen',
        targetMap: '$coord:LF,RF',
        onNote: onNote);

void main() {
  group('applyBondViaZoneApi', () {
    test('stores a definition when none matches, then activates it', () async {
      final api = FakeZoneApi(zones: const []);
      await _apply(api);
      expect(api.calls, contains('addDefinition'));
      expect(api.calls, contains('activate:new-0'));
    });

    // The namespace does no dedupe, so this is the whole defence against a
    // household's definition library growing on every single apply.
    test('reuses a definition whose name AND map already match', () async {
      final api = FakeZoneApi(zones: const [], defs: [
        const ZoneDefinition(
            zoneId: 'z1', name: 'Kitchen', rawMap: '$coord:LF,RF'),
      ]);
      await _apply(api);
      expect(api.calls, isNot(contains('addDefinition')));
      expect(api.calls, contains('activate:z1'));
      expect(api.defs, hasLength(1));
    });

    // A stale name is exactly what renames a real room on activation.
    test('does NOT reuse a matching map stored under another name', () async {
      final api = FakeZoneApi(zones: const [], defs: [
        const ZoneDefinition(
            zoneId: 'z1', name: 'Old name', rawMap: '$coord:LF,RF'),
      ]);
      await _apply(api);
      expect(api.calls, contains('addDefinition'));
      expect(api.calls, contains('activate:new-0'));
    });

    // Identifying the new definition by set difference means a Sonos-side
    // normalisation of the name or map can't orphan what we just stored.
    test('activates the newly added definition even if Sonos renamed it',
        () async {
      final api = _RenamingZoneApi();
      await _apply(api);
      expect(api.calls, contains('activate:new-0'));
    });

    // Measured on hardware: an add can store nothing new, because Sonos dedupes
    // onto an equivalent definition. Set difference alone reported that as a
    // failure (1 of 3 timed rounds); whatever it deduped onto is usable.
    test('an add that stored nothing new still activates the match', () async {
      final api = _DedupingZoneApi();
      await _apply(api);
      expect(api.calls, contains('activate:already-there'));
    });

    // Hardware-observed and it never clears on retry: activating over a
    // DIFFERENT live definition on the same coordinator is refused until that
    // one is deactivated. With no SOAP fallback left, recovering here is the
    // difference between the edit working and the user seeing an error. Keyed on
    // "something else is live", not on the message — two wordings were seen.
    test('deactivates the live bond when activation is refused', () async {
      final api = _BusyPrimaryZoneApi();
      final notes = <String>[];
      await _apply(api, onNote: notes.add);
      expect(api.calls, containsAllInOrder(
          ['activate:new-0', 'deactivate:live', 'activate:new-0']));
      expect(notes.join(), contains('deactivating the live bond first'));
    });

    // Without a live zone to get out of the way, a refusal is about the request
    // itself — deactivating nothing and retrying would just loop.
    test('a refusal with nothing else live is reported, not retried', () async {
      final api = FakeZoneApi(
          zones: const [],
          throwOn: ('activate:new-0', const ZoneApiException('activateZone failed')));
      expect(_apply(api), throwsA(isA<ZoneApiException>()));
    });

    // There is no fallback any more, so every one of these must reach the user.
    test('a household with no zone service throws', () async {
      expect(_apply(FakeZoneApi(zones: null)),
          throwsA(isA<ZoneApiException>()));
    });

    test('a named refusal throws', () async {
      final api = FakeZoneApi(
          zones: const [],
          throwOn: ('addDefinition', const ZoneApiException('nope')));
      expect(_apply(api), throwsA(isA<ZoneApiException>()));
    });

    test('an add that stores nothing at all throws', () async {
      expect(_apply(_SilentZoneApi()), throwsA(isA<ZoneApiException>()));
    });

    // The project's own rule: a timed-out write very often applied anyway, so it
    // must mean "go verify", never "it failed" — the caller poll-verifies and
    // turns a genuinely lost write into its own error.
    test('a timeout completes so the caller poll-verifies', () async {
      final api = FakeZoneApi(
          zones: const [],
          throwOn: ('activate:new-0', TimeoutException('slow')));
      final notes = <String>[];
      await _apply(api, onNote: notes.add);
      expect(notes.join(), contains('timed out'));
    });
  });

  group('zone selection', () {
    ActiveZone zone(String id, List<ActiveZoneMember> members) =>
        ActiveZone(zoneId: id, members: members);

    test('dissolve targets the zone the speaker coordinates', () async {
      final api = FakeZoneApi(zones: [
        zone('other-room', [_m(other), _m(stray)]),
        zone('ours', [_m(coord), _m(stray)]),
      ]);
      await _repo(api)
          .dissolveBondViaZoneApi(ip: '192.0.2.1', coordinatorUuid: coord);
      expect(api.calls, contains('deactivate:ours'));
    });

    // The regression this guards: this household's own home theater lists the
    // unofficial fronts as members with `disconnected: true`. Matching on
    // membership alone would deactivate THAT bond when asked about a front.
    test('a merely-listed (not coordinating) speaker matches nothing', () async {
      final api = FakeZoneApi(zones: [
        zone('other-room', [_m(other), _m(coord, disconnected: true)]),
      ]);
      await expectLater(
        _repo(api)
            .dissolveBondViaZoneApi(ip: '192.0.2.1', coordinatorUuid: coord),
        throwsA(isA<ZoneApiException>()),
      );
      expect(api.calls, isNot(contains('deactivate:other-room')));
    });

    test('a disconnected coordinator is not treated as a live bond', () async {
      final api = FakeZoneApi(zones: [
        zone('ours', [_m(coord, disconnected: true), _m(stray)]),
      ]);
      expect(
        _repo(api)
            .dissolveBondViaZoneApi(ip: '192.0.2.1', coordinatorUuid: coord),
        throwsA(isA<ZoneApiException>()),
      );
    });

    test('dropGroupMembers updates the coordinated zone in place', () async {
      final api = FakeZoneApi(zones: [
        zone('ours', [_m(coord), _m(stray)]),
      ]);
      expect(
        await _repo(api).dropGroupMembersViaZoneApi(
            ip: '192.0.2.1', coordinatorUuid: coord, targetMap: '$coord:LF,RF'),
        isTrue,
      );
      expect(api.calls, contains('update:ours'));
    });

    // False here is NOT a failure: it means "no live definition to mutate", and
    // the caller activates the target layout instead — still the zones path.
    test('dropGroupMembers reports false when nothing is live', () async {
      final api = FakeZoneApi(zones: const []);
      expect(
        await _repo(api).dropGroupMembersViaZoneApi(
            ip: '192.0.2.1', coordinatorUuid: coord, targetMap: '$coord:LF,RF'),
        isFalse,
      );
    });
  });
}

/// Models Sonos normalising the stored definition so a re-match on (name, map)
/// would fail — the orphan case.
class _RenamingZoneApi extends FakeZoneApi {
  _RenamingZoneApi() : super(zones: const []);

  @override
  void onAdd(String name, String rawMap) => defs.add(
      ZoneDefinition(zoneId: 'new-0', name: '$name (2)', rawMap: '$coord:LF'));
}

/// Models Sonos answering an add with "you already have that one": nothing new
/// appears, but an equivalent definition is present under the requested name.
class _DedupingZoneApi extends FakeZoneApi {
  _DedupingZoneApi() : super(zones: const []);

  @override
  void onAdd(String name, String rawMap) =>
      // Present only AFTER the add, so the pre-add read finds no match.
      defs.add(
          ZoneDefinition(zoneId: 'already-there', name: name, rawMap: rawMap));
}

/// Models an add that stores nothing an activation could use.
class _SilentZoneApi extends FakeZoneApi {
  _SilentZoneApi() : super(zones: const []);

  @override
  void onAdd(String name, String rawMap) {}
}

/// Models the hardware behaviour: the first activation is refused while another
/// definition is live on the same coordinator, and succeeds once that one is
/// deactivated.
class _BusyPrimaryZoneApi extends FakeZoneApi {
  _BusyPrimaryZoneApi()
      : super(zones: [
          ActiveZone(zoneId: 'live', members: [_m(coord), _m(stray)]),
        ]);

  bool _refused = false;

  @override
  void maybeThrow(String command) {
    super.maybeThrow(command);
    if (command == 'activate:new-0' && !_refused) {
      _refused = true;
      throw const ZoneApiException('activateZone failed');
    }
  }
}
