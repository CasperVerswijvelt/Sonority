/// Domain models for the local Sonos system.
///
/// These intentionally mirror the data we can read from the undocumented local
/// UPnP API: device descriptions (`/xml/device_description.xml`) and the
/// `ZoneGroupTopology` service (`GetZoneGroupState`).
library;

/// Speaker channel tokens used in a `HTSatChanMapSet`.
enum SonosChannel {
  leftFront('LF'),
  rightFront('RF'),
  center('CC'), // soundbar's role once dedicated fronts take over L/R
  leftRear('LR'),
  rightRear('RR'),
  sub('SW');

  const SonosChannel(this.token);
  final String token;

  static SonosChannel? fromToken(String token) {
    for (final c in SonosChannel.values) {
      if (c.token == token.trim().toUpperCase()) return c;
    }
    return null;
  }
}

/// A single physical Sonos player on the network.
class SonosDevice {
  final String uuid; // RINCON_xxxxxxxxxxxx01400
  final String roomName;
  final String modelName; // e.g. "Sonos Arc"
  final String? modelNumber; // e.g. "S27"
  final String? ip;

  /// False when we couldn't read this player's device_description.xml: it's
  /// present in the authoritative topology but its model/capabilities are
  /// unknown, so the UI surfaces it disabled with a warning rather than
  /// offering it as a real bonding candidate.
  final bool reachable;

  const SonosDevice({
    required this.uuid,
    required this.roomName,
    required this.modelName,
    this.modelNumber,
    this.ip,
    this.reachable = true,
  });

  /// Soundbars are the only valid `AddHTSatellite` targets.
  bool get isSoundbar {
    final m = modelName.toLowerCase();
    return m.contains('arc') ||
        m.contains('beam') ||
        m.contains('ray') ||
        m.contains('playbar') ||
        m.contains('playbase');
  }

  bool get isSub => modelName.toLowerCase().contains('sub');

  /// Friendly speaker type for display, e.g. "Play:1", "One SL", "Beam (Gen 2)".
  /// - A Sub's generation isn't reliably reported (Gen 1 & 2 are identical and
  ///   both report model number "Sub"), so we just say "Sub".
  /// - The Beam generation IS identifiable by model number (S14 = Gen 1,
  ///   S31 = Gen 2) so it's shown.
  String get typeLabel {
    final base = modelName.replaceFirst(RegExp(r'^Sonos\s+'), '').trim();
    if (isSub) return 'Sub';
    if (base.toLowerCase() == 'beam') {
      if (modelNumber == 'S14') return 'Beam (Gen 1)';
      if (modelNumber == 'S31') return 'Beam (Gen 2)';
    }
    return base.isEmpty ? 'Speaker' : base;
  }

  /// A Sonos Amp / Connect:Amp drives passive L/R speakers, so it can serve as
  /// BOTH front channels at once (`LF,RF`) — unlike a normal speaker, which is
  /// a single side. Used to offer it as a one-box dedicated-fronts option.
  bool get isAmp => modelName.toLowerCase().contains('amp');

  SonosDevice copyWith({String? ip, String? roomName}) => SonosDevice(
        uuid: uuid,
        roomName: roomName ?? this.roomName,
        modelName: modelName,
        modelNumber: modelNumber,
        ip: ip ?? this.ip,
        reachable: reachable,
      );

  @override
  bool operator ==(Object other) => other is SonosDevice && other.uuid == uuid;

  @override
  int get hashCode => uuid.hashCode;
}

/// A hidden satellite bonded to a home-theater primary (surround or sub).
class SonosSatellite {
  final String uuid;
  final String zoneName;
  final List<SonosChannel> channels;
  final String? ip;

  const SonosSatellite({
    required this.uuid,
    required this.zoneName,
    required this.channels,
    this.ip,
  });

  bool get isSub => channels.contains(SonosChannel.sub);
  bool get isFront =>
      channels.contains(SonosChannel.leftFront) || channels.contains(SonosChannel.rightFront);
  bool get isRear =>
      channels.contains(SonosChannel.leftRear) || channels.contains(SonosChannel.rightRear);
}

/// A visible zone (room). When it is a home-theater primary it carries
/// satellites and the raw `HTSatChanMapSet` describing the bonded layout.
class ZoneGroupMember {
  final String uuid;
  final String zoneName;
  final String? location; // device_description.xml URL
  final String? htSatChanMapSet; // raw bonded layout, null if none
  final List<SonosSatellite> satellites;
  final bool invisible; // hidden right-half of a stereo pair / bonded satellite
  final String? channelMapSet; // stereo-pair map (UUID:LF,LF;UUID:RF,RF), else null

  const ZoneGroupMember({
    required this.uuid,
    required this.zoneName,
    this.location,
    this.htSatChanMapSet,
    this.satellites = const [],
    this.invisible = false,
    this.channelMapSet,
  });

  String? get ip {
    final loc = location;
    if (loc == null) return null;
    return Uri.tryParse(loc)?.host;
  }

  bool get isHomeTheater => (htSatChanMapSet?.isNotEmpty ?? false) || satellites.isNotEmpty;

  /// True when this visible member is a stereo pair (carries a ChannelMapSet
  /// with doubled L/R channels). The hidden half is a separate Invisible member.
  bool get isStereoPair => (channelMapSet?.contains(',') ?? false);

  /// [leftUuid, rightUuid] of the stereo pair, parsed from the ChannelMapSet.
  List<String> get stereoPairUuids {
    final cms = channelMapSet;
    if (cms == null || cms.isEmpty) return const [];
    return cms
        .split(';')
        .map((e) => e.split(':').first.trim())
        .where((u) => u.isNotEmpty)
        .toList();
  }

  /// UUIDs of bonded front (LF/RF) satellites, read straight from the
  /// authoritative `HTSatChanMapSet`. This is robust to the transient window
  /// after a bonding change where the `<Satellite>` elements briefly vanish
  /// from the topology (observed to take ~15s to re-enumerate on real gear).
  List<String> get frontSatelliteUuids {
    final map = htSatChanMapSet;
    if (map == null) return const [];
    final parts = map.split(';');
    final out = <String>[];
    // Skip the first entry — that's the soundbar primary (e.g. CC center).
    for (var i = 1; i < parts.length; i++) {
      final p = parts[i].trim();
      final colon = p.indexOf(':');
      if (colon < 0) continue;
      final uuid = p.substring(0, colon).trim();
      final tokens = p.substring(colon + 1).toUpperCase();
      if (uuid.isNotEmpty && (tokens.contains('LF') || tokens.contains('RF'))) {
        out.add(uuid);
      }
    }
    return out;
  }

  bool get hasDedicatedFronts =>
      frontSatelliteUuids.isNotEmpty || satellites.any((s) => s.isFront);

  /// Channel → satellite UUID, parsed from the authoritative `HTSatChanMapSet`
  /// (skips the soundbar primary). Robust to the post-change topology lag.
  Map<SonosChannel, String> get channelAssignments {
    final raw = htSatChanMapSet;
    final result = <SonosChannel, String>{};
    if (raw == null) return result;
    final parts = raw.split(';');
    for (var i = 1; i < parts.length; i++) {
      final p = parts[i].trim();
      final colon = p.indexOf(':');
      if (colon < 0) continue;
      final uuid = p.substring(0, colon).trim();
      if (uuid.isEmpty) continue;
      for (final token in p.substring(colon + 1).split(',')) {
        final ch = SonosChannel.fromToken(token);
        if (ch != null) result[ch] = uuid;
      }
    }
    return result;
  }

  /// Every bonded satellite UUID from the `HTSatChanMapSet` (skips the soundbar
  /// primary), in map order. Unlike [channelAssignments] (a 1:1 channel→uuid
  /// map) this keeps ALL satellites — including a second Sub in a dual-sub HT.
  List<String> get satelliteUuids => _uuidsWhere((_) => true);

  /// All satellite UUIDs assigned to [channel] — more than one for dual subs.
  List<String> uuidsForChannel(SonosChannel channel) =>
      _uuidsWhere((tokens) => tokens.contains(channel.token));

  List<String> _uuidsWhere(bool Function(List<String> tokens) test) {
    final raw = htSatChanMapSet;
    if (raw == null) return const [];
    final out = <String>[];
    final parts = raw.split(';');
    for (var i = 1; i < parts.length; i++) {
      final p = parts[i].trim();
      final colon = p.indexOf(':');
      if (colon < 0) continue;
      final uuid = p.substring(0, colon).trim();
      final tokens = p
          .substring(colon + 1)
          .split(',')
          .map((t) => t.trim().toUpperCase())
          .toList();
      if (uuid.isNotEmpty && !out.contains(uuid) && test(tokens)) out.add(uuid);
    }
    return out;
  }
}

/// A Sonos zone group (the coordinator plus any grouped rooms).
class ZoneGroup {
  final String coordinatorUuid;
  final List<ZoneGroupMember> members;

  const ZoneGroup({required this.coordinatorUuid, required this.members});

  ZoneGroupMember? get coordinator {
    for (final m in members) {
      if (m.uuid == coordinatorUuid) return m;
    }
    return members.isEmpty ? null : members.first;
  }
}

/// The full discovered system: every group plus a flat device index.
class SonosSystem {
  final List<ZoneGroup> groups;
  final Map<String, SonosDevice> devicesByUuid;

  const SonosSystem({required this.groups, required this.devicesByUuid});

  /// All visible rooms across all groups. Excludes Invisible members (the
  /// hidden half of a stereo pair / bonded satellites), which aren't rooms.
  List<ZoneGroupMember> get allMembers => groups
      .expand((g) => g.members)
      .where((m) => !m.invisible)
      .toList(growable: false);

  /// Home theaters present in the system (e.g. an Arc with surrounds).
  List<ZoneGroupMember> get homeTheaters =>
      allMembers.where((m) => m.isHomeTheater).toList(growable: false);

  /// Stereo pairs present in the system.
  List<ZoneGroupMember> get stereoPairs =>
      allMembers.where((m) => m.isStereoPair).toList(growable: false);

  /// UUIDs already committed to a role (HT primary/satellite, stereo pair, or a
  /// hidden half) and therefore not free to bond elsewhere.
  Set<String> get _bondedUuids => {
        for (final g in groups)
          for (final m in g.members) ...[
            if (m.isHomeTheater) m.uuid,
            if (m.invisible) m.uuid,
            ...m.satellites.map((s) => s.uuid),
            ...m.stereoPairUuids,
          ],
      };

  /// Standalone, un-bonded speakers — candidates to bond as fronts/surrounds or
  /// pair. Excludes soundbars, subs, HT members, stereo pairs, and hidden halves.
  List<SonosDevice> get bondableSpeakers {
    final bonded = _bondedUuids;
    return devicesByUuid.values
        .where((d) => !bonded.contains(d.uuid) && !d.isSoundbar && !d.isSub)
        .toList(growable: false);
  }

  /// Standalone Sonos Subs free to bond as the `SW` channel of a home theater.
  List<SonosDevice> get bondableSubs {
    final bonded = _bondedUuids;
    return devicesByUuid.values
        .where((d) => d.isSub && !bonded.contains(d.uuid))
        .toList(growable: false);
  }

  SonosDevice? device(String uuid) => devicesByUuid[uuid];
}
