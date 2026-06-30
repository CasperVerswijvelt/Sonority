import 'soap_client.dart';

/// Minimal `AVTransport` client. Today only used to detach a player from its
/// playback group — a prerequisite for dissolving a zone bond (Sonos won't
/// remove the bond while the zone coordinator is a non-coordinator member of a
/// larger playback group).
class AvTransportClient {
  final SonosSoapClient _soap;
  AvTransportClient(this._soap);

  static const _service = 'urn:schemas-upnp-org:service:AVTransport:1';
  static const _control = '/MediaRenderer/AVTransport/Control';

  /// Detaches [ip] from its current playback group into its own standalone
  /// group (it becomes its own coordinator). No-op if it's already standalone.
  Future<void> becomeCoordinatorOfStandaloneGroup(String ip) => _soap.call(
        ip: ip,
        controlPath: _control,
        serviceType: _service,
        action: 'BecomeCoordinatorOfStandaloneGroup',
        args: {'InstanceID': '0'},
      );
}
