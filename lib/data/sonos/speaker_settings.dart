import 'package:xml/xml.dart';

import 'soap_client.dart';

/// A snapshot of one speaker's audio settings, read from the `RenderingControl`
/// service. Every field is nullable: `null` means "not captured" (the profile
/// toggle was off) OR "this speaker doesn't support it" (e.g. a plain Play:1 has
/// no `SubGain`). Reading and applying are both best-effort per field — one
/// setting faulting never sinks the rest.
///
/// EQ fields (`bass`…`surroundLevel`) are stable configuration and pair well
/// with a saved layout. `volume`/`mute` are transient playback state, captured
/// only when the user opts in via the separate volume toggle.
///
/// Action/arg shapes follow the RenderingControl SCPD (confirm with
/// `tool/eq_probe.dart`): Get/SetBass, Get/SetTreble, Get/SetLoudness(Channel),
/// Get/SetEQ(EQType), Get/SetVolume(Channel), Get/SetMute(Channel).
class SpeakerSettings {
  final int? bass;
  final int? treble;
  final bool? loudness;
  final bool? nightMode; // EQType NightMode
  final int? dialogLevel; // EQType DialogLevel (speech enhancement)
  final int? subGain; // EQType SubGain
  final int? surroundLevel; // EQType SurroundLevel
  final int? volume;
  final bool? mute;

  const SpeakerSettings({
    this.bass,
    this.treble,
    this.loudness,
    this.nightMode,
    this.dialogLevel,
    this.subGain,
    this.surroundLevel,
    this.volume,
    this.mute,
  });

  static const empty = SpeakerSettings();

  bool get hasEq =>
      bass != null ||
      treble != null ||
      loudness != null ||
      nightMode != null ||
      dialogLevel != null ||
      subGain != null ||
      surroundLevel != null;

  bool get hasVolume => volume != null || mute != null;

  bool get isEmpty => !hasEq && !hasVolume;

  /// Serializes only the non-null fields, so an EQ-only capture doesn't store
  /// bogus volume keys and old profiles round-trip cleanly.
  Map<String, dynamic> toJson() => {
        if (bass != null) 'bass': bass,
        if (treble != null) 'treble': treble,
        if (loudness != null) 'loudness': loudness,
        if (nightMode != null) 'nightMode': nightMode,
        if (dialogLevel != null) 'dialogLevel': dialogLevel,
        if (subGain != null) 'subGain': subGain,
        if (surroundLevel != null) 'surroundLevel': surroundLevel,
        if (volume != null) 'volume': volume,
        if (mute != null) 'mute': mute,
      };

  factory SpeakerSettings.fromJson(Map<String, dynamic> j) => SpeakerSettings(
        bass: j['bass'] as int?,
        treble: j['treble'] as int?,
        loudness: j['loudness'] as bool?,
        nightMode: j['nightMode'] as bool?,
        dialogLevel: j['dialogLevel'] as int?,
        subGain: j['subGain'] as int?,
        surroundLevel: j['surroundLevel'] as int?,
        volume: j['volume'] as int?,
        mute: j['mute'] as bool?,
      );
}

/// Reads and applies per-speaker audio settings. Both directions are
/// best-effort: a field that faults (unsupported action, transient error) is
/// skipped, never fatal — settings restore is a nicety layered on top of the
/// authoritative layout, not a hard requirement.
class SpeakerSettingsClient {
  final SonosSoapClient _soap;
  SpeakerSettingsClient([SonosSoapClient? client])
      : _soap = client ?? SonosSoapClient();

  static const _service = 'urn:schemas-upnp-org:service:RenderingControl:1';
  static const _control = '/MediaRenderer/RenderingControl/Control';

  /// Reads a settings snapshot for the speaker at [ip]. [eq] captures the EQ
  /// bundle (bass/treble/loudness/night/speech/sub/surround); [volume] captures
  /// volume/mute. The two are independent toggles.
  Future<SpeakerSettings> read(String ip,
      {bool eq = true, bool volume = false}) async {
    return SpeakerSettings(
      bass: eq ? await _readInt(ip, 'GetBass', 'CurrentBass') : null,
      treble: eq ? await _readInt(ip, 'GetTreble', 'CurrentTreble') : null,
      loudness: eq
          ? await _readBool(ip, 'GetLoudness', 'CurrentLoudness',
              extra: const {'Channel': 'Master'})
          : null,
      nightMode: eq ? await _readEqBool(ip, 'NightMode') : null,
      dialogLevel: eq ? await _readEqInt(ip, 'DialogLevel') : null,
      subGain: eq ? await _readEqInt(ip, 'SubGain') : null,
      surroundLevel: eq ? await _readEqInt(ip, 'SurroundLevel') : null,
      volume: volume
          ? await _readInt(ip, 'GetVolume', 'CurrentVolume',
              extra: const {'Channel': 'Master'})
          : null,
      mute: volume
          ? await _readBool(ip, 'GetMute', 'CurrentMute',
              extra: const {'Channel': 'Master'})
          : null,
    );
  }

  /// Writes every non-null field of [s]. Each write is independent; a failure is
  /// swallowed so the remaining settings still apply.
  Future<void> apply(String ip, SpeakerSettings s) async {
    if (s.bass != null) {
      await _set(ip, 'SetBass', {'DesiredBass': '${s.bass}'});
    }
    if (s.treble != null) {
      await _set(ip, 'SetTreble', {'DesiredTreble': '${s.treble}'});
    }
    if (s.loudness != null) {
      await _set(ip, 'SetLoudness',
          {'Channel': 'Master', 'DesiredLoudness': s.loudness! ? '1' : '0'});
    }
    if (s.nightMode != null) {
      await _setEq(ip, 'NightMode', s.nightMode! ? '1' : '0');
    }
    if (s.dialogLevel != null) await _setEq(ip, 'DialogLevel', '${s.dialogLevel}');
    if (s.subGain != null) await _setEq(ip, 'SubGain', '${s.subGain}');
    if (s.surroundLevel != null) {
      await _setEq(ip, 'SurroundLevel', '${s.surroundLevel}');
    }
    if (s.volume != null) {
      await _set(ip, 'SetVolume',
          {'Channel': 'Master', 'DesiredVolume': '${s.volume}'});
    }
    if (s.mute != null) {
      await _set(
          ip, 'SetMute', {'Channel': 'Master', 'DesiredMute': s.mute! ? '1' : '0'});
    }
  }

  // ---- read helpers (null on any fault so unsupported settings are skipped) ----

  Future<String?> _rawRead(String ip, String action, String outEl,
      Map<String, String> extra) async {
    try {
      final body = await _soap.call(
        ip: ip,
        controlPath: _control,
        serviceType: _service,
        action: action,
        args: {'InstanceID': '0', ...extra},
      );
      final els = body.findAllElements(outEl);
      return els.isEmpty ? null : els.first.innerText.trim();
    } catch (_) {
      return null;
    }
  }

  Future<int?> _readInt(String ip, String action, String outEl,
          {Map<String, String> extra = const {}}) async =>
      int.tryParse(await _rawRead(ip, action, outEl, extra) ?? '');

  Future<bool?> _readBool(String ip, String action, String outEl,
      {Map<String, String> extra = const {}}) async {
    final v = await _rawRead(ip, action, outEl, extra);
    return v == null ? null : v == '1';
  }

  Future<int?> _readEqInt(String ip, String type) =>
      _readInt(ip, 'GetEQ', 'CurrentValue', extra: {'EQType': type});

  Future<bool?> _readEqBool(String ip, String type) =>
      _readBool(ip, 'GetEQ', 'CurrentValue', extra: {'EQType': type});

  // ---- write helpers (swallow faults; one setting must not block the rest) ----

  Future<void> _set(String ip, String action, Map<String, String> extra) async {
    try {
      await _soap.call(
        ip: ip,
        controlPath: _control,
        serviceType: _service,
        action: action,
        args: {'InstanceID': '0', ...extra},
      );
    } catch (_) {/* best-effort */}
  }

  Future<void> _setEq(String ip, String type, String value) =>
      _set(ip, 'SetEQ', {'EQType': type, 'DesiredValue': value});
}
