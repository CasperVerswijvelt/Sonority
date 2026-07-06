import 'package:flutter_test/flutter_test.dart';

import 'package:sonority/data/sonos/apply_progress.dart';

void main() {
  ApplyProgress tracker(List<String> log) => ApplyProgress(
        const [
          ApplyStep(id: 'e1', label: 'Home Theater: Living Room'),
          ApplyStep(id: 'e2', label: 'Single: Kitchen'),
        ],
        onLog: log.add,
      );

  test('seedSubs inserts pending children right after the parent', () {
    final p = tracker([]);
    p.seedSubs('e1', [('e1/bond', 'Bond 3 speakers'), ('e1/names', 'Restore room name')]);
    expect(p.steps.map((s) => s.id), ['e1', 'e1/bond', 'e1/names', 'e2']);
    expect(p.steps[1].parentId, 'e1');
    expect(p.steps[1].status, ApplyStatus.pending);
  });

  test('startSub activates a seeded child and refreshes its label', () {
    final p = tracker([]);
    p.seedSubs('e1', [('e1/bond', 'Bond speakers')]);
    p.start('e1');
    p.startSub('e1', 'e1/bond', 'Bond 2 speakers + sub');
    final bond = p.steps.firstWhere((s) => s.id == 'e1/bond');
    expect(bond.status, ApplyStatus.active);
    expect(bond.label, 'Bond 2 speakers + sub');
  });

  test('a conditional phase inserts before pending seeded siblings', () {
    final p = tracker([]);
    p.seedSubs('e1', [('e1/bond', 'Bond 3 speakers'), ('e1/names', 'Restore room name')]);
    p.start('e1');
    p.startSub('e1', 'e1/free', 'Free conflicting speakers');
    expect(p.steps.map((s) => s.id), ['e1', 'e1/free', 'e1/bond', 'e1/names', 'e2']);
  });

  test('starting the next phase completes the previous one', () {
    final p = tracker([]);
    p.start('e1');
    p.startSub('e1', 'e1/free', 'Free conflicting speakers');
    p.noteActive('freeing Kitchen');
    p.startSub('e1', 'e1/bond', 'Bond 3 speakers');
    final free = p.steps.firstWhere((s) => s.id == 'e1/free');
    expect(free.status, ApplyStatus.done);
    expect(free.detail, isNull); // transient verbose note cleared
    expect(p.steps.firstWhere((s) => s.id == 'e1/bond').status,
        ApplyStatus.active);
  });

  test('noteActive updates the active child, falls back to active parent', () {
    final p = tracker([]);
    p.start('e1');
    p.noteActive('working'); // no child yet → parent
    expect(p.steps.first.detail, 'working');
    p.startSub('e1', 'e1/bond', 'Bond 3 speakers');
    p.noteActive('attempt 2: re-asserting');
    expect(p.steps.firstWhere((s) => s.id == 'e1/bond').detail,
        'attempt 2: re-asserting');
  });

  test('doneSub short-circuits the active phase with a detail', () {
    final p = tracker([]);
    p.start('e1');
    p.startSub('e1', 'e1/bond', 'Bond 3 speakers');
    p.doneSub(detail: 'layout unchanged — nothing to do');
    final bond = p.steps.firstWhere((s) => s.id == 'e1/bond');
    expect(bond.status, ApplyStatus.done);
    expect(bond.detail, 'layout unchanged — nothing to do');
  });

  test('parent done completes the active child and drops leftover pending ones',
      () {
    final p = tracker([]);
    p.seedSubs('e1', [('e1/bond', 'Bond'), ('e1/settings', 'Restore settings')]);
    p.start('e1');
    p.startSub('e1', 'e1/bond', 'Bond 3 speakers');
    p.done('e1');
    expect(p.steps.firstWhere((s) => s.id == 'e1/bond').status,
        ApplyStatus.done);
    expect(p.steps.any((s) => s.id == 'e1/settings'), isFalse);
  });

  test('parent fail propagates the reason to the active child', () {
    final p = tracker([]);
    p.start('e1');
    p.startSub('e1', 'e1/bond', 'Bond 3 speakers');
    p.fail('e1', 'satellite never joined');
    final bond = p.steps.firstWhere((s) => s.id == 'e1/bond');
    expect(bond.status, ApplyStatus.failed);
    expect(bond.detail, 'satellite never joined');
    expect(p.steps.first.status, ApplyStatus.failed);
  });

  test('the next entity starts with a clean phase slate', () {
    final p = tracker([]);
    p.start('e1');
    p.startSub('e1', 'e1/bond', 'Bond 3 speakers');
    p.done('e1');
    p.start('e2');
    p.noteActive('freeing'); // must land on e2, not a stale e1 child
    expect(p.steps.firstWhere((s) => s.id == 'e2').detail, 'freeing');
  });

  test('raw log indents child lines', () {
    final log = <String>[];
    final p = tracker(log);
    p.start('e1');
    p.startSub('e1', 'e1/bond', 'Bond 3 speakers');
    expect(log.last, '  ▸ Bond 3 speakers');
  });
}
