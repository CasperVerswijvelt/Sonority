import 'package:xml/xml.dart';

import 'soap_client.dart';

/// The `GetEQ`/`SetEQ` types captured in the EQ bundle — every stable sound
/// setting the local API exposes (all hardware-confirmed on a Beam Gen 2 via
/// `tool/eq_probe.dart`). Values are ints; booleans are 0/1. Note the enable
/// tokens are `SubEnable`/`SurroundEnable` — WITHOUT the trailing "d" the SCPD
/// state variables carry (`SubEnabled` faults with 402).
///
/// Covers, in Sonos-app terms: night sound (NightMode), speech enhancement
/// (DialogLevel), sub level/on-off/phase/crossover (SubGain/SubEnable/
/// SubPolarity/SubCrossover), surround on-off + TV & music levels + full-vs-
/// ambient music mode (SurroundEnable/SurroundLevel/MusicSurroundLevel/
/// SurroundMode), lip sync (AudioDelay), surround distance (AudioDelayLeftRear/
/// RightRear), height channel level. NOT exposed by the local API (so not
/// captured): volume limit, spatial music, TV autoplay/disband, group audio
/// delay, IR.
const eqTypes = [
  'NightMode',
  'DialogLevel',
  'SubGain',
  'SubEnable',
  'SubPolarity',
  'SubCrossover',
  'SurroundLevel',
  'SurroundEnable',
  'SurroundMode',
  'MusicSurroundLevel',
  'AudioDelay',
  'AudioDelayLeftRear',
  'AudioDelayRightRear',
  'HeightChannelLevel',
];

/// A snapshot of one speaker's audio settings, read from the `RenderingControl`
/// service. Every field is nullable / possibly absent: it means "not captured"
/// (the profile toggle was off) OR "this speaker doesn't support it" (e.g. a
/// plain Play:1 answers no surround/sub tokens; HT satellites reject EQ reads
/// entirely with UPnPError 803). Reading and applying are both best-effort per
/// field — one setting faulting never sinks the rest.
///
/// [bass]/[treble]/[loudness] have dedicated SOAP actions; every other sound
/// setting rides the generic `GetEQ`/`SetEQ` pair and lives in [eq] keyed by
/// EQType (see [eqTypes]). [volume]/[mute] are transient playback state,
/// captured only when the user opts in via the separate volume toggle.
class SpeakerSettings {
  final int? bass;
  final int? treble;
  final bool? loudness;

  /// EQType → value for every token the speaker answered (see [eqTypes]).
  final Map<String, int> eq;

  final int? volume;
  final bool? mute;

  const SpeakerSettings({
    this.bass,
    this.treble,
    this.loudness,
    this.eq = const {},
    this.volume,
    this.mute,
  });

  static const empty = SpeakerSettings();

  bool get hasAudioSettings =>
      bass != null || treble != null || loudness != null || eq.isNotEmpty;

  bool get hasVolume => volume != null || mute != null;

  bool get isEmpty => !hasAudioSettings && !hasVolume;

  /// Serializes only the non-null/non-empty fields, so an EQ-only capture
  /// doesn't store bogus volume keys and old profiles round-trip cleanly.
  Map<String, dynamic> toJson() => {
        if (bass != null) 'bass': bass,
        if (treble != null) 'treble': treble,
        if (loudness != null) 'loudness': loudness,
        if (eq.isNotEmpty) 'eq': eq,
        if (volume != null) 'volume': volume,
        if (mute != null) 'mute': mute,
      };

  factory SpeakerSettings.fromJson(Map<String, dynamic> j) => SpeakerSettings(
        bass: j['bass'] as int?,
        treble: j['treble'] as int?,
        loudness: j['loudness'] as bool?,
        eq: Map<String, int>.from((j['eq'] as Map?) ?? const {}),
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

  /// Reads a settings snapshot for the speaker at [ip]. [audio] captures the
  /// audio-settings bundle (bass/treble/loudness + every [eqTypes] token the
  /// speaker answers); [volume] captures volume/mute. The two are independent
  /// toggles.
  Future<SpeakerSettings> read(String ip,
      {bool audio = true, bool volume = false}) async {
    final eqValues = <String, int>{};
    if (audio) {
      for (final t in eqTypes) {
        final v = await _readInt(ip, 'GetEQ', 'CurrentValue',
            extra: {'EQType': t});
        if (v != null) eqValues[t] = v;
      }
    }
    return SpeakerSettings(
      bass: audio ? await _readInt(ip, 'GetBass', 'CurrentBass') : null,
      treble: audio ? await _readInt(ip, 'GetTreble', 'CurrentTreble') : null,
      loudness: audio
          ? await _readBool(ip, 'GetLoudness', 'CurrentLoudness',
              extra: const {'Channel': 'Master'})
          : null,
      eq: eqValues,
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
    for (final e in s.eq.entries) {
      await _set(ip, 'SetEQ', {'EQType': e.key, 'DesiredValue': '${e.value}'});
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

  // ---- write helper (swallows faults; one setting must not block the rest) ----

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
}
