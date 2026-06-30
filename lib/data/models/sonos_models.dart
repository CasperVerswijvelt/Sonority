/// Domain models for the local Sonos system.
///
/// These intentionally mirror the data we can read from the undocumented local
/// UPnP API: device descriptions (`/xml/device_description.xml`) and the
/// `ZoneGroupTopology` service (`GetZoneGroupState`).
library;

import '../sonos/zone_layout.dart' show GroupChannel;

export '../sonos/zone_layout.dart' show GroupChannel;

/// How a speaker group bond classifies for display. A "group" is any member
/// carrying a `ChannelMapSet` (stereo pair / zone / custom L-R layout).
enum GroupKind { none, stereoPair, zone, custom }

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

  /// Parsed `ChannelMapSet` entries: each `(uuid, channel-token-set)`, primary
  /// first. Shared by stereo-pair and zone detection. A stereo pair's entries
  /// are single-sided (`LF,LF` / `RF,RF`); a zone's are full-range (`LF,RF`).
  List<({String uuid, Set<String> tokens})> get _channelMapEntries {
    final cms = channelMapSet;
    if (cms == null || cms.isEmpty) return const [];
    final out = <({String uuid, Set<String> tokens})>[];
    for (final part in cms.split(';')) {
      final colon = part.indexOf(':');
      if (colon < 0) continue;
      final uuid = part.substring(0, colon).trim();
      if (uuid.isEmpty) continue;
      out.add((
        uuid: uuid,
        tokens: part
            .substring(colon + 1)
            .split(',')
            .map((t) => t.trim().toUpperCase())
            .where((t) => t.isNotEmpty)
            .toSet(),
      ));
    }
    return out;
  }

  /// Every UUID in the `ChannelMapSet` (all bonded speakers, INCLUDING a Sub),
  /// primary first. Used to mark all of them as committed/bonded.
  List<String> get channelMapUuids =>
      [for (final e in _channelMapEntries) e.uuid];

  /// The audio (non-Sub) entries — used for stereo/zone/custom classification so
  /// a Sub (`SW`) in the map doesn't change the shape (a pair+sub is still a pair).
  List<({String uuid, Set<String> tokens})> get _audioEntries =>
      [for (final e in _channelMapEntries) if (!e.tokens.contains('SW')) e];

  /// The UUID of the bonded Sub (the `SW` entry), or null.
  String? get subUuid {
    for (final e in _channelMapEntries) {
      if (e.tokens.contains('SW')) return e.uuid;
    }
    return null;
  }

  /// True when this visible member carries a `ChannelMapSet` — i.e. it's a
  /// bonded **speaker group** (stereo pair / zone / custom L-R layout).
  bool get isGroup => channelMapSet?.isNotEmpty ?? false;

  /// True when this group is a stereo pair: exactly two single-sided audio
  /// entries (one `LF`-only, one `RF`-only). A Sub may also be present.
  bool get isStereoPair {
    final e = _audioEntries;
    if (e.length != 2) return false;
    bool leftOnly(Set<String> t) => t.contains('LF') && !t.contains('RF');
    bool rightOnly(Set<String> t) => t.contains('RF') && !t.contains('LF');
    return (leftOnly(e[0].tokens) && rightOnly(e[1].tokens)) ||
        (rightOnly(e[0].tokens) && leftOnly(e[1].tokens));
  }

  /// True when this group is a Sonos **zone**: ≥2 audio members, each full-range
  /// (`LF`+`RF`). Confirmed format on hardware (`tool/zone_probe.dart`).
  bool get isZone {
    final e = _audioEntries;
    return e.length >= 2 &&
        e.every((m) => m.tokens.contains('LF') && m.tokens.contains('RF'));
  }

  /// Display classification for the group (a Sub doesn't change it).
  GroupKind get groupKind => !isGroup
      ? GroupKind.none
      : isStereoPair
          ? GroupKind.stereoPair
          : isZone
              ? GroupKind.zone
              : GroupKind.custom;

  /// Per-speaker channel assignment of the audio members (excludes the Sub),
  /// coordinator first — for the group card + custom-edit display.
  Map<String, GroupChannel> get groupChannels => {
        for (final e in _audioEntries)
          e.uuid: (e.tokens.contains('LF') && e.tokens.contains('RF'))
              ? GroupChannel.both
              : (e.tokens.contains('LF') ? GroupChannel.left : GroupChannel.right),
      };

  /// [leftUuid, rightUuid] of the stereo pair, parsed from the ChannelMapSet.
  List<String> get stereoPairUuids => channelMapUuids;

  /// UUIDs of all zone members (coordinator first), or empty if not a zone.
  List<String> get zoneMemberUuids => isZone ? channelMapUuids : const [];

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

  /// Sonos zones present in the system (multi-speaker bonds).
  List<ZoneGroupMember> get zones =>
      allMembers.where((m) => m.isZone).toList(growable: false);

  /// All bonded **speaker groups** (stereo pairs, zones, and custom L-R layouts)
  /// — every visible member carrying a `ChannelMapSet`. The overview's unified
  /// "Speaker groups" section.
  List<ZoneGroupMember> get speakerGroups =>
      allMembers.where((m) => m.isGroup).toList(growable: false);

  /// UUIDs already committed to a role (HT primary/satellite, or either half of
  /// a stereo pair) and therefore not free to bond elsewhere.
  ///
  /// NB: we deliberately do NOT treat every `Invisible` member as bonded — a
  /// standalone Sub is its own Invisible group member (Subs have no visible
  /// room), and excluding it here is what hid freed Subs from `bondableSubs`.
  /// The hidden half of a stereo pair is already covered by the visible
  /// primary's [stereoPairUuids], and bonded satellites by [satellites].
  Set<String> get _bondedUuids => {
        for (final g in groups)
          for (final m in g.members) ...[
            if (m.isHomeTheater) m.uuid,
            ...m.satellites.map((s) => s.uuid),
            // Covers both stereo-pair halves and all zone members.
            ...m.channelMapUuids,
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

  /// Standalone speakers eligible to form a zone: bondable individual speakers,
  /// excluding Amps (Amps and Subs can't be zoned; soundbars/subs are already
  /// excluded by [bondableSpeakers]). Hardware-confirmed that Play:1 (not on
  /// Sonos' official list) zones fine, so we don't gate on the model list —
  /// create polls to confirm and surfaces a clear error if Sonos rejects it.
  List<SonosDevice> get zoneableSpeakers =>
      bondableSpeakers.where((d) => !d.isAmp).toList(growable: false);

  /// Standalone Sonos Subs free to bond as the `SW` channel of a home theater.
  List<SonosDevice> get bondableSubs {
    final bonded = _bondedUuids;
    return devicesByUuid.values
        .where((d) => d.isSub && !bonded.contains(d.uuid))
        .toList(growable: false);
  }

  SonosDevice? device(String uuid) => devicesByUuid[uuid];
}
