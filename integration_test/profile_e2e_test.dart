// LIVE end-to-end test, run on a device/emulator on the same Wi-Fi as the real
// Sonos system. Drives the real UI: scan → create a profile from the current
// state → apply it → verify the home theater is intact → delete the profile.
//
// Applying a just-captured profile re-asserts the CURRENT layout, so the system
// ends where it started (the staged re-bond does tear down + rebuild the HT, and
// wipes Trueplay — re-tune in the iOS Sonos app afterward).
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
    await tester.enterText(find.byType(TextField).first, 'E2E TEST');
    await tester.pump();
    await tester.tap(find.text('Create profile'));
    await _until(tester, () => _text('E2E TEST'),
        timeout: const Duration(seconds: 10), what: 'profile saved');
    debugPrint('E2E: profile created');

    // 4. Apply it (play button → confirm dialog → Apply).
    await tester.tap(find.byTooltip('Apply'));
    await _until(tester, () => _text('Cancel') && _text('Apply'),
        timeout: const Duration(seconds: 10), what: 'confirm dialog');
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));

    // 5. Wait for the apply screen to finish. On success it auto-pops back to
    //    the profiles list; on failure it shows Retry/Close.
    var failed = false;
    await _until(
      tester,
      () {
        if (_text('Retry') && _text('Close')) {
          failed = true;
          return true;
        }
        // Back on the list when the New-profile FAB is visible again.
        return _text('New profile');
      },
      timeout: const Duration(seconds: 240),
      what: 'apply to complete',
    );
    dumpProgress(failed ? 'FAILED' : 'done');
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

    // 7. Clean up the test profile.
    await tester.tap(find.byTooltip('Delete'));
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
