import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/features/profiles/profile.dart';
import 'package:sonority/features/profiles/profile_ui.dart';

void main() {
  EntitySnapshot ht(String map, Map<String, String> names) => EntitySnapshot(
      kind: EntityKind.homeTheater, primaryUuid: 'BEAM', mapSet: map, names: names);

  test('HT summary groups fronts / surrounds / sub with names', () {
    final e = ht('BEAM:CC;FL:LF;FR:RF;LR:LR;RR:RR;SUB:SW', {
      'BEAM': 'Woonkamer',
      'FL': 'Left',
      'FR': 'Right',
      'LR': 'RearL',
      'RR': 'RearR',
      'SUB': 'Sub',
    });
    expect(entitySummary(e, null),
        'Fronts: Left, Right · Surrounds: RearL, RearR · Sub: Sub');
  });

  test('HT with only fronts omits empty groups', () {
    final e = ht('BEAM:CC;FL:LF;FR:RF', {'BEAM': 'WK', 'FL': 'L', 'FR': 'R'});
    expect(entitySummary(e, null), 'Fronts: L, R');
  });

  test('Amp on both fronts is listed once', () {
    final e = ht('BEAM:CC;AMP:LF,RF', {'BEAM': 'WK', 'AMP': 'Amp'});
    expect(entitySummary(e, null), 'Fronts: Amp');
  });

  test('bare soundbar HT reads "Soundbar only"', () {
    final e = ht('BEAM:CC', {'BEAM': 'WK'});
    expect(entitySummary(e, null), 'Soundbar only');
  });

  test('stereo pair summary joins both names', () {
    final e = EntitySnapshot(
      kind: EntityKind.stereoPair,
      primaryUuid: 'L',
      mapSet: 'L:LF,LF;R:RF,RF',
      names: {'L': 'Keuken L', 'R': 'Keuken R'},
    );
    expect(entitySummary(e, null), 'Keuken L + Keuken R');
  });

  test('single speaker summary falls back without a live system', () {
    final e = EntitySnapshot(
      kind: EntityKind.single,
      primaryUuid: 'X',
      mapSet: null,
      names: {'X': 'Bureau'},
    );
    expect(entitySummary(e, null), 'Standalone speaker');
  });
}
