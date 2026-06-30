// LIVE end-to-end test, run on a device/emulator on the same Wi-Fi as the real
// Sonos system. Drives the real UI: scan → create a profile from the current
// state → apply it → verify the home theater is intact → delete the profile.
//
// Applying a just-captured profile targets the CURRENT layout, so the diff-based
// apply (_applyHtTarget) is a NO-OP — zero bonding writes, no teardown, no
// Trueplay wipe. The HT-intact assertions below therefore also prove the no-op
// path left everything bonded. (If this apply suddenly takes minutes again, the
// diff broke and it's falling back to a full rebuild.)
//
//   flutter test integration_test/profile_e2e_test.dart -d <emulator>

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sonority/app.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/state/sonos_controller.dart';

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

    // 1. Scan the LAN.
    expect(find.text('Find my Sonos system'), findsOneWidget);
    await tester.tap(find.text('Find my Sonos system'));
    await _until(tester, () => _text('Home theaters'),
        timeout: const Duration(seconds: 40), what: 'discovery');
    debugPrint('E2E: discovery complete');

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

    // 4. Apply it (tile Apply → confirm dialog → Apply). The list has a single
    //    'Apply' (the tile button); the dialog's Apply is an exact-type
    //    TextButton (the tile's is a FilledButton.icon subtype, so type-based
    //    finders don't confuse the two).
    await tester.tap(find.text('Apply'));
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

    // 6. Verify the home theater is intact via the live controller state.
    final system = container.read(sonosControllerProvider).value;
    expect(system, isNotNull, reason: 'system should be loaded');
    final ht = system!.homeTheaters.firstOrNull;
    expect(ht, isNotNull, reason: 'a home theater should still exist');
    final ch = ht!.channelAssignments.keys.toSet();
    debugPrint('E2E: HT channels after apply = '
        '${ch.map((c) => c.token).join(',')}');
    // Whatever roles the HT had are still bonded (fronts + rears + sub here).
    expect(ch.contains(SonosChannel.leftFront), isTrue, reason: 'LF bonded');
    expect(ch.contains(SonosChannel.rightFront), isTrue, reason: 'RF bonded');
    expect(ch.contains(SonosChannel.leftRear), isTrue, reason: 'LR bonded');
    expect(ch.contains(SonosChannel.rightRear), isTrue, reason: 'RR bonded');
    expect(ch.contains(SonosChannel.sub), isTrue, reason: 'SW bonded');

    // 7. Clean up the test profile (overflow menu → Delete → confirm dialog).
    await tester.tap(find.byIcon(Icons.more_vert));
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
