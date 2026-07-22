import '../models/sonos_models.dart';

/// One device assignment inside a `HTSatChanMapSet`:
/// `RINCON_xxx01400:LF,RF`.
///
/// Tokens are stored raw (as strings) so we never lose channel codes we don't
/// model yet (e.g. height/Atmos tokens) when round-tripping an existing map.
class ChannelMapEntry {
  final String uuid;
  final List<String> tokens;

  const ChannelMapEntry(this.uuid, this.tokens);

  /// Build from typed channels (used when constructing a new layout).
  factory ChannelMapEntry.fromChannels(String uuid, List<SonosChannel> channels) =>
      ChannelMapEntry(uuid, channels.map((c) => c.token).toList());

  /// The subset of tokens we recognise, as typed channels.
  List<SonosChannel> get channels =>
      tokens.map(SonosChannel.fromToken).whereType<SonosChannel>().toList();

  String encode() => '$uuid:${tokens.join(',')}';

  @override
  String toString() => encode();
}

/// Build and parse Sonos `HTSatChanMapSet` strings.
///
/// Format: entries separated by `;`, each `UUID:CH[,CH...]`. Verified against a
/// live Sonos Beam home theater, whose layout is:
/// `RINCON_BEAM:CC;RINCON_S1:LR;RINCON_S2:RR;RINCON_SUB:SW`
///
/// The first entry is the home-theater primary (soundbar). Note the soundbar
/// carries `CC` (center) — the dedicated-front unlock keeps it as center and
/// adds two extra speakers as `LF`/`RF`, which the official app won't do.
class ChannelMap {
  final List<ChannelMapEntry> entries;

  const ChannelMap(this.entries);

  static ChannelMap parse(String raw) {
    final entries = <ChannelMapEntry>[];
    for (final part in raw.split(';')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final colon = trimmed.indexOf(':');
      if (colon < 0) continue;
      final uuid = trimmed.substring(0, colon).trim();
      final tokens = trimmed
          .substring(colon + 1)
          .split(',')
          .map((t) => t.trim().toUpperCase())
          .where((t) => t.isNotEmpty)
          .toList();
      if (uuid.isEmpty || tokens.isEmpty) continue;
      entries.add(ChannelMapEntry(uuid, tokens));
    }
    return ChannelMap(entries);
  }

  String encode() => entries.map((e) => e.encode()).join(';');

  ChannelMapEntry? get primary => entries.isEmpty ? null : entries.first;

  ChannelMap withoutUuid(String uuid) =>
      ChannelMap(entries.where((e) => e.uuid != uuid).toList());

  @override
  String toString() => encode();
}
