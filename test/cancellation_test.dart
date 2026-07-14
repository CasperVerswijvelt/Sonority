import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/sonos/apply_progress.dart';
import 'package:sonority/data/sonos/cancellation.dart';

void main() {
  group('CancellationToken', () {
    test('throwIfCancelled is a no-op until cancelled, then throws', () {
      final t = CancellationToken();
      expect(t.isCancelled, isFalse);
      expect(() => t.throwIfCancelled(), returnsNormally);
      t.cancel();
      expect(t.isCancelled, isTrue);
      expect(() => t.throwIfCancelled(), throwsA(isA<OperationCancelled>()));
    });
  });

  group('interruptibleDelay', () {
    test('completes normally when never cancelled', () async {
      final t = CancellationToken();
      await interruptibleDelay(const Duration(milliseconds: 60), t,
          slice: const Duration(milliseconds: 20));
    });

    test('stops well before the full delay when cancelled mid-wait', () async {
      final t = CancellationToken();
      final sw = Stopwatch()..start();
      // Cancel shortly after starting a long delay.
      Future<void>.delayed(const Duration(milliseconds: 40), t.cancel);
      await expectLater(
        interruptibleDelay(const Duration(seconds: 10), t,
            slice: const Duration(milliseconds: 20)),
        throwsA(isA<OperationCancelled>()),
      );
      sw.stop();
      // Must abort in well under the 10s total (give generous CI headroom).
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('throws immediately if already cancelled', () async {
      final t = CancellationToken()..cancel();
      await expectLater(
        interruptibleDelay(const Duration(seconds: 5), t),
        throwsA(isA<OperationCancelled>()),
      );
    });
  });

  group('untilCancelled', () {
    test('resolves with the work result when never cancelled', () async {
      final t = CancellationToken();
      final r = await untilCancelled(
          Future<int>.delayed(const Duration(milliseconds: 20), () => 42), t);
      expect(r, 42);
    });

    test('propagates the work error when never cancelled', () async {
      final t = CancellationToken();
      await expectLater(
        untilCancelled(
            Future<int>.error(StateError('boom')), t),
        throwsA(isA<StateError>()),
      );
    });

    test('throws OperationCancelled promptly, not waiting out slow work',
        () async {
      final t = CancellationToken();
      final sw = Stopwatch()..start();
      Future<void>.delayed(const Duration(milliseconds: 30), t.cancel);
      await expectLater(
        // Work that would take 10s — must not be awaited once cancelled.
        untilCancelled(
            Future<int>.delayed(const Duration(seconds: 10), () => 1), t,
            slice: const Duration(milliseconds: 10)),
        throwsA(isA<OperationCancelled>()),
      );
      sw.stop();
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    });
  });

  group('ApplyProgress.onLog', () {
    test('emits a line for start / note / done / fail', () {
      final log = <String>[];
      final p = ApplyProgress(
        [const ApplyStep(id: 'a', label: 'Bond surrounds')],
        onLog: log.add,
      );
      p.start('a');
      p.note('a', 'attempt 1: RR not bonded yet');
      p.done('a');

      expect(log, [
        '▸ Bond surrounds',
        '    attempt 1: RR not bonded yet',
        '✓ Bond surrounds',
      ]);

      final p2 = ApplyProgress(
        [const ApplyStep(id: 'b', label: 'Bond fronts')],
        onLog: log.add,
      );
      p2.fail('b', 'LF never joined');
      expect(log.last, '✗ Bond fronts: LF never joined');
    });
  });
}
