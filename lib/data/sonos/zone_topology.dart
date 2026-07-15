import 'package:xml/xml.dart';

import '../models/sonos_models.dart';
import 'channel_map.dart';
import 'soap_client.dart';

/// Reads the system layout via `ZoneGroupTopology.GetZoneGroupState`.
class ZoneTopologyClient {
  final SonosSoapClient _soap;
  ZoneTopologyClient(this._soap);

  static const _service = 'urn:schemas-upnp-org:service:ZoneGroupTopology:1';
  static const _control = '/ZoneGroupTopology/Control';

  /// Query any reachable player [ip]; it returns the whole system's topology.
  Future<List<ZoneGroup>> getZoneGroups(String ip) async =>
      parseZoneGroupState(await getRawState(ip));

  /// The raw, unescaped inner `<ZoneGroupState>` XML — the double-decoded
  /// topology document, for the diagnostics bundle (and reused by
  /// [getZoneGroups]). Returns `''` if the response carries no state element.
  Future<String> getRawState(String ip) async {
    final body = await _soap.call(
      ip: ip,
      controlPath: _control,
      serviceType: _service,
      action: 'GetZoneGroupState',
    );

    // The response carries the topology as an escaped XML string inside
    // <ZoneGroupState>. innerText unescapes it; parse again.
    final stateEls = body.findAllElements('ZoneGroupState');
    return stateEls.isEmpty ? '' : stateEls.first.innerText;
  }

  /// Parses the inner `<ZoneGroupState>` XML into groups. Public for testing.
  static List<ZoneGroup> parseZoneGroupState(String xml) {
    if (xml.isEmpty) return const [];
    final doc = XmlDocument.parse(xml);
    final groups = <ZoneGroup>[];

    for (final group in doc.findAllElements('ZoneGroup')) {
      final coordinator = group.getAttribute('Coordinator') ?? '';
      final members = <ZoneGroupMember>[];

      for (final member in group.findElements('ZoneGroupMember')) {
        final uuid = member.getAttribute('UUID') ?? '';
        if (uuid.isEmpty) continue;
        final mapSet = member.getAttribute('HTSatChanMapSet');
        final satellites = <SonosSatellite>[];

        // Channels per satellite live in the primary's HTSatChanMapSet.
        final channelsByUuid = <String, List<SonosChannel>>{};
        if (mapSet != null && mapSet.isNotEmpty) {
          for (final e in ChannelMap.parse(mapSet).entries) {
            channelsByUuid[e.uuid] = e.channels;
          }
        }

        for (final sat in member.findElements('Satellite')) {
          final satUuid = sat.getAttribute('UUID') ?? '';
          if (satUuid.isEmpty) continue;
          satellites.add(SonosSatellite(
            uuid: satUuid,
            zoneName: sat.getAttribute('ZoneName') ?? '',
            channels: channelsByUuid[satUuid] ?? const [],
            ip: _ipFromLocation(sat.getAttribute('Location')),
          ));
        }

        members.add(ZoneGroupMember(
          uuid: uuid,
          zoneName: member.getAttribute('ZoneName') ?? '',
          location: member.getAttribute('Location'),
          htSatChanMapSet: mapSet,
          satellites: satellites,
          invisible: member.getAttribute('Invisible') == '1',
          channelMapSet: member.getAttribute('ChannelMapSet'),
        ));
      }

      if (members.isNotEmpty) {
        groups.add(ZoneGroup(coordinatorUuid: coordinator, members: members));
      }
    }
    return groups;
  }

  static String? _ipFromLocation(String? location) {
    if (location == null) return null;
    return Uri.tryParse(location)?.host;
  }
}
