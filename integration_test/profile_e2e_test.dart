// LIVE end-to-end test, run on a device/desktop on the same Wi-Fi as the real
// Sonos system. Drives the real UI: auto-scan → create a profile from the
// current state → apply it → verify the bonded topology is unchanged → delete
// the profile.
//
// Applying a just-captured profile targets the CURRENT layout, so the diff-based
// apply (_applyHtTarget) is a NO-OP — zero bonding writes, no teardown, no
// Trueplay wipe. We snapshot the bonded topology (HTs + speaker groups and their
// channel maps) right after discovery and assert it is byte-for-byte identical
// after the apply. This works on ANY system — all-standalone (empty signature),
// a 5.1 HT, stereo pairs, zones — and proves the no-op path disturbed nothing.
// (If this apply suddenly takes minutes again, the diff broke and it's falling
// back to a full rebuild.)
//
//   flutter test integration_test/profile_e2e_test.dart -d <device|macos>

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sonority/app.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/features/profiles/profile_controller.dart';
import 'package:sonority/state/sonos_controller.dart';

const _testProfileName = 'E2E TEST';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('create + apply a profile on live hardware', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SonorityApp()));
    await tester.pump(const Duration(seconds: 1));

    // Capture the root container once for diagnostics + final verification.
    final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)));
    void dumpProgress(String when) {
      final steps = container.read(applyProgressProvider);
      debugPrint('E2E progress ($when):');
      for (final s in steps) {
        debugPrint('  - ${s.label}: ${s.status.name}'
            '${s.detail != null ? ' — ${s.detail}' : ''}');
      }
    }

    // The test coexists with the user's real profiles (e.g. "My setup"), so
    // never clear the store — just remove any leftover test profile from a prior
    // aborted run up front (a name clash would otherwise block re-creating it).
    // Step 7 deletes this run's profile; a failed run's leftover is cleared here
    // next time. (Can't use addTearDown: the ProviderScope is disposed by then.)
    await container.read(profilesProvider.future);
    for (final p in (container.read(profilesProvider).value ?? const [])
        .where((p) => p.name == _testProfileName)) {
      await container.read(profilesProvider.notifier).remove(p.id);
    }

    // 1. The app auto-scans on launch (no landing page). Wait for the system
    //    overview — its 'Home theaters' section header always renders, even when
    //    empty, so it's a stable "scan complete" marker on any system.
    await _until(tester, () => _text('Home theaters'),
        timeout: const Duration(seconds: 40), what: 'discovery');
    debugPrint('E2E: discovery complete');

    // Snapshot the bonded topology now — the apply below must leave it identical.
    final before = _bondSig(container.read(sonosControllerProvider).value);
    debugPrint('E2E: bonded signature before = $before');

    // 2. Profiles tab → New profile.
    await tester.tap(find.text('Profiles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New profile'));
    await _until(tester, () => _text('Create profile'),
        timeout: const Duration(seconds: 10), what: 'edit screen');

    // 3. Name it and create (all current entities are included by default).
    //    Wait until we're back on the list — signalled by the tile's Apply
    //    button. ('E2E TEST' text alone is ambiguous: the create screen's
    //    TextField already contains it, so it'd match before navigation.)
    await tester.enterText(find.byType(TextField).first, 'E2E TEST');
    await tester.pump();
    await tester.tap(find.text('Create profile'));
    // Back on the list once the tile shows AND the create screen's button is
    // gone (the TextField also contains 'E2E TEST', so that text alone is
    // ambiguous while the create screen is still up).
    await _until(
        tester,
        () => _text('E2E TEST') && !_text('Create profile'),
        timeout: const Duration(seconds: 10),
        what: 'profile saved + back on list');
    debugPrint('E2E: profile created');

    // The test's own profile tile — scope tile-level finders to it so the user's
    // other profiles (e.g. "My setup") don't make 'Apply'/menu ambiguous.
    final testTile =
        find.ancestor(of: find.text(_testProfileName), matching: find.byType(Card));

    // 4. Apply it (tile Apply → confirm dialog → Apply). Tap THIS tile's Apply;
    //    the dialog's Apply is an exact-type TextButton (the tile's is a
    //    FilledButton.icon subtype, so type-based finders don't confuse them).
    await tester.tap(find.descendant(of: testTile, matching: find.text('Apply')));
    await _until(tester, () => _text('Cancel') && _text('Apply'),
        timeout: const Duration(seconds: 10), what: 'confirm dialog');
    await tester.tap(find.widgetWithText(TextButton, 'Apply'));

    // 5. The shared bonding dialog runs the apply, then shows a 'Done' button
    //    (and 'Retry' too on failure). It does NOT auto-pop. Wait for 'Done',
    //    note whether 'Retry' is also present (= failure), tap Done to close.
    await _until(
      tester,
      () => _text('Done'),
      timeout: const Duration(seconds: 240),
      what: 'apply to finish',
    );
    final failed = _text('Retry');
    dumpProgress(failed ? 'FAILED' : 'done');
    await tester.tap(find.widgetWithText(FilledButton, 'Done').evaluate().isNotEmpty
        ? find.widgetWithText(FilledButton, 'Done')
        : find.widgetWithText(OutlinedButton, 'Done'));
    await _until(tester, () => _text('New profile'),
        timeout: const Duration(seconds: 10), what: 'back on list');
    if (failed) throw TestFailure('Apply failed — see progress dump above.');
    debugPrint('E2E: apply completed, back on list');

    // 6. Verify the no-op apply left the bonded topology byte-for-byte intact
    //    (same HTs/groups, same channel maps). Holds on any system.
    final system = container.read(sonosControllerProvider).value;
    expect(system, isNotNull, reason: 'system should be loaded');
    final after = _bondSig(system);
    debugPrint('E2E: bonded signature after = $after');
    expect(after, equals(before),
        reason: 'apply must be a no-op — bonds unchanged');

    // 7. Clean up the test profile (its overflow menu → Delete → confirm dialog).
    //    Find the menu by widget type, not icon: PopupMenuButton's default glyph
    //    is Icons.adaptive.more (more_horiz on macOS/iOS, more_vert on Android).
    await tester.tap(find.descendant(
        of: testTile, matching: find.byType(PopupMenuButton<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await _until(tester, () => _text('Delete') && _text('Cancel'),
        timeout: const Duration(seconds: 10), what: 'delete dialog');
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    debugPrint('E2E: cleaned up — DONE');
  }, timeout: const Timeout(Duration(minutes: 8)));
}

bool _text(String s) => find.text(s).evaluate().isNotEmpty;

/// A stable signature of every bond in the system: each home theater and speaker
/// group keyed by coordinator UUID → its authoritative channel map. Empty on an
/// all-standalone system. The no-op apply must not change this.
Map<String, String> _bondSig(SonosSystem? s) => {
      if (s != null) ...{
        for (final m in s.homeTheaters) m.uuid: 'HT:${m.htSatChanMapSet ?? ''}',
        for (final m in s.speakerGroups) m.uuid: 'GRP:${m.channelMapSet ?? ''}',
      },
    };

/// Pumps the UI in a loop (real time) until [cond] is true or [timeout] elapses.
/// Used instead of pumpAndSettle because discovery/bonding never "settle".
Future<void> _until(
  WidgetTester tester,
  bool Function() cond, {
  required Duration timeout,
  required String what,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 400));
    if (cond()) return;
  }
  throw TimeoutException('Timed out waiting for: $what');
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
  @override
  String toString() => 'TimeoutException: $message';
}
