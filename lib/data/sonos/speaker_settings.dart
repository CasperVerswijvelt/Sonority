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

/// EQType → human label (Sonos-app terms) for read-only display of a captured
/// [SpeakerSettings]. Tokens absent here fall back to the raw token.
const _eqLabels = {
  'NightMode': 'Night sound',
  'DialogLevel': 'Speech enhancement',
  'SubGain': 'Sub level',
  'SubEnable': 'Sub',
  'SubPolarity': 'Sub phase',
  'SubCrossover': 'Sub crossover',
  'SurroundLevel': 'Surround level (TV)',
  'SurroundEnable': 'Surround',
  'SurroundMode': 'Surround mode',
  'MusicSurroundLevel': 'Surround level (music)',
  'AudioDelay': 'Audio delay (lip sync)',
  'AudioDelayLeftRear': 'Surround distance L',
  'AudioDelayRightRear': 'Surround distance R',
  'HeightChannelLevel': 'Height level',
};

/// EQType tokens whose value is a boolean toggle (0/1) — shown as On/Off. Every
/// other token is a numeric level shown as-is (except `SubPolarity`, a 0/1 sub
/// *phase* rendered as 0°/180° — see [SpeakerSettings.describe]).
const _eqBoolTokens = {'NightMode', 'SubEnable', 'SurroundEnable'};

/// A snapshot of one speaker's audio settings, read from the `RenderingControl`
/// service. Every field is nullable / possibly absent: it means "not captured"
/// (the profile toggle was off, or the [eqTypes] bundle was skipped for a plain
/// speaker — see [SpeakerSettingsClient.read]'s `extendedEq`) OR "this speaker
/// doesn't support it" (HT satellites reject EQ reads entirely with UPnPError
/// 803). Note a plain Play:1 / One *does* answer the sub/surround/height GetEQ
/// calls, just with meaningless defaults — which is why we gate them by role
/// rather than by whether the call faults. Reading and applying are both
/// best-effort per field — one setting faulting never sinks the rest.
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

  /// Human-readable (label, value) rows for read-only display of what this
  /// snapshot captured, in a stable order. Bass/treble/loudness first, then the
  /// EQ tokens in [eqTypes] order, then volume/mute.
  ///
  /// ponytail: per-token value semantics are approximate — bass/treble/gains are
  /// signed levels, a few tokens are 0/1 toggles ([_eqBoolTokens]), SubPolarity is
  /// a phase, SurroundMode/DialogLevel map their known values (with a raw
  /// fallback for anything unexpected), and every other token shows a raw int.
  /// This is display-only; captured values are written back verbatim, never
  /// derived from these labels.
  List<({String label, String value})> describe() {
    String signed(int v) => v > 0 ? '+$v' : '$v';
    String onOff(bool b) => b ? 'On' : 'Off';
    final rows = <({String label, String value})>[
      if (bass != null) (label: 'Bass', value: signed(bass!)),
      if (treble != null) (label: 'Treble', value: signed(treble!)),
      if (loudness != null) (label: 'Loudness', value: onOff(loudness!)),
    ];
    for (final token in eqTypes) {
      final v = eq[token];
      if (v == null) continue;
      final String value;
      if (token == 'SubPolarity') {
        value = v == 0 ? '0°' : '180°'; // sub phase, not an on/off toggle
      } else if (token == 'SurroundMode') {
        // Sonos surround-music mode: 0 = ambient, 1 = full. Raw for anything else.
        value = switch (v) {
          0 => 'Ambient',
          1 => 'Full',
          _ => '$v',
        };
      } else if (token == 'DialogLevel') {
        // Speech enhancement — a 0/1 toggle on the models that expose it. Raw for
        // anything else (some models may report a level rather than a toggle).
        value = switch (v) {
          0 => 'Off',
          1 => 'On',
          _ => '$v',
        };
      } else if (_eqBoolTokens.contains(token)) {
        value = onOff(v != 0);
      } else {
        value = '$v';
      }
      rows.add((label: _eqLabels[token] ?? token, value: value));
    }
    if (volume != null) rows.add((label: 'Volume', value: '$volume%'));
    if (mute != null) rows.add((label: 'Muted', value: onOff(mute!)));
    return rows;
  }

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
  /// audio-settings bundle; [volume] captures volume/mute (independent toggles).
  ///
  /// [extendedEq] gates the [eqTypes] bundle (night sound, speech, sub, surround,
  /// height, lip-sync). Those are only physically meaningful on a soundbar / in a
  /// home theater / when a sub is bonded — every other speaker (a plain Play:1 /
  /// One in a zone or pair) still *answers* GetEQ for them with harmless defaults
  /// (SubGain 0, SubEnable On, …), which is just noise to capture and show. So
  /// callers pass `extendedEq: false` for plain speakers and only bass / treble /
  /// loudness (the universally-meaningful controls) are read.
  Future<SpeakerSettings> read(
    String ip, {
    bool audio = true,
    bool volume = false,
    bool extendedEq = true,
  }) async {
    final eqValues = <String, int>{};
    if (audio && extendedEq) {
      for (final t in eqTypes) {
        final v = await _readInt(
          ip,
          'GetEQ',
          'CurrentValue',
          extra: {'EQType': t},
        );
        if (v != null) eqValues[t] = v;
      }
    }
    return SpeakerSettings(
      bass: audio ? await _readInt(ip, 'GetBass', 'CurrentBass') : null,
      treble: audio ? await _readInt(ip, 'GetTreble', 'CurrentTreble') : null,
      loudness: audio
          ? await _readBool(
              ip,
              'GetLoudness',
              'CurrentLoudness',
              extra: const {'Channel': 'Master'},
            )
          : null,
      eq: eqValues,
      volume: volume
          ? await _readInt(
              ip,
              'GetVolume',
              'CurrentVolume',
              extra: const {'Channel': 'Master'},
            )
          : null,
      mute: volume
          ? await _readBool(
              ip,
              'GetMute',
              'CurrentMute',
              extra: const {'Channel': 'Master'},
            )
          : null,
    );
  }

  /// Writes every non-null field of [s]. Each write is independent; a failure is
  /// swallowed so the remaining settings still apply. Returns the number of
  /// writes that failed — a non-zero count (e.g. a firmware change renaming an
  /// EQ token so every SetEQ faults) is otherwise invisible to the caller.
  Future<int> apply(String ip, SpeakerSettings s) async {
    var failed = 0;
    Future<void> set(String action, Map<String, String> extra) async {
      if (!await _set(ip, action, extra)) failed++;
    }

    if (s.bass != null) {
      await set('SetBass', {'DesiredBass': '${s.bass}'});
    }
    if (s.treble != null) {
      await set('SetTreble', {'DesiredTreble': '${s.treble}'});
    }
    if (s.loudness != null) {
      await set('SetLoudness', {
        'Channel': 'Master',
        'DesiredLoudness': s.loudness! ? '1' : '0',
      });
    }
    for (final e in s.eq.entries) {
      await set('SetEQ', {'EQType': e.key, 'DesiredValue': '${e.value}'});
    }
    if (s.volume != null) {
      await set('SetVolume', {
        'Channel': 'Master',
        'DesiredVolume': '${s.volume}',
      });
    }
    if (s.mute != null) {
      await set('SetMute', {
        'Channel': 'Master',
        'DesiredMute': s.mute! ? '1' : '0',
      });
    }
    return failed;
  }

  // ---- read helpers (null on any fault so unsupported settings are skipped) ----

  Future<String?> _rawRead(
    String ip,
    String action,
    String outEl,
    Map<String, String> extra,
  ) async {
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

  Future<int?> _readInt(
    String ip,
    String action,
    String outEl, {
    Map<String, String> extra = const {},
  }) async => int.tryParse(await _rawRead(ip, action, outEl, extra) ?? '');

  Future<bool?> _readBool(
    String ip,
    String action,
    String outEl, {
    Map<String, String> extra = const {},
  }) async {
    final v = await _rawRead(ip, action, outEl, extra);
    return v == null ? null : v == '1';
  }

  // ---- write helper (swallows faults; one setting must not block the rest) ----

  /// Returns true if the write succeeded, false if it faulted (best-effort — a
  /// single failed setting must not block the rest).
  Future<bool> _set(String ip, String action, Map<String, String> extra) async {
    try {
      await _soap.call(
        ip: ip,
        controlPath: _control,
        serviceType: _service,
        action: action,
        args: {'InstanceID': '0', ...extra},
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
