import 'package:xml/xml.dart';

import 'soap_client.dart';

/// Trueplay / room-calibration state for one speaker, read from the
/// `RenderingControl` service. Confirmed against real hardware via the device's
/// SCPD (see `tool/trueplay_probe.dart`):
///   GetRoomCalibrationStatus(InstanceID) → RoomCalibrationEnabled + RoomCalibrationAvailable
///   SetRoomCalibrationStatus(InstanceID, RoomCalibrationEnabled)
///
/// [available] == a tuning is stored on the speaker (done once in the iOS Sonos
/// app — the measurement can't be performed from Android). [enabled] == that
/// tuning is being applied. Both true ⇒ Trueplay is actually active.
class RoomCalibration {
  final bool available;
  final bool enabled;
  const RoomCalibration({required this.available, required this.enabled});

  /// Trueplay is only audibly in effect when a tuning exists AND is switched on.
  bool get active => available && enabled;

  static const unknown = RoomCalibration(available: false, enabled: false);
}

/// Reads and toggles room calibration on a single speaker. Toggling is
/// non-destructive and instantly reversible (it never re-measures or re-bonds).
class RoomCalibrationClient {
  final SonosSoapClient _soap;
  RoomCalibrationClient([SonosSoapClient? client])
      : _soap = client ?? SonosSoapClient();

  static const _service = 'urn:schemas-upnp-org:service:RenderingControl:1';
  static const _control = '/MediaRenderer/RenderingControl/Control';

  Future<RoomCalibration> getStatus(String ip) async {
    final body = await _soap.call(
      ip: ip,
      controlPath: _control,
      serviceType: _service,
      action: 'GetRoomCalibrationStatus',
      args: const {'InstanceID': '0'},
    );
    bool flag(String name) {
      final els = body.findAllElements(name);
      return els.isNotEmpty && els.first.innerText.trim() == '1';
    }

    return RoomCalibration(
      available: flag('RoomCalibrationAvailable'),
      enabled: flag('RoomCalibrationEnabled'),
    );
  }

  /// Switches the stored calibration on/off. Has no audible effect if the
  /// speaker has no tuning (`available == false`) — Sonos accepts the call but
  /// it's a no-op, so callers should gate on availability.
  Future<void> setEnabled(String ip, bool on) => _soap.call(
        ip: ip,
        controlPath: _control,
        serviceType: _service,
        action: 'SetRoomCalibrationStatus',
        args: {'InstanceID': '0', 'RoomCalibrationEnabled': on ? '1' : '0'},
      );
}
