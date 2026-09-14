import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/sonos/room_calibration.dart';
import 'package:sonority/data/sonos/soap_client.dart';
import 'package:sonority/data/sonos/sonos_repository.dart';
import 'package:xml/xml.dart';

/// Measured end to end on real hardware (EXP-23, 2026-09-14): a speaker whose
/// Trueplay tuning SURVIVES being absorbed into a home theater still comes back
/// `available=1 enabled=0` — Sonos keeps the coefficients and switches the
/// calibration off. Six stable reads, so it is not the oracle decaying.
///
/// So an apply that promises "keeps Trueplay" has to put the switch back. These
/// pin the three things it must not get wrong.
class _Soap extends SonosSoapClient {
  final bool available;
  final bool enabled;
  int gets = 0;
  final sets = <String>[];

  _Soap({required this.available, required this.enabled});

  @override
  Future<XmlElement> call({
    required String ip,
    required String controlPath,
    required String serviceType,
    required String action,
    Map<String, String> args = const {},
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (action == 'GetRoomCalibrationStatus') {
      gets++;
      return XmlDocument.parse(
              '<Body><RoomCalibrationAvailable>${available ? 1 : 0}'
              '</RoomCalibrationAvailable><RoomCalibrationEnabled>'
              '${enabled ? 1 : 0}</RoomCalibrationEnabled></Body>')
          .rootElement;
    }
    if (action == 'SetRoomCalibrationStatus') {
      sets.add(args['RoomCalibrationEnabled'] ?? '');
      return XmlDocument.parse('<Body/>').rootElement;
    }
    throw StateError('unexpected action $action');
  }
}

void main() {
  ({SonosRepository repo, _Soap soap}) fixture(
          {required bool available, required bool enabled}) {
    final soap = _Soap(available: available, enabled: enabled);
    return (
      repo: SonosRepository(calibration: RoomCalibrationClient(soap)),
      soap: soap
    );
  }

  test('a surviving tuning that Sonos switched off is switched back on',
      () async {
    final f = fixture(available: true, enabled: false);
    expect(await f.repo.restoreRoomCalibration('1.2.3.4'), isTrue);
    expect(f.soap.sets, ['1']);
  });

  test('a tuning the bond DESTROYED is never switched on over nothing',
      () async {
    // available=0 means there are no coefficients. Enabling would light up a
    // Trueplay indicator with nothing behind it — the state EXP-23 calls 0/1.
    final f = fixture(available: false, enabled: false);
    expect(await f.repo.restoreRoomCalibration('1.2.3.4'), isFalse);
    expect(f.soap.sets, isEmpty);
  });

  test('a speaker Sonos left switched on is not rewritten', () async {
    final f = fixture(available: true, enabled: true);
    expect(await f.repo.restoreRoomCalibration('1.2.3.4'), isFalse);
    expect(f.soap.sets, isEmpty);
    expect(f.soap.gets, 1, reason: 'one read, no write');
  });
}
