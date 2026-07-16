import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';

/// [SonosDevice.typeLabel] is the model shown inside bonded entities (the room
/// name is absorbed, so the type is the useful label). Regression coverage that
/// moved here when the old `entitySummary` test was removed.
SonosDevice _dev(String model, String? number) =>
    SonosDevice(uuid: 'x', roomName: 'Room', modelName: model, modelNumber: number);

void main() {
  group('typeLabel', () {
    test('strips the Sonos prefix', () {
      expect(_dev('Sonos Play:1', 'S1').typeLabel, 'Play:1');
      expect(_dev('Sonos One SL', 'S22').typeLabel, 'One SL');
    });
    test('a Sub omits the (unknowable) generation', () {
      expect(_dev('Sonos Sub', 'Sub').typeLabel, 'Sub');
      expect(_dev('Sonos Sub', null).typeLabel, 'Sub');
      expect(_dev('Sonos Sub', 'S27').typeLabel, 'Sub');
    });
    test('the Beam generation is shown from its model number', () {
      expect(_dev('Sonos Beam', 'S14').typeLabel, 'Beam (Gen 1)');
      expect(_dev('Sonos Beam', 'S31').typeLabel, 'Beam (Gen 2)');
      expect(_dev('Sonos Beam', null).typeLabel, 'Beam');
    });
  });
}
