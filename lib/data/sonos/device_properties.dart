import 'channel_map.dart';
import 'soap_client.dart';

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
}
