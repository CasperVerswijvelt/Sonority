import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/room_calibration.dart';
import 'package:sonority/features/widgets/trueplay_control.dart';

// The per-speaker breakdown behind an aggregate like "5/6 tuned · 0/6 active".
// A user's Arc Ultra report ("not sure why it's 5/6") is the case it answers:
// the counter names how many, never which.
void main() {
  const bar = SonosDevice(
      uuid: 'BAR',
      roomName: 'Living Room HT',
      modelName: 'Sonos Arc Ultra',
      ip: '192.168.1.20');
  const left = SonosDevice(
      uuid: 'LEFT',
      roomName: 'Living Room HT',
      modelName: 'Sonos Five',
      ip: '192.168.1.21');
  const right = SonosDevice(
      uuid: 'RIGHT',
      roomName: 'Living Room HT',
      modelName: 'Sonos Five',
      ip: '192.168.1.22');
  const noIp = SonosDevice(
      uuid: 'NOIP', roomName: 'Living Room HT', modelName: 'Sonos Sub');

  const on = RoomCalibration(available: true, enabled: true);
  const storedOff = RoomCalibration(available: true, enabled: false);
  const none = RoomCalibration(available: false, enabled: false);

  test('maps each speaker to its own state, in the order given', () {
    final rows = trueplayRows(
      [bar, left, right],
      const {'BAR': on, 'LEFT': storedOff, 'RIGHT': none},
    );
    expect(rows.map((r) => r.label), ['Arc Ultra', 'Five', 'Five']);
    expect(rows.map((r) => r.state), [
      TrueplayRowState.active,
      TrueplayRowState.tunedOff,
      TrueplayRowState.notTuned,
    ]);
  });

  test('a speaker that could not be read is kept as unknown, not dropped', () {
    // `right` has an IP, so it stays in the on-screen denominator while its
    // failed read keeps it out of the numerator — that is what renders "1/2"
    // rather than "1/1", and without a row the missing speaker is
    // unattributable. `noIp` can't be read either and leaves both counts.
    final rows = trueplayRows([bar, right, noIp], const {'BAR': on});
    expect(rows.length, 3);
    expect(rows[1].state, TrueplayRowState.unknown);
    expect(rows[2].state, TrueplayRowState.unknown);
  });

  test('a uniform set collapses to one state, so the breakdown can stay hidden',
      () {
    // The widget only shows rows when the states differ — an all-active home
    // theater already says everything in its one-line subtitle.
    final uniform = trueplayRows(
      [bar, left, right],
      const {'BAR': on, 'LEFT': on, 'RIGHT': on},
    );
    expect(uniform.map((r) => r.state).toSet(), hasLength(1));

    final mixed = trueplayRows(
      [bar, left, right],
      const {'BAR': on, 'LEFT': on, 'RIGHT': storedOff},
    );
    expect(mixed.map((r) => r.state).toSet(), hasLength(greaterThan(1)));
  });

  test('nothing loaded yet is uniformly unknown, so it never flashes mid-load',
      () {
    final rows = trueplayRows([bar, left], const {});
    expect(rows.map((r) => r.state).toSet(), {TrueplayRowState.unknown});
  });
}
