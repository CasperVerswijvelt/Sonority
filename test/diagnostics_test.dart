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
      ZoneGroup(coordinatorUuid: 'L', members: [
        ZoneGroupMember(
          uuid: 'L',
          zoneName: 'Bedroom',
          location: 'http://192.168.1.10:1400/xml/device_description.xml',
          channelMapSet: 'L:LF,LF;R:RF,RF',
        ),
        ZoneGroupMember(uuid: 'R', zoneName: 'Bedroom', invisible: true),
      ]),
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
    expect(text, contains('L:LF,LF;R:RF,RF'));
  });

  test('topologyText does not mislabel a bonded HT satellite as an orphan', () {
    final ht = SonosSystem(
      groups: const [
        ZoneGroup(coordinatorUuid: 'BAR', members: [
          ZoneGroupMember(
            uuid: 'BAR',
            zoneName: 'Living',
            htSatChanMapSet: 'BAR:CC;SAT:LR',
            satellites: [
              SonosSatellite(
                  uuid: 'SAT', zoneName: 'Living', channels: [SonosChannel.leftRear]),
            ],
          ),
        ]),
      ],
      devicesByUuid: {
        'BAR': const SonosDevice(uuid: 'BAR', roomName: 'Living', modelName: 'Sonos Beam'),
        // The satellite is a discovered device but NOT a ZoneGroupMember.
        'SAT': const SonosDevice(uuid: 'SAT', roomName: 'Living', modelName: 'Sonos One'),
      },
    );
    expect(topologyText(ht), isNot(contains('not in topology groups')));
  });

  test('inlineJsonPrefs inlines JSON string values as real nested JSON', () {
    final out = inlineJsonPrefs({
      'profiles': '[{"id":"1","name":"My setup"}]',
      'pair_snapshot_X': '{"left":{"name":"Keuken"}}',
      'plain': 'not json',
      'count': 3,
    });
    // JSON strings become real structures (not escaped strings)...
    expect(out['profiles'], isA<List<dynamic>>());
    expect((out['profiles'] as List).first['name'], 'My setup');
    expect(out['pair_snapshot_X'], isA<Map<String, dynamic>>());
    expect((out['pair_snapshot_X'] as Map)['left']['name'], 'Keuken');
    // ...while non-JSON strings and non-string values pass through unchanged.
    expect(out['plain'], 'not json');
    expect(out['count'], 3);
    // The whole thing re-encodes without escaped-JSON-in-string.
    expect(jsonEncode(out), isNot(contains(r'\"')));
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
