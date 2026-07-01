import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/sonos/apply_progress.dart';

/// `begin()` grows a single-entity op's actions into their own persistent
/// bullets: each appended step becomes active and the previous active one flips
/// to done, so completed actions accumulate as ✓ rows instead of one flickering
/// detail line.
void main() {
  test('begin() appends an active step and completes the prior active one', () {
    late List<ApplyStep> latest;
    final p = ApplyProgress(const [], onChange: (s) => latest = s);

    p.begin('a', 'First');
    expect(latest.map((s) => s.label), ['First']);
    expect(latest.single.status, ApplyStatus.active);

    p.begin('b', 'Second');
    expect(latest.map((s) => s.label), ['First', 'Second']);
    expect(latest[0].status, ApplyStatus.done);
    expect(latest[1].status, ApplyStatus.active);
  });

  test('note() after begin() annotates the active step, not the prior one', () {
    late List<ApplyStep> latest;
    final p = ApplyProgress(const [], onChange: (s) => latest = s);
    p.begin('a', 'First');
    p.begin('b', 'Second');
    p.note('b', 'working…');
    expect(latest[0].detail, isNull);
    expect(latest[1].detail, 'working…');
  });

  test('done()/fail() finalize the current begun step', () {
    late List<ApplyStep> latest;
    final p = ApplyProgress(const [], onChange: (s) => latest = s);

    p.begin('a', 'Bond');
    p.done('a');
    expect(latest.single.status, ApplyStatus.done);

    p.begin('b', 'Name');
    p.fail('b', 'boom');
    expect(latest[1].status, ApplyStatus.failed);
    expect(latest[1].detail, 'boom');
  });
}
