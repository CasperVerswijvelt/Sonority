import 'package:xml/xml.dart';

import 'soap_client.dart';

/// Identifies a speaker by **blinking its white status LED** — an alternative to
/// the audio chime ([IdentifyService]) that needs no in-app HTTP server and so
/// works everywhere, including the sandboxed macOS app (it's a plain outbound
/// SOAP call to the speaker, not an inbound LAN connection).
///
/// Uses the `DeviceProperties` service (confirmed across Sonos UPnP libraries):
///   GetLEDState() → CurrentLEDState ("On"|"Off")
///   SetLEDState(DesiredLEDState)
///
/// [blink] is **self-reverting**: it captures the current LED state first and
/// always restores it, even if a toggle fails or the caller is torn down — a
/// speaker is never left in a changed state. This mirrors the chime's
/// save→bump→restore volume/mute and the bonding "snapshot then self-revert"
/// pattern used elsewhere in the engine.
class LedIdentifyClient {
  final SonosSoapClient _soap;
  final void Function(String message)? onLog;
  LedIdentifyClient([SonosSoapClient? client, this.onLog])
      : _soap = client ?? SonosSoapClient();

  static const _service = 'urn:schemas-upnp-org:service:DeviceProperties:1';
  static const _control = '/DeviceProperties/Control';

  /// Short per-call timeout: LED ops are fast and fired in quick succession, so
  /// a stalled one should fail fast rather than freeze the blink.
  static const _timeout = Duration(seconds: 4);

  /// Reads the current status-light state. `true` == on. Returns `null` if the
  /// speaker doesn't report it.
  Future<bool?> getLedState(String ip) async {
    final body = await _soap.call(
      ip: ip,
      controlPath: _control,
      serviceType: _service,
      action: 'GetLEDState',
      timeout: _timeout,
    );
    final els = body.findAllElements('CurrentLEDState');
    if (els.isEmpty) return null;
    return els.first.innerText.trim().toLowerCase() == 'on';
  }

  /// Turns the status light on/off.
  Future<void> setLedState(String ip, bool on) => _soap.call(
        ip: ip,
        controlPath: _control,
        serviceType: _service,
        action: 'SetLEDState',
        args: {'DesiredLEDState': on ? 'On' : 'Off'},
        timeout: _timeout,
      );

  /// Blinks the LED [cycles] times, then restores the original state.
  ///
  /// The original state is captured up front and restored in a `finally`, so the
  /// speaker returns to exactly how it was found whether the user had the light
  /// on or off — and even if a toggle throws mid-blink. If the initial read
  /// fails we restore to **on** (the Sonos factory default) rather than risk
  /// leaving the light off.
  Future<void> blink(
    String ip, {
    int cycles = 3,
    Duration interval = const Duration(milliseconds: 300),
  }) async {
    bool original;
    try {
      original = await getLedState(ip) ?? true;
    } catch (e) {
      onLog?.call('LED read failed, will restore to on: $e');
      original = true;
    }
    onLog?.call('blinking $ip (was ${original ? 'on' : 'off'})');

    // Tolerate the odd slow/failed toggle: keep blinking rather than aborting,
    // so one hiccup doesn't leave a half-finished blink.
    var attempts = 0;
    var failures = 0;
    Future<void> toggle(bool on) async {
      attempts++;
      try {
        await setLedState(ip, on);
      } catch (e) {
        failures++;
        onLog?.call('LED toggle failed (continuing): $e');
      }
    }

    try {
      for (var i = 0; i < cycles; i++) {
        await toggle(false);
        await Future<void>.delayed(interval);
        await toggle(true);
        await Future<void>.delayed(interval);
      }
    } finally {
      // Always put the light back the way we found it (best-effort).
      try {
        await setLedState(ip, original);
        onLog?.call('restored LED to ${original ? 'on' : 'off'}');
      } catch (e) {
        onLog?.call('LED restore skipped: $e');
      }
    }

    // If not a single toggle landed, the speaker is unreachable — surface it so
    // the UI can tell the user, instead of silently doing nothing.
    if (attempts > 0 && failures == attempts) {
      throw Exception('Could not reach the speaker to blink its light.');
    }
  }
}
