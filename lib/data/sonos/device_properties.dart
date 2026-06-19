import 'package:xml/xml.dart';

import 'channel_map.dart';
import 'soap_client.dart';

/// A speaker's room name + icon/configuration, captured so it can be restored
/// after un-pairing (Sonos doesn't reliably restore the hidden speaker's name).
class ZoneAttributes {
  final String zoneName;
  final String icon;
  final String configuration;
  const ZoneAttributes({
    required this.zoneName,
    required this.icon,
    required this.configuration,
  });
}

/// Wraps the `DeviceProperties` bonding actions on a home-theater primary.
///
/// This is where the dedicated-front-surround unlock happens: we call
/// `AddHTSatellite` with a `HTSatChanMapSet` that maps extra speakers to the
/// front (`LF`/`RF`) channels — something the official app refuses to build.
class DevicePropertiesClient {
  final SonosSoapClient _soap;
  DevicePropertiesClient(this._soap);

  static const _service = 'urn:schemas-upnp-org:service:DeviceProperties:1';
  static const _control = '/DeviceProperties/Control';

  /// Bonds satellites/sub described by [map] to the soundbar at [soundbarIp].
  /// The first entry of [map] must be the soundbar itself.
  Future<void> addHtSatellite({
    required String soundbarIp,
    required ChannelMap map,
  }) async {
    await _soap.call(
      ip: soundbarIp,
      controlPath: _control,
      serviceType: _service,
      action: 'AddHTSatellite',
      args: {'HTSatChanMapSet': map.encode()},
    );
  }

  /// Un-bonds a single satellite, making it a visible standalone room again.
  /// This is the safe "remove fronts" / restore primitive.
  Future<void> removeHtSatellite({
    required String soundbarIp,
    required String satelliteUuid,
  }) async {
    await _soap.call(
      ip: soundbarIp,
      controlPath: _control,
      serviceType: _service,
      action: 'RemoveHTSatellite',
      args: {'SatRoomUUID': satelliteUuid},
    );
  }

  /// Creates a stereo pair: [leftUuid] becomes the visible primary, [rightUuid]
  /// becomes hidden. Sent to the left speaker's [ip]. The local API does not
  /// enforce model matching, so mismatched pairs are possible here.
  Future<void> createStereoPair({
    required String ip,
    required String leftUuid,
    required String rightUuid,
  }) async {
    await _soap.call(
      ip: ip,
      controlPath: _control,
      serviceType: _service,
      action: 'CreateStereoPair',
      args: {'ChannelMapSet': '$leftUuid:LF,LF;$rightUuid:RF,RF'},
    );
  }

  /// Dissolves the stereo pair described by the same channel map.
  Future<void> separateStereoPair({
    required String ip,
    required String leftUuid,
    required String rightUuid,
  }) async {
    await _soap.call(
      ip: ip,
      controlPath: _control,
      serviceType: _service,
      action: 'SeparateStereoPair',
      args: {'ChannelMapSet': '$leftUuid:LF,LF;$rightUuid:RF,RF'},
    );
  }

  /// Reads a speaker's current zone attributes (name/icon/configuration).
  Future<ZoneAttributes> getZoneAttributes(String ip) async {
    final body = await _soap.call(
      ip: ip,
      controlPath: _control,
      serviceType: _service,
      action: 'GetZoneAttributes',
    );
    String val(String tag) {
      final els = body.findAllElements(tag);
      return els.isEmpty ? '' : els.first.innerText;
    }

    return ZoneAttributes(
      zoneName: val('CurrentZoneName'),
      icon: val('CurrentIcon'),
      configuration: val('CurrentConfiguration'),
    );
  }

  /// Sets a speaker's zone attributes — used to restore the original room name
  /// after separating a pair.
  Future<void> setZoneAttributes(String ip, ZoneAttributes attrs) async {
    await _soap.call(
      ip: ip,
      controlPath: _control,
      serviceType: _service,
      action: 'SetZoneAttributes',
      args: {
        'DesiredZoneName': attrs.zoneName,
        'DesiredIcon': attrs.icon,
        'DesiredConfiguration': attrs.configuration,
      },
    );
  }
}
