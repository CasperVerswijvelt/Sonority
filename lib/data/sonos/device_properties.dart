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

  /// Bonds the speakers in [channelMapSet] into a single Sonos **speaker group**
  /// — the universal create for stereo pairs, zones, and custom L/R layouts (and
  /// an optional `:SW` Sub). Each member plays its assigned channel(s). Sent to
  /// the coordinator's [ip]; the other members go Invisible. Distinct from a
  /// temporary playback group. Token format confirmed via `tool/zone_probe.dart`.
  Future<void> addBondedZones({
    required String ip,
    required String channelMapSet,
  }) async {
    await _soap.call(
      ip: ip,
      controlPath: _control,
      serviceType: _service,
      action: 'AddBondedZones',
      args: {'ChannelMapSet': channelMapSet},
    );
  }

  /// Dissolves the zone described by [channelMapSet], returning its members to
  /// standalone rooms. Uses `SeparateStereoPair` — confirmed on hardware that
  /// `RemoveBondedZones` returns 200 OK but silently no-ops on the 2025 zones
  /// feature, while `SeparateStereoPair` (a zone shares the pair's `ChannelMapSet`
  /// bond mechanism) actually works. The zone must be its own group coordinator
  /// first (see `AvTransportClient.becomeCoordinatorOfStandaloneGroup`).
  Future<void> separateBondedZones({
    required String ip,
    required String channelMapSet,
  }) async {
    await _soap.call(
      ip: ip,
      controlPath: _control,
      serviceType: _service,
      action: 'SeparateStereoPair',
      args: {'ChannelMapSet': channelMapSet},
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
    return ZoneAttributes(
      zoneName: body.childText('CurrentZoneName') ?? '',
      icon: body.childText('CurrentIcon') ?? '',
      configuration: body.childText('CurrentConfiguration') ?? '',
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
