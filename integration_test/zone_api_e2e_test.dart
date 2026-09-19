// LIVE end-to-end test of the newer `:1443` zones bonding path, driven through
// the real UI on a device/desktop on the same Wi-Fi as the real Sonos system.
//
// Unlike `profile_e2e_test.dart` (a deliberate NO-OP apply that proves the diff
// disturbed nothing), this one makes a REAL bonding change and puts it back:
// it picks an existing speaker group, adds a spare standalone speaker to it via
// the Configure flow, then removes it again. Both directions must:
//   * land the expected topology, and
//   * report in the operation log that the zones API did it — because the whole
//     point of the feature is which path ran, and a SOAP fallback would produce
//     an identical end state while silently proving nothing.
//
// It skips itself (rather than failing) on a household with no zone service or
// no spare speaker, so it is safe to run anywhere.
//
//   flutter test integration_test/zone_api_e2e_test.dart -d macos
//
// ⚠️ This writes to real speakers. It restores the original membership in a
// tearDown-style final step even if the assertions fail.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sonority/app.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/zone_api.dart';
import 'package:sonority/state/sonos_controller.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('add + remove a group member via the zones API', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SonorityApp()));
    await tester.pump(const Duration(seconds: 1));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    await _until(
      tester,
      () => _text('Home theaters'),
      timeout: const Duration(seconds: 40),
      what: 'discovery',
    );

    final system = container.read(sonosControllerProvider).value;
    if (system == null) fail('no system after discovery');

    // Pick the first speaker group and a spare standalone speaker to move in
    // and out of it. Both are required; without them there is nothing to test.
    final group = system.allMembers.where((m) => m.isGroup).firstOrNull;
    final spare = system.allMembers
        .where((m) => !m.isGroup && !m.isHomeTheater && !m.invisible)
        .map((m) => system.device(m.uuid))
        .whereType<SonosDevice>()
        .where((d) => !d.isSoundbar && !d.drivesExternalSpeakers)
        .firstOrNull;
    if (group == null || spare == null) {
      markTestSkipped('needs an existing speaker group + a spare speaker');
      return;
    }
    final groupName = group.zoneName;
    final before = group.channelMapUuids.length;
    debugPrint(
      'E2E: group "$groupName" has $before members; '
      'spare = ${spare.roomName}',
    );

    final ip = group.ip;
    if (ip == null || await const ZoneApiClient().activeZones(ip) == null) {
      markTestSkipped('household has no zones API');
      return;
    }

    try {
      // ---- 1. ADD the spare via Configure -------------------------------
      await _editGroup(tester, groupName, spare.roomName);
      final added = _memberCount(container, group.uuid);
      final addLog = _zoneApiLines(container);
      debugPrint('E2E: after add -> $added members; zones API lines: $addLog');
      expect(added, before + 1, reason: 'the spare should have joined');
      expect(
        addLog,
        isNotEmpty,
        reason:
            'the zones API must be the path that applied it, '
            'not a silent SOAP fallback',
      );

      // ---- 2. REMOVE it again -------------------------------------------
      await _editGroup(tester, groupName, spare.roomName);
      final removed = _memberCount(container, group.uuid);
      final dropLog = _zoneApiLines(container);
      debugPrint('E2E: after remove -> $removed members; zones API: $dropLog');
      expect(removed, before, reason: 'the spare should have left');
      expect(
        dropLog,
        isNotEmpty,
        reason: 'removal must go through updateZoneDefinition, not a dissolve',
      );
    } finally {
      // Leave the system as we found it even if an expectation blew up.
      final now = _memberCount(container, group.uuid);
      if (now != before) {
        debugPrint('E2E: restoring membership ($now -> $before)');
        await _editGroup(tester, groupName, spare.roomName);
      }
    }
  });

  // A second real change: tear the group down and build it back, which exercises
  // `deactivateZone` and the create path rather than the edit path.
  testWidgets('dissolve + recreate a group via the zones API', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SonorityApp()));
    await tester.pump(const Duration(seconds: 1));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    await _until(
      tester,
      () => _text('Home theaters'),
      timeout: const Duration(seconds: 40),
      what: 'discovery',
    );

    final system = container.read(sonosControllerProvider).value;
    final group = system?.allMembers.where((m) => m.isGroup).firstOrNull;
    if (system == null || group == null) {
      markTestSkipped('needs an existing speaker group');
      return;
    }
    final name = group.zoneName;
    final size = group.channelMapUuids.length;
    final ip = group.ip;
    if (ip == null || await const ZoneApiClient().activeZones(ip) == null) {
      markTestSkipped('household has no zones API');
      return;
    }
    debugPrint('E2E: dissolving "$name" ($size speakers)');

    // ---- 1. DISSOLVE via the detail page's Separate action ---------------
    await _tap(tester, find.text(name));
    await _until(
      tester,
      () => _text('Separate'),
      timeout: const Duration(seconds: 15),
      what: 'group detail',
    );
    await _tap(tester, find.text('Separate'));
    await _until(
      tester,
      () => _text('Separate group?'),
      timeout: const Duration(seconds: 10),
      what: 'confirm dialog',
    );
    await _tap(tester, find.text('Separate'));
    await _until(
      tester,
      () => _text('Done'),
      timeout: const Duration(seconds: 240),
      what: 'separate to finish',
    );
    expect(_text('Retry'), isFalse, reason: 'the separate failed');
    final dissolveLog = _zoneApiLines(container);
    debugPrint('E2E: dissolve log = $dissolveLog');
    await _tap(tester, find.text('Done'));
    await tester.pump(const Duration(seconds: 2));
    expect(
      dissolveLog,
      isNotEmpty,
      reason: 'deactivateZone must be the path, not detach + separate',
    );

    // ---- 2. RECREATE it via the overview's "+" ---------------------------
    // 'Speaker groups' is the section header; 'Group speakers' is the + button's
    // tooltip. Pop back until the overview is up — the detail page we came from
    // is stale now that its group is gone.
    await _backToOverview(tester);
    await _tap(tester, find.byTooltip('Group speakers'));
    await _until(
      tester,
      () => _text('Zone'),
      timeout: const Duration(seconds: 15),
      what: 'group flow',
    );
    await _tap(tester, find.text('Zone'));
    await tester.pump(const Duration(milliseconds: 400));

    // The freed speakers keep the group's room name, so both tiles read the
    // same — select them by their tile, not by a (duplicate) label.
    final tiles = find.ancestor(
      of: find.text(name),
      matching: find.byType(CheckboxListTile),
    );
    expect(tiles, findsNWidgets(size), reason: 'freed members not all offered');
    for (var i = 0; i < size; i++) {
      await _tap(tester, tiles.at(i));
      await tester.pump(const Duration(milliseconds: 250));
    }
    for (var i = 0; i < 4 && !_text('Create zone'); i++) {
      await _tap(tester, find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(
      _text('Create zone'),
      isTrue,
      reason: 'never reached the review step',
    );
    await _tap(tester, find.text('Create zone'));
    await _until(
      tester,
      () => _text('Done'),
      timeout: const Duration(seconds: 240),
      what: 'create to finish',
    );
    expect(_text('Retry'), isFalse, reason: 'the create failed');
    final createLog = _zoneApiLines(container);
    debugPrint('E2E: create log = $createLog');
    await _tap(tester, find.text('Done'));
    await tester.pump(const Duration(seconds: 3));

    expect(
      createLog,
      isNotEmpty,
      reason: 'create must go through activateZone',
    );
    // The app re-reads topology a beat after the bond lands, so poll rather than
    // asserting on whatever the cache held when Done was tapped.
    await _until(
      tester,
      () => _memberCount(container, group.uuid) == size,
      timeout: const Duration(seconds: 60),
      what: 'the group to be back to its original size',
    );
  });
}

/// Opens [groupName]'s detail page → Configure, toggles [speakerName], saves,
/// and waits for the bonding screen to finish.
Future<void> _editGroup(
  WidgetTester tester,
  String groupName,
  String speakerName,
) async {
  await _until(
    tester,
    () => _text(groupName),
    timeout: const Duration(seconds: 20),
    what: 'overview',
  );
  await _tap(tester, find.text(groupName));
  await _until(
    tester,
    () => _text('Configure'),
    timeout: const Duration(seconds: 15),
    what: 'group detail',
  );
  await _tap(tester, find.text('Configure'));
  // The flow is a 4-step vertical Stepper (speakers → sub → name → review);
  // its primary button reads 'Continue' until the review step.
  await _until(
    tester,
    () => _text('Continue'),
    timeout: const Duration(seconds: 15),
    what: 'configure flow',
  );

  // Toggle the speaker on step 1. Scope to the checkbox tile: the pushed route
  // leaves the overview's own copy of the room name in the tree.
  final tile = find.widgetWithText(CheckboxListTile, speakerName);
  expect(tile, findsWidgets, reason: '$speakerName not offered in the flow');
  await _tap(tester, tile);
  await tester.pump(const Duration(milliseconds: 300));

  // Advance to the review step, then save. The Stepper renders a control row
  // per step, so only the expanded step's button is hit-testable — everything
  // here taps through `_tap`, which filters to that one.
  for (var i = 0; i < 4 && !_text('Save changes'); i++) {
    await _tap(tester, find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 400));
  }
  expect(
    _text('Save changes'),
    isTrue,
    reason: 'never reached the review step',
  );
  await _tap(tester, find.text('Save changes'));

  await _until(
    tester,
    () => _text('Done'),
    timeout: const Duration(seconds: 240),
    what: 'bonding to finish',
  );
  expect(_text('Retry'), isFalse, reason: 'the bonding step failed');
  await _tap(tester, find.text('Done'));
  await tester.pump(const Duration(seconds: 2));
  // Back out of the detail page to the overview for the next round.
  final back = find.byTooltip('Back');
  if (back.evaluate().isNotEmpty) {
    await _tap(tester, back);
    await tester.pump(const Duration(seconds: 1));
  }
}

int _memberCount(ProviderContainer c, String uuid) =>
    c
        .read(sonosControllerProvider)
        .value
        ?.memberByUuid(uuid)
        ?.channelMapUuids
        .length ??
    -1;

/// The operation log is where the engine records which path ran — this is the
/// assertion that distinguishes "it worked" from "it worked via the new API".
List<String> _zoneApiLines(ProviderContainer c) => c
    .read(operationLogProvider)
    .where((l) => l.contains('zones API:'))
    .toList();

/// Pops until the system overview is showing.
Future<void> _backToOverview(WidgetTester tester) async {
  for (var i = 0; i < 4 && !_text('Speaker groups'); i++) {
    final back = find.byTooltip('Back');
    if (back.evaluate().isEmpty) break;
    await _tap(tester, back);
    await tester.pump(const Duration(seconds: 1));
  }
  await _until(
    tester,
    () => _text('Speaker groups'),
    timeout: const Duration(seconds: 20),
    what: 'back on the overview',
  );
}

bool _text(String s) => find.text(s).evaluate().isNotEmpty;

/// Taps the one visible match. Several screens here render the same label more
/// than once (a Stepper builds its controls for every step), and only the
/// expanded one can actually be hit.
Future<void> _tap(WidgetTester tester, Finder f) async {
  // The review step sits below the fold, so scroll the target into view first;
  // `ensureVisible` is a no-op when it already is.
  if (f.evaluate().isNotEmpty) {
    try {
      await tester.ensureVisible(f.first);
      await tester.pump(const Duration(milliseconds: 200));
    } catch (_) {
      // Not inside a scrollable — fine, it was already reachable.
    }
  }
  final hittable = f.hitTestable();
  expect(hittable, findsWidgets, reason: 'nothing tappable for $f');
  await tester.tap(hittable.first);
}

Future<void> _until(
  WidgetTester tester,
  bool Function() done, {
  required Duration timeout,
  required String what,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (done()) return;
  }
  fail('timed out waiting for $what');
}
