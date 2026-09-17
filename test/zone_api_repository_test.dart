// The zones-API repository logic used to be covered only by a live hardware e2e
// that skips itself on any household without the zone service. `ZoneApiClient` is
// injectable, so a fake covers the claims the feature actually rests on: the
// fallback contract, definition reuse (the "library can't grow unboundedly"
// guarantee), the orphan case, and which zone a coordinator resolves to.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/sonos/sonos_repository.dart';
import 'package:sonority/data/sonos/zone_api.dart';

const coord = 'RINCON_COORD01400';
const other = 'RINCON_OTHER01400';
const stray = 'RINCON_STRAY01400';

ActiveZoneMember _m(String uuid, {bool disconnected = false}) =>
    ActiveZoneMember(uuid: uuid, disconnected: disconnected);

class FakeZoneApi extends ZoneApiClient {
  FakeZoneApi({this.zones = const [], List<ZoneDefinition>? defs, this.throwOn})
      : defs = [...?defs];

  /// null models a household with no zone service at all.
  final List<ActiveZone>? zones;
  final List<ZoneDefinition> defs;

  /// Command name that should blow up, and what to throw.
  final (String, Object)? throwOn;

  final calls = <String>[];
  int _next = 0;

  void _maybeThrow(String command) {
    calls.add(command);
    final t = throwOn;
    if (t != null && t.$1 == command) throw t.$2;
  }

  @override
  Future<List<ActiveZone>?> activeZones(String ip) async {
    calls.add('activeZones');
    return zones;
  }

  @override
  Future<bool> supported(String ip) async => zones != null;

  @override
  Future<List<ZoneDefinition>> definitions(String ip) async => [...defs];

  @override
  Future<void> addDefinition({
    required String ip,
    required String name,
    required String rawMap,
    bool live = false,
  }) async {
    _maybeThrow('addDefinition');
    defs.add(ZoneDefinition(
        zoneId: 'new-${_next++}', name: name, rawMap: rawMap));
  }

  @override
  Future<void> activate({
    required String ip,
    required String zoneId,
    bool live = false,
  }) async =>
      _maybeThrow('activate:$zoneId');

  @override
  Future<void> deactivate({
    required String ip,
    required String zoneId,
    bool live = false,
  }) async =>
      _maybeThrow('deactivate:$zoneId');

  @override
  Future<void> updateDefinition({
    required String ip,
    required String zoneId,
    required String rawMap,
    bool live = false,
  }) async =>
      _maybeThrow('update:$zoneId');
}

SonosRepository _repo(FakeZoneApi api) => SonosRepository(zoneApi: api);

void main() {
  group('applyBondViaZoneApi', () {
    test('stores a definition when none matches, then activates it', () async {
      final api = FakeZoneApi(zones: const []);
      expect(
        await _repo(api).applyBondViaZoneApi(
            ip: '192.0.2.1', roomName: 'Kitchen', targetMap: '$coord:LF,RF'),
        isTrue,
      );
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
      expect(
        await _repo(api).applyBondViaZoneApi(
            ip: '192.0.2.1', roomName: 'Kitchen', targetMap: '$coord:LF,RF'),
        isTrue,
      );
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
      await _repo(api).applyBondViaZoneApi(
          ip: '192.0.2.1', roomName: 'Kitchen', targetMap: '$coord:LF,RF');
      expect(api.calls, contains('addDefinition'));
      expect(api.calls, contains('activate:new-0'));
    });

    // Identifying the new definition by set difference means a Sonos-side
    // normalisation of the name or map can't orphan what we just stored.
    test('activates the newly added definition even if Sonos renamed it',
        () async {
      final api = _RenamingZoneApi();
      expect(
        await _repo(api).applyBondViaZoneApi(
            ip: '192.0.2.1', roomName: 'Kitchen', targetMap: '$coord:LF,RF'),
        isTrue,
      );
      expect(api.calls, contains('activate:new-0'));
    });

    test('a household with no zone service falls back', () async {
      final api = FakeZoneApi(zones: null);
      expect(
        await _repo(api).applyBondViaZoneApi(
            ip: '192.0.2.1', roomName: 'Kitchen', targetMap: '$coord:LF,RF'),
        isFalse,
      );
    });

    test('a named refusal falls back', () async {
      final api = FakeZoneApi(
          zones: const [],
          throwOn: ('addDefinition', const ZoneApiException('nope')));
      final notes = <String>[];
      expect(
        await _repo(api).applyBondViaZoneApi(
            ip: '192.0.2.1',
            roomName: 'Kitchen',
            targetMap: '$coord:LF,RF',
            onNote: notes.add),
        isFalse,
      );
      expect(notes.join(), contains('refused (nope)'));
    });

    // The project's own rule: a timed-out write very often applied anyway, so it
    // must mean "go verify", never "it failed" — reporting failure here would
    // fire a SOAP write on top of a change already in flight.
    test('a timeout reports success so the caller poll-verifies', () async {
      final api = FakeZoneApi(
          zones: const [],
          throwOn: ('activate:new-0', TimeoutException('slow')));
      final notes = <String>[];
      expect(
        await _repo(api).applyBondViaZoneApi(
            ip: '192.0.2.1',
            roomName: 'Kitchen',
            targetMap: '$coord:LF,RF',
            onNote: notes.add),
        isTrue,
      );
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
      expect(
        await _repo(api)
            .dissolveBondViaZoneApi(ip: '192.0.2.1', coordinatorUuid: coord),
        isTrue,
      );
      expect(api.calls, contains('deactivate:ours'));
    });

    // The regression this guards: this household's own home theater lists the
    // unofficial fronts as members with `disconnected: true`. Matching on
    // membership alone would deactivate THAT bond when asked about a front.
    test('a merely-listed (not coordinating) speaker matches nothing', () async {
      final api = FakeZoneApi(zones: [
        zone('other-room', [_m(other), _m(coord, disconnected: true)]),
      ]);
      final notes = <String>[];
      expect(
        await _repo(api).dissolveBondViaZoneApi(
            ip: '192.0.2.1', coordinatorUuid: coord, onNote: notes.add),
        isFalse,
      );
      expect(api.calls, isNot(contains('deactivate:other-room')));
      expect(notes.join(), contains('no active zone is coordinated by'));
    });

    test('a disconnected coordinator is not treated as a live bond', () async {
      final api = FakeZoneApi(zones: [
        zone('ours', [_m(coord, disconnected: true), _m(stray)]),
      ]);
      expect(
        await _repo(api)
            .dissolveBondViaZoneApi(ip: '192.0.2.1', coordinatorUuid: coord),
        isFalse,
      );
    });

    test('dropGroupMembers updates the coordinated zone in place', () async {
      final api = FakeZoneApi(zones: [
        zone('ours', [_m(coord), _m(stray)]),
      ]);
      expect(
        await _repo(api).dropGroupMembersViaZoneApi(
            ip: '192.0.2.1',
            coordinatorUuid: coord,
            targetMap: '$coord:LF,RF'),
        isTrue,
      );
      expect(api.calls, contains('update:ours'));
    });
  });
}

/// Models Sonos normalising the stored definition so a re-match on (name, map)
/// would fail — the orphan case.
class _RenamingZoneApi extends FakeZoneApi {
  _RenamingZoneApi() : super(zones: const []);

  @override
  Future<void> addDefinition({
    required String ip,
    required String name,
    required String rawMap,
    bool live = false,
  }) async {
    calls.add('addDefinition');
    defs.add(ZoneDefinition(
        zoneId: 'new-0', name: '$name (2)', rawMap: '$coord:LF'));
  }
}
