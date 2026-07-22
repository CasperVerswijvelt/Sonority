import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/diagnostics_log.dart';
import 'package:sonority/features/diagnostics/diagnostics_bundle.dart';

void main() {
  // A stereo pair: the left half is visible + carries the ChannelMapSet, the
  // right half is a separate Invisible member (the case the normal UI hides).
  final system = SonosSystem(
    groups: const [
      ZoneGroup(
        coordinatorUuid: 'L',
        members: [
          ZoneGroupMember(
            uuid: 'L',
            zoneName: 'Bedroom',
            location: 'http://192.168.1.10:1400/xml/device_description.xml',
            channelMapSet: 'L:LF,LF;R:RF,RF',
          ),
          ZoneGroupMember(uuid: 'R', zoneName: 'Bedroom', invisible: true),
        ],
      ),
    ],
    devicesByUuid: {
      'L': const SonosDevice(
        uuid: 'L',
        roomName: 'Bedroom',
        modelName: 'Sonos One',
        modelNumber: 'S13',
        ip: '192.168.1.10',
        mac: 'AA:BB:CC:00:00:01',
        serial: 'SER-1',
        softwareVersion: '83.1-abc',
      ),
      'R': const SonosDevice(
        uuid: 'R',
        roomName: 'Bedroom',
        modelName: 'Sonos One',
        modelNumber: 'S13',
        ip: '192.168.1.11',
      ),
    },
  );

  group('topologyJson', () {
    test('includes the invisible member the normal UI filters out', () {
      final json = topologyJson(system);
      final members = (json['groups'] as List).first['members'] as List;
      expect(members.length, 2);
      final hidden = members.firstWhere((m) => m['uuid'] == 'R');
      expect(hidden['invisible'], true);
    });

    test('carries the raw channel-map strings and per-device identity', () {
      final json = topologyJson(system);
      final visible = ((json['groups'] as List).first['members'] as List)
          .firstWhere((m) => m['uuid'] == 'L');
      expect(visible['channelMapSet'], 'L:LF,LF;R:RF,RF');

      final dev = (json['devices'] as List).firstWhere((d) => d['uuid'] == 'L');
      expect(dev['mac'], 'AA:BB:CC:00:00:01');
      expect(dev['serial'], 'SER-1');
      expect(dev['softwareVersion'], '83.1-abc');
    });
  });

  test('topologyText marks hidden members and shows IP/MAC', () {
    final text = topologyText(system);
    expect(text, contains('[hidden]'));
    expect(text, contains('192.168.1.10'));
    expect(text, contains('AA:BB:CC:00:00:01'));
    // The channel map is broken one entry per line (not the joined blob).
    expect(text, contains('L:LF,LF'));
    expect(text, contains('R:RF,RF'));
    expect(text, isNot(contains('L:LF,LF;R:RF,RF')));
  });

  test('topologyText does not mislabel a bonded HT satellite as an orphan', () {
    final ht = SonosSystem(
      groups: const [
        ZoneGroup(
          coordinatorUuid: 'BAR',
          members: [
            ZoneGroupMember(
              uuid: 'BAR',
              zoneName: 'Living',
              htSatChanMapSet: 'BAR:CC;SAT:LR',
              satellites: [
                SonosSatellite(
                  uuid: 'SAT',
                  zoneName: 'Living',
                  channels: [SonosChannel.leftRear],
                ),
              ],
            ),
          ],
        ),
      ],
      devicesByUuid: {
        'BAR': const SonosDevice(
          uuid: 'BAR',
          roomName: 'Living',
          modelName: 'Sonos Beam',
        ),
        // The satellite is a discovered device but NOT a ZoneGroupMember.
        'SAT': const SonosDevice(
          uuid: 'SAT',
          roomName: 'Living',
          modelName: 'Sonos One',
        ),
      },
    );
    expect(topologyText(ht), isNot(contains('not in topology groups')));
  });

  test('topologyText folds an HT satellite IP into its map line (no └ dup)', () {
    final ht = SonosSystem(
      groups: const [
        ZoneGroup(
          coordinatorUuid: 'BAR',
          members: [
            ZoneGroupMember(
              uuid: 'BAR',
              zoneName: 'Living',
              htSatChanMapSet: 'BAR:CC;SAT:LR',
              satellites: [
                SonosSatellite(
                  uuid: 'SAT',
                  zoneName: 'Living',
                  channels: [SonosChannel.leftRear],
                  ip: '192.168.1.50',
                ),
              ],
            ),
          ],
        ),
      ],
      devicesByUuid: {
        'BAR': const SonosDevice(
          uuid: 'BAR',
          roomName: 'Living',
          modelName: 'Sonos Beam',
        ),
      },
    );
    final text = topologyText(ht);
    // Satellite IP is appended to its map row...
    expect(text, contains('SAT:LR · 192.168.1.50'));
    // ...the coordinator's own CC row stays plain (its IP is in its device block)...
    expect(text, isNot(contains('BAR:CC ·')));
    // ...and no residual └ line for a map-covered satellite.
    expect(text, isNot(contains('└')));
  });

  test(
    'topologyText keeps a residual └ line for a satellite absent from the map',
    () {
      final ht = SonosSystem(
        groups: const [
          ZoneGroup(
            coordinatorUuid: 'BAR',
            members: [
              ZoneGroupMember(
                uuid: 'BAR',
                zoneName: 'Living',
                htSatChanMapSet: 'BAR:CC',
                satellites: [
                  SonosSatellite(
                    uuid: 'GHOST',
                    zoneName: 'Living',
                    channels: [SonosChannel.rightRear],
                    ip: '192.168.1.51',
                  ),
                ],
              ),
            ],
          ),
        ],
        devicesByUuid: {
          'BAR': const SonosDevice(
            uuid: 'BAR',
            roomName: 'Living',
            modelName: 'Sonos Beam',
          ),
        },
      );
      expect(topologyText(ht), contains('└ [RR] GHOST · 192.168.1.51'));
    },
  );

  test('inlineJsonPrefs inlines JSON string values as real nested JSON', () {
    final out = inlineJsonPrefs({
      'profiles': '[{"id":"1","name":"My setup"}]',
      'zone_snapshot_X': '{"left":{"name":"Keuken"}}',
      'plain': 'not json',
      'count': 3,
    });
    // JSON strings become real structures (not escaped strings)...
    expect(out['profiles'], isA<List<dynamic>>());
    expect((out['profiles'] as List).first['name'], 'My setup');
    expect(out['zone_snapshot_X'], isA<Map<String, dynamic>>());
    expect((out['zone_snapshot_X'] as Map)['left']['name'], 'Keuken');
    // ...while non-JSON strings and non-string values pass through unchanged.
    expect(out['plain'], 'not json');
    expect(out['count'], 3);
    // The whole thing re-encodes without escaped-JSON-in-string.
    expect(jsonEncode(out), isNot(contains(r'\"')));
  });

  test('isAppOwnedPrefKey allows only the profiles blob + zone snapshots', () {
    // The diagnostics bundle dumps only these; a stray framework/plugin key or a
    // sibling of `profiles` must NOT ride along into an emailed bundle.
    expect(isAppOwnedPrefKey('profiles'), isTrue);
    expect(isAppOwnedPrefKey('zone_snapshot_RINCON_A_RINCON_B'), isTrue);
    expect(
      isAppOwnedPrefKey('profiles_backup'),
      isFalse,
    ); // exact match, not prefix
    expect(isAppOwnedPrefKey('flutter.someFrameworkKey'), isFalse);
    expect(
      isAppOwnedPrefKey('widget_profiles'),
      isFalse,
    ); // home_widget's own store
    expect(isAppOwnedPrefKey('anything_else'), isFalse);
  });

  group('settingsReadPlan role-gating', () {
    // An HT: Arc Ultra coordinator with an Amp bonded as fronts, plus a
    // standalone plain speaker in its own group.
    final htSystem = SonosSystem(
      groups: const [
        ZoneGroup(coordinatorUuid: 'BAR', members: [
          ZoneGroupMember(
            uuid: 'BAR',
            zoneName: 'Cinema',
            location: 'http://192.168.1.20:1400/xml/device_description.xml',
            htSatChanMapSet: 'BAR:CC;AMP:LF,RF',
            satellites: [
              SonosSatellite(
                uuid: 'AMP',
                zoneName: 'Cinema',
                channels: [SonosChannel.leftFront, SonosChannel.rightFront],
              ),
            ],
          ),
        ]),
        ZoneGroup(coordinatorUuid: 'ONE', members: [
          ZoneGroupMember(uuid: 'ONE', zoneName: 'Kitchen'),
        ]),
      ],
      devicesByUuid: {
        'BAR': const SonosDevice(
            uuid: 'BAR', roomName: 'Cinema', modelName: 'Sonos Arc Ultra'),
        'AMP': const SonosDevice(
            uuid: 'AMP', roomName: 'Cinema', modelName: 'Sonos Amp'),
        'ONE': const SonosDevice(
            uuid: 'ONE', roomName: 'Kitchen', modelName: 'Sonos One'),
      },
    );

    final plan = settingsReadPlan(htSystem);

    test('soundbar / HT coordinator gets the extended EQ bundle', () {
      expect(plan['BAR']!.audio, isTrue);
      expect(plan['BAR']!.extendedEq, isTrue);
    });

    test('HT satellite skips audio reads (they 803)', () {
      expect(plan['AMP']!.audio, isFalse);
      expect(plan['AMP']!.extendedEq, isFalse);
    });

    test('plain standalone speaker reads audio but not extended EQ', () {
      expect(plan['ONE']!.audio, isTrue);
      expect(plan['ONE']!.extendedEq, isFalse);
    });

    test('zone coordinator with a bonded Sub gets the extended EQ bundle', () {
      // A zone (ChannelMapSet, no soundbar) with a Sub bonded as SW — the sub
      // level/crossover ride the coordinator's GetEQ, so it must read extended.
      final zoneWithSub = SonosSystem(
        groups: const [
          ZoneGroup(coordinatorUuid: 'Z1', members: [
            ZoneGroupMember(
              uuid: 'Z1',
              zoneName: 'Loft',
              location: 'http://192.168.1.30:1400/xml/device_description.xml',
              channelMapSet: 'Z1:LF,RF;Z2:LF,RF;ZSUB:SW',
            ),
            ZoneGroupMember(uuid: 'Z2', zoneName: 'Loft', invisible: true),
            ZoneGroupMember(uuid: 'ZSUB', zoneName: 'Loft', invisible: true),
          ]),
        ],
        devicesByUuid: {
          'Z1': const SonosDevice(
              uuid: 'Z1', roomName: 'Loft', modelName: 'Sonos Era 100'),
          'Z2': const SonosDevice(
              uuid: 'Z2', roomName: 'Loft', modelName: 'Sonos Era 100'),
          'ZSUB': const SonosDevice(
              uuid: 'ZSUB', roomName: 'Loft', modelName: 'Sonos Sub'),
        },
      );
      final p = settingsReadPlan(zoneWithSub);
      expect(p['Z1']!.extendedEq, isTrue, reason: 'coordinator carries sub EQ');
      // A plain zone member without the sub map stays bass/treble/loudness only.
      expect(p['Z2']!.extendedEq, isFalse);
    });
  });

  test('DiagnosticsLog is a capped ring buffer, oldest dropped first', () {
    DiagnosticsLog.clear();
    for (var i = 0; i < 600; i++) {
      DiagnosticsLog.add('line $i');
    }
    final lines = DiagnosticsLog.lines;
    expect(lines.length, 500);
    // The first 100 were evicted; the newest survives.
    expect(lines.first, contains('line 100'));
    expect(lines.last, contains('line 599'));
    DiagnosticsLog.clear();
  });
}
