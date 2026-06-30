// Interactive L/R audio-routing test for zone configs. Forms a bonded config,
// then plays a looping "left"(L)/"right"(R) track on the coordinator so you can
// hear which physical speaker outputs which channel — i.e. whether Sonos
// actually HONORS the channel map (not just accepts it). Throwaway harness.
//
//   dart run tool/lr_audiotest.dart snapshot <uuid,uuid,…>          # save standalone names (run once)
//   dart run tool/lr_audiotest.dart play "<coord:CH;uuid:CH;…>" <url> [vol]
//   dart run tool/lr_audiotest.dart stop                            # dissolve live config + restore names
//
// play dissolves any existing config first, so you can chain configs.

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/av_transport.dart';
import 'package:sonority/data/sonos/channel_map.dart';
import 'package:sonority/data/sonos/device_properties.dart';
import 'package:sonority/data/sonos/soap_client.dart';
import 'package:sonority/data/sonos/zone_topology.dart';

import 'discover_util.dart';

final _namesFile = File('/tmp/lrtest/names.json');
final _props = DevicePropertiesClient(SonosSoapClient());
final _av = AvTransportClient(SonosSoapClient());
final _soap = SonosSoapClient();
final _topo = ZoneTopologyClient(SonosSoapClient());

Future<void> main(List<String> argv) async {
  if (argv.isEmpty) {
    print('Usage: snapshot <uuids> | play "<map>" <url> [vol] | stop');
    exit(64);
  }
  final devices = await discoverDevices();
  String? ipOf(String uuid) =>
      devices.where((d) => d.uuid == uuid).map((d) => d.ip).firstOrNull;
  final anyIp = devices.first.ip!;

  Future<ZoneGroupMember?> liveConfig() async => (await _topo.getZoneGroups(anyIp))
      .expand((g) => g.members)
      .where((m) => !m.invisible && (m.channelMapSet ?? '').isNotEmpty)
      .cast<ZoneGroupMember?>()
      .firstOrNull;

  Future<void> restoreNames(Iterable<String> uuids) async {
    if (!_namesFile.existsSync()) return;
    final saved = (jsonDecode(_namesFile.readAsStringSync()) as Map)
        .cast<String, dynamic>();
    for (final u in uuids) {
      final want = saved[u] as Map?;
      final ip = ipOf(u);
      if (want == null || ip == null) continue;
      try {
        if ((await _props.getZoneAttributes(ip)).zoneName != want['name']) {
          await _props.setZoneAttributes(
              ip,
              ZoneAttributes(
                  zoneName: want['name'] as String,
                  icon: want['icon'] as String? ?? '',
                  configuration: want['config'] as String? ?? ''));
        }
      } catch (_) {}
    }
  }

  Future<void> dissolveExisting() async {
    final m = await liveConfig();
    if (m == null) return;
    final ip = m.ip ?? ipOf(m.uuid);
    final cms = m.channelMapSet!;
    final uuids = cms
        .split(';')
        .where((p) => p.contains(':'))
        .map((p) => p.split(':').first.trim())
        .toList();
    print('  dissolving existing: $cms');
    if (ip != null) {
      try {
        await _soap.call(
            ip: ip,
            controlPath: '/MediaRenderer/AVTransport/Control',
            serviceType: 'urn:schemas-upnp-org:service:AVTransport:1',
            action: 'Stop',
            args: {'InstanceID': '0'});
      } catch (_) {}
      await _av.becomeCoordinatorOfStandaloneGroup(ip);
      await Future<void>.delayed(const Duration(seconds: 6));
      await _props.separateBondedZones(ip: ip, channelMapSet: cms);
      await Future<void>.delayed(const Duration(seconds: 6));
    }
    await restoreNames(uuids);
  }

  final cmd = argv.first;
  switch (cmd) {
    case 'snapshot':
      final uuids = argv[1].split(',').map((s) => s.trim()).toList();
      final out = <String, dynamic>{};
      for (final u in uuids) {
        final ip = ipOf(u);
        if (ip == null) {
          print('  ⚠️ no ip for $u');
          continue;
        }
        final a = await _props.getZoneAttributes(ip);
        out[u] = {'name': a.zoneName, 'icon': a.icon, 'config': a.configuration};
        print('  $u = "${a.zoneName}"');
      }
      _namesFile.parent.createSync(recursive: true);
      _namesFile.writeAsStringSync(jsonEncode(out));
      print('✅ saved ${out.length} names to ${_namesFile.path}');

    case 'stop':
      await dissolveExisting();
      print('✅ stopped + dissolved + names restored');

    case 'freesat':
      // freesat <barUuid> <satUuid> — unbond one HT satellite from the bar.
      final barIp = ipOf(argv[1]);
      if (barIp == null) {
        print('❌ no ip for bar ${argv[1]}');
        exit(1);
      }
      await _props.removeHtSatellite(soundbarIp: barIp, satelliteUuid: argv[2]);
      print('✅ freed ${argv[2]} from ${argv[1]}');

    case 'addht':
      // addht <barUuid> "<BAR:CC;SAT:CH;…>" — re-bond an HT map onto the bar.
      final barIp = ipOf(argv[1]);
      if (barIp == null) {
        print('❌ no ip for bar ${argv[1]}');
        exit(1);
      }
      await _props.addHtSatellite(soundbarIp: barIp, map: ChannelMap.parse(argv[2]));
      print('✅ applied HT map ${argv[2]}');

    case 'play':
      final map = argv[1];
      final url = argv[2];
      final vol = argv.length > 3 ? argv[3] : '30';
      final coordUuid = map.split(':').first.trim();
      final ip = ipOf(coordUuid);
      if (ip == null) {
        print('❌ no ip for coordinator $coordUuid');
        exit(1);
      }
      await dissolveExisting();
      print('  forming: $map');
      var formed = false;
      for (var attempt = 0; attempt < 2 && !formed; attempt++) {
        try {
          await _props.addBondedZones(ip: ip, channelMapSet: map);
        } catch (_) {}
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(const Duration(seconds: 3));
          final m = await liveConfig();
          if (m != null && m.uuid == coordUuid) {
            formed = true;
            break;
          }
        }
      }
      if (!formed) {
        print('❌ config did not form');
        exit(1);
      }
      await _soap.call(
          ip: ip,
          controlPath: '/MediaRenderer/RenderingControl/Control',
          serviceType: 'urn:schemas-upnp-org:service:RenderingControl:1',
          action: 'SetVolume',
          args: {'InstanceID': '0', 'Channel': 'Master', 'DesiredVolume': vol});
      await _soap.call(
          ip: ip,
          controlPath: '/MediaRenderer/AVTransport/Control',
          serviceType: 'urn:schemas-upnp-org:service:AVTransport:1',
          action: 'SetAVTransportURI',
          args: {'InstanceID': '0', 'CurrentURI': url, 'CurrentURIMetaData': ''});
      await _soap.call(
          ip: ip,
          controlPath: '/MediaRenderer/AVTransport/Control',
          serviceType: 'urn:schemas-upnp-org:service:AVTransport:1',
          action: 'Play',
          args: {'InstanceID': '0', 'Speed': '1'});
      print('▶️  playing on coordinator $coordUuid (vol $vol) — listen now.');

    default:
      print('unknown command: $cmd');
      exit(64);
  }
}
