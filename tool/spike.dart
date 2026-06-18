// Networking spike: validates the read path against real hardware WITHOUT
// touching any bonding action. Run from the project root, on the same Wi-Fi as
// your Sonos system:
//
//   dart run tool/spike.dart
//
// It discovers players, prints each one, then dumps the full topology including
// every home theater's raw HTSatChanMapSet — the string we need to confirm the
// exact dedicated-front recipe before wiring up writes.
//
// This is read-only. It never calls AddHTSatellite / RemoveHTSatellite.

// ignore_for_file: avoid_print

import 'package:soyes/data/sonos/device_description.dart';
import 'package:soyes/data/sonos/soap_client.dart';
import 'package:soyes/data/sonos/ssdp_discovery.dart';
import 'package:soyes/data/sonos/zone_topology.dart';

Future<void> main() async {
  print('🔎 SSDP discovery (4s)…');
  final locations = await SsdpDiscovery().discover();
  if (locations.isEmpty) {
    print('❌ No Sonos players responded. Same Wi-Fi? Local network allowed?');
    return;
  }
  print('Found ${locations.length} location(s):');
  for (final l in locations) {
    print('  • $l');
  }

  final descriptions = DeviceDescriptionClient();
  final devices = <String, String>{}; // uuid -> "Room (Model) @ ip"
  String? anyIp;
  print('\n📇 Device descriptions:');
  for (final loc in locations) {
    try {
      final d = await descriptions.fetch(loc);
      anyIp ??= d.ip;
      devices[d.uuid] = '${d.roomName} (${d.modelName}) @ ${d.ip}';
      print('  • ${d.roomName.padRight(18)} ${d.modelName.padRight(18)} '
          '${d.uuid}  ${d.isSoundbar ? "[SOUNDBAR]" : ""}');
    } catch (e) {
      print('  ! failed $loc: $e');
    }
  }

  if (anyIp == null) {
    print('❌ Could not read any device description.');
    return;
  }

  print('\n🗺️  Topology (via $anyIp):');
  final groups =
      await ZoneTopologyClient(SonosSoapClient()).getZoneGroups(anyIp);
  for (final g in groups) {
    final coord = g.coordinator;
    print('\n  ▸ Group [coordinator: ${coord?.zoneName ?? g.coordinatorUuid}]');
    for (final m in g.members) {
      final tag = m.isHomeTheater ? ' 🎬 HOME THEATER' : '';
      print('    - ${m.zoneName} (${m.uuid})$tag');
      if (m.htSatChanMapSet != null) {
        print('      HTSatChanMapSet = ${m.htSatChanMapSet}');
      }
      for (final s in m.satellites) {
        final chans = s.channels.map((c) => c.token).join(',');
        print('        · satellite ${s.zoneName} [$chans] ${s.uuid}');
      }
      if (m.hasDedicatedFronts) {
        print('      ✅ Dedicated fronts detected.');
      }
    }
  }

  print('\nDone. Copy any HTSatChanMapSet above to confirm the front recipe.');
}
