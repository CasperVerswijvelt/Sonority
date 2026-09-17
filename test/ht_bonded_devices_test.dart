import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/features/home_theater/home_theater_screen.dart';

// The set the Trueplay counter is handed. Its size IS the denominator, and the
// denominator is what decides whether the destructive-enable confirm fires, so
// a speaker missing here is a speaker that can be silently wiped.
void main() {
  const bar = SonosDevice(
      uuid: 'BAR',
      roomName: 'Living Room',
      modelName: 'Sonos Beam',
      ip: '192.168.1.20');
  const subA = SonosDevice(
      uuid: 'SUBA',
      roomName: 'Living Room',
      modelName: 'Sonos Sub',
      ip: '192.168.1.21');
  const subB = SonosDevice(
      uuid: 'SUBB',
      roomName: 'Living Room',
      modelName: 'Sonos Sub',
      ip: '192.168.1.22');
  const amp = SonosDevice(
      uuid: 'AMP',
      roomName: 'Living Room',
      modelName: 'Sonos Amp',
      ip: '192.168.1.23');

  SonosSystem systemWith(String mapSet, Map<String, SonosDevice> devices) {
    final ht = ZoneGroupMember(
      uuid: 'BAR',
      zoneName: 'Living Room',
      htSatChanMapSet: mapSet,
    );
    return SonosSystem(
      groups: [ZoneGroup(coordinatorUuid: 'BAR', members: [ht])],
      devicesByUuid: devices,
    );
  }

  test('a DUAL-SUB home theater keeps both subs', () {
    // `channelAssignments` is keyed by channel, so both `SW` entries collapse
    // to one uuid there. Reading the count off that map dropped a Sub out of
    // the denominator, which let an incomplete set read complete.
    final system = systemWith(
      'BAR:CC;SUBA:SW;SUBB:SW',
      const {'BAR': bar, 'SUBA': subA, 'SUBB': subB},
    );
    final got = htBondedDevices(system, system.memberByUuid('BAR')!);
    expect(got.map((d) => d.uuid).toSet(), {'BAR', 'SUBA', 'SUBB'});
  });

  test('a line-out box driving the fronts is still excluded', () {
    // An Amp has no drivers of its own, so it holds no tuning to count.
    final system = systemWith(
      'BAR:CC;AMP:LF,RF;SUBA:SW',
      const {'BAR': bar, 'AMP': amp, 'SUBA': subA},
    );
    final got = htBondedDevices(system, system.memberByUuid('BAR')!);
    expect(got.map((d) => d.uuid).toSet(), {'BAR', 'SUBA'});
  });

  test('a satellite missing from devicesByUuid is dropped, as before', () {
    // Not fixed here: the known hole CLAUDE.md records. Pinned so a change
    // shows up rather than passing silently.
    final system = systemWith(
      'BAR:CC;SUBA:SW;GHOST:LR',
      const {'BAR': bar, 'SUBA': subA},
    );
    final got = htBondedDevices(system, system.memberByUuid('BAR')!);
    expect(got.map((d) => d.uuid).toSet(), {'BAR', 'SUBA'});
  });
}
