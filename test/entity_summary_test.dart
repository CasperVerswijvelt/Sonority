import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/features/profiles/profile.dart';
import 'package:sonority/features/profiles/profile_ui.dart';

void main() {
  EntitySnapshot ht(String map) => EntitySnapshot(
      kind: EntityKind.homeTheater, primaryUuid: 'BEAM', mapSet: map, names: const {});

  // A system where every uuid resolves to a typed device.
  final system = SonosSystem(
    groups: const [],
    devicesByUuid: {
      'BEAM': _dev('BEAM', 'Sonos Beam', 'S31'),
      'FL': _dev('FL', 'Sonos One SL', 'S22'),
      'FR': _dev('FR', 'Sonos One SL', 'S22'),
      'LR': _dev('LR', 'Sonos Play:1', 'S1'),
      'RR': _dev('RR', 'Sonos Play:1', 'S1'),
      'SUB': _dev('SUB', 'Sonos Sub', 'Sub'),
      'AMP': _dev('AMP', 'Sonos Amp', 'S16'),
    },
  );

  group('typeLabel', () {
    test('strips the Sonos prefix', () {
      expect(_dev('x', 'Sonos Play:1', 'S1').typeLabel, 'Play:1');
      expect(_dev('x', 'Sonos One SL', 'S22').typeLabel, 'One SL');
    });
    test('Sub (Gen 1/2) reports model number "Sub"', () {
      expect(_dev('x', 'Sonos Sub', 'Sub').typeLabel, 'Sub (Gen 1/2)');
      expect(_dev('x', 'Sonos Sub', null).typeLabel, 'Sub (Gen 1/2)');
    });
    test('a newer Sub surfaces its model code', () {
      expect(_dev('x', 'Sonos Sub', 'S27').typeLabel, 'Sub (S27)');
    });
  });

  test('HT summary groups by type (per speaker), with sub generation', () {
    final e = ht('BEAM:CC;FL:LF;FR:RF;LR:LR;RR:RR;SUB:SW');
    expect(entitySummary(e, system),
        'Fronts: One SL, One SL · Surrounds: Play:1, Play:1 · Sub: Sub (Gen 1/2)');
  });

  test('two same-type surrounds are both shown', () {
    final e = ht('BEAM:CC;LR:LR;RR:RR');
    expect(entitySummary(e, system), 'Surrounds: Play:1, Play:1');
  });

  test('Amp on both fronts is listed once', () {
    final e = ht('BEAM:CC;AMP:LF,RF');
    expect(entitySummary(e, system), 'Fronts: Amp');
  });

  test('bare soundbar HT reads "Soundbar only"', () {
    expect(entitySummary(ht('BEAM:CC'), system), 'Soundbar only');
  });

  test('stereo pair summary joins both types', () {
    final e = EntitySnapshot(
      kind: EntityKind.stereoPair,
      primaryUuid: 'LR',
      mapSet: 'LR:LF,LF;RR:RF,RF',
      names: const {},
    );
    expect(entitySummary(e, system), 'Play:1 + Play:1');
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

SonosDevice _dev(String uuid, String model, String? number) => SonosDevice(
    uuid: uuid, roomName: 'Room', modelName: model, modelNumber: number);
