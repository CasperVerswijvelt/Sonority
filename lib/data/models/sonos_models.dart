/// Domain models for the local Sonos system.
///
/// These intentionally mirror the data we can read from the undocumented local
/// UPnP API: device descriptions (`/xml/device_description.xml`) and the
/// `ZoneGroupTopology` service (`GetZoneGroupState`).
library;

import '../sonos/zone_layout.dart' show GroupChannel;

export '../sonos/zone_layout.dart'
    show GroupChannel, groupChannelShort, groupChannelLabel, groupEditIsInPlace;

/// How a speaker group bond classifies for display. A "group" is any member
/// carrying a `ChannelMapSet` (stereo pair / zone / custom L-R layout).
enum GroupKind { none, stereoPair, zone, custom }

/// Display label for a group's [GroupKind].
String groupKindLabel(GroupKind k) => switch (k) {
      GroupKind.stereoPair => 'Stereo pair',
      GroupKind.zone => 'Zone',
      GroupKind.custom => 'Custom group',
      GroupKind.none => 'Group',
    };

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

  /// Extra identity/firmware fields from device_description.xml, surfaced only
  /// in the diagnostics view + bundle (never used for logic). Nullable because a
  /// topology-only device (unreachable description) won't have them.
  final String? mac;
  final String? serial;
  final String? softwareVersion;
  final String? hardwareVersion;

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
    this.mac,
    this.serial,
    this.softwareVersion,
    this.hardwareVersion,
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

  /// Has no built-in drivers — it feeds external stereo speakers (Amp /
  /// Connect:Amp via speaker terminals, Port / Connect via line-out). So ONE
  /// box covers BOTH front channels at once (`LF,RF`), unlike a normal speaker
  /// which is a single side. Also means it can't be Trueplay-tuned.
  /// Word-bounded so a SYMFONISK Table **Lamp** isn't read as an Amp.
  bool get drivesExternalSpeakers =>
      modelName.toLowerCase().contains(RegExp(r'\b(amp|port|connect)\b'));

  /// An Amp / Connect:Amp specifically — the one line-out box Sonos' stated
  /// zone limits exclude. Narrower than [drivesExternalSpeakers] on purpose: a
  /// Port/Connect has always been offered as a zone member and nobody has
  /// reported that failing, so widening this would drop a working capability.
  bool get isAmp => modelName.toLowerCase().contains(RegExp(r'\bamp\b'));

  SonosDevice copyWith({String? ip, String? roomName}) => SonosDevice(
        uuid: uuid,
        roomName: roomName ?? this.roomName,
        modelName: modelName,
        modelNumber: modelNumber,
        ip: ip ?? this.ip,
        mac: mac,
        serial: serial,
        softwareVersion: softwareVersion,
        hardwareVersion: hardwareVersion,
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

  /// The satellite's description URL from the topology. Kept (not just the
  /// derived [ip]) so discovery can re-fetch a satellite that SSDP missed,
  /// see `SonosRepository.discover`, where a missing Sub silently cost the
  /// whole HT its sub channel on the next apply.
  final String? location;

  const SonosSatellite({
    required this.uuid,
    required this.zoneName,
    required this.channels,
    this.ip,
    this.location,
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

  /// All bonded HT Sub UUIDs (`SW` entries in the `HTSatChanMapSet`) — up to two
  /// for a dual-sub home theater. Reads the authoritative HT map (not the group
  /// `ChannelMapSet` that [subUuid] scans), so it's HT-only by design.
  List<String> get subUuids => uuidsForChannel(SonosChannel.sub);

  /// Whether this member holds [uuid] as a bonded HT satellite (front, rear or
  /// sub).
  ///
  /// ONE predicate on purpose. It existed as two hand-rolled copies, in
  /// [SonosSystem.ownerOf] and in `SonosRepository.freeSpeaker`, and they
  /// drifted: `channelAssignments` is keyed by CHANNEL, so a dual-sub map
  /// (`…:SW;…:SW`) collapses to one uuid and the FIRST sub reads as unheld. The
  /// `<Satellite>` list normally covers it, but that list vanishes for ~15s
  /// after any bonding change, which is exactly when this gets asked. With the
  /// copies out of step, the decision layer said "free this sub" and the write
  /// layer then issued no `RemoveHTSatellite` at all.
  bool holdsSatellite(String uuid) =>
      uuid != this.uuid &&
      (channelAssignments.values.contains(uuid) ||
          subUuids.contains(uuid) ||
          satellites.any((s) => s.uuid == uuid));

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

  /// True when this live group already carries exactly [targetChannels]
  /// (per-speaker channel, order-insensitive) plus [subUuid] — the "would a write
  /// change anything" test for a speaker group. Channel-aware on purpose: a
  /// membership-set-only check passes before an in-place channel reassignment has
  /// landed. Shared by the group-edit verification, the group flow's Apply gate
  /// and the profile active-match check so the three can't disagree.
  ///
  /// [coordUuid] is the one position that is NOT interchangeable: the
  /// coordinator stays visible and carries the map, and `AddBondedZones` cannot
  /// move it, so a target that coordinates elsewhere needs a full
  /// dissolve-and-recreate. Callers that know which speaker should coordinate
  /// pass it; the rest compare channels only.
  bool matchesGroupLayout(Map<String, GroupChannel> targetChannels,
      {String? subUuid, String? coordUuid}) {
    if (!isGroup || this.subUuid != subUuid) return false;
    if (coordUuid != null && channelMapUuids.firstOrNull != coordUuid) {
      return false;
    }
    final live = groupChannels;
    return live.length == targetChannels.length &&
        targetChannels.entries.every((e) => live[e.key] == e.value);
  }

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
      .toList();

  /// Home theaters present in the system (e.g. an Arc with surrounds).
  List<ZoneGroupMember> get homeTheaters =>
      allMembers.where((m) => m.isHomeTheater).toList();

  /// Stereo pairs present in the system.
  List<ZoneGroupMember> get stereoPairs =>
      allMembers.where((m) => m.isStereoPair).toList();

  /// Sonos zones present in the system (multi-speaker bonds).
  List<ZoneGroupMember> get zones =>
      allMembers.where((m) => m.isZone).toList();

  /// All bonded **speaker groups** (stereo pairs, zones, and custom L-R layouts)
  /// — every visible member carrying a `ChannelMapSet`. The overview's unified
  /// "Speaker groups" section.
  List<ZoneGroupMember> get speakerGroups =>
      allMembers.where((m) => m.isGroup).toList();

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
            // The AUTHORITATIVE channel map first. `<Satellite>` elements
            // briefly vanish for ~15s after any bonding change (gotcha #1), and
            // this set decides whether a speaker gets freed before a bond
            // write. Reading only the satellite list would let a satellite of
            // ANOTHER home theater look standalone mid-settle, skip its free,
            // and target a speaker that bar still claims.
            ...m.channelAssignments.values,
            // `channelAssignments` is keyed by CHANNEL, so a dual-sub map
            // (`…:SW;…:SW`) collapses to one uuid, and the second Sub would
            // read as standalone in exactly the mid-settle window above.
            ...m.subUuids,
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
        .toList();
  }

  /// Standalone speakers eligible to form a zone: bondable individual speakers,
  /// excluding Amps (Amps and Subs can't be zoned; soundbars/subs are already
  /// excluded by [bondableSpeakers]). Hardware-confirmed that Play:1 (not on
  /// Sonos' official list) zones fine, so we don't gate on the model list —
  /// create polls to confirm and surfaces a clear error if Sonos rejects it.
  List<SonosDevice> get zoneableSpeakers =>
      bondableSpeakers.where((d) => !d.isAmp).toList();

  /// Standalone Sonos Subs free to bond as the `SW` channel of a home theater.
  List<SonosDevice> get bondableSubs {
    final bonded = _bondedUuids;
    return devicesByUuid.values
        .where((d) => d.isSub && !bonded.contains(d.uuid))
        .toList();
  }

  /// UUIDs whose RenderingControl `GetEQ` carries the extended EQ bundle
  /// (sub/surround/night/speech/height): soundbars, plus the coordinator of any
  /// bond that is a home theater or has a bonded Sub. The Sub device itself
  /// rejects every EQ read (UPnPError 803, hardware-confirmed via `tool/eq_probe`
  /// — the sub level/crossover live on the coordinator's `GetEQ`, never the Sub).
  /// The single gate both the profile capture and the diagnostics dump read from,
  /// so the two can't drift.
  Set<String> get extendedEqUuids => {
        for (final d in devicesByUuid.values)
          if (d.isSoundbar) d.uuid,
        for (final g in groups)
          for (final m in g.members)
            if (m.isHomeTheater || m.subUuid != null) m.uuid,
      };

  SonosDevice? device(String uuid) => devicesByUuid[uuid];

  /// The visible member with [uuid], or null. Parallels [device].
  ZoneGroupMember? memberByUuid(String uuid) =>
      allMembers.where((m) => m.uuid == uuid).firstOrNull;

  /// Whether [uuid] plays audio on its own — i.e. it isn't bonded into a home
  /// theater or speaker group. Only a standalone speaker can be identified with
  /// the audio chime; a bonded satellite / group member (and a coordinator,
  /// whose chime would play the whole bond) can only blink its LED.
  bool isStandalone(String uuid) => !_bondedUuids.contains(uuid);

  /// The coordinator/primary UUID that currently owns [uuid] as a bonded member
  /// — an HT satellite, a stereo-pair half, or any zone/custom group member — or
  /// null if [uuid] is standalone. The single source of truth for "is this
  /// speaker bonded elsewhere?", shared by profile pre-flight and apply so they
  /// can't disagree (a group member must be caught by BOTH).
  String? ownerOf(String uuid) {
    for (final g in groups) {
      for (final m in g.members) {
        if (m.holdsSatellite(uuid)) {
          return m.uuid;
        }
        if (m.isGroup && m.channelMapUuids.contains(uuid)) {
          return m.channelMapUuids.first;
        }
      }
    }
    return null;
  }

  /// Every speaker belonging to the bond [m]. Its primary plus satellites and
  /// channel-map members. This is the unit a bonding change acts on: Sonos
  /// invalidates room calibration per BOND, not per speaker (EXP-23).
  Set<String> bondMemberUuids(ZoneGroupMember m) => {
        m.uuid,
        // Authoritative map first. See [_bondedUuids] on why the `<Satellite>`
        // list alone is not safe to decide bonding on, and why the sub list is
        // spread separately (a dual-sub map collapses under a channel key).
        ...m.channelAssignments.values,
        ...m.subUuids,
        ...m.satellites.map((s) => s.uuid),
        ...m.channelMapUuids,
      };

  /// Speakers already bonded into some OTHER entity, offered so a picker can
  /// take them from it rather than making the user unbond by hand first.
  ///
  /// Hardware-measured (EXP-23): `AddHTSatellite` absorbs a speaker straight out
  /// of a live stereo pair: the pair dissolves implicitly and the speaker's
  /// Trueplay COEFFICIENTS survive *in storage*, which is not retention and is
  /// never credited in copy, so the unbond-first step Sonority used to require
  /// was unnecessary. It was not the only thing costing a tuning: a
  /// bonding change clears members with no removal and no enable written at all
  /// (CLAUDE.md, Q20). What a take costs is [tuningLostBySelection].
  ///
  /// Excludes soundbars and Subs (neither is offered anywhere as a stealable
  /// speaker: the Sub pickers list standalone Subs only) and the bond
  /// [exceptPrimary], whose own members the caller lists separately.
  List<SonosDevice> stealableSpeakers({String? exceptPrimary}) => [
        for (final m in allMembers)
          if ((m.isHomeTheater || m.isGroup) && m.uuid != exceptPrimary)
            for (final id in bondMemberUuids(m))
              // A home theater's PRIMARY is the bar itself. Never a candidate,
              // and `ownerOf` returns null for it, so offering one would land it
              // in the "available" block and skip freeing. (A group's primary IS
              // a normal member and stays.)
              if (id != m.uuid || m.isGroup)
                if (device(id) case final d? when !d.isSoundbar && !d.isSub) d,
      ];

  /// Which speakers lose their Trueplay tuning when [selected] is bonded into a
  /// destination: the WHOLE of every bond the selection takes from, plus
  /// [alsoLosing].
  ///
  /// The whole bond, every time, even though storage is kinder than that,
  /// `AddHTSatellite` absorbs a speaker out of a live pair or zone (Q7/Q9/Q10)
  /// and its coefficients survive. They come back switched OFF, and the only
  /// write that switches them on destroys them (CLAUDE.md, the
  /// destructive-enable rule), so there is no retention any screen may promise.
  /// What the absorb IS still worth (skipping the free) is [canAbsorbFrom],
  /// and that is what `_freeConflicts` acts on.
  ///
  /// [alsoLosing] is what the destination itself costs, which the sources cannot
  /// know about: a group edit's own members (`AddBondedZones` rebuilds the bond
  /// even on an unchanged map, EXP-23 Q8a) or, for a home theater, its whole
  /// current membership whenever the apply writes anything at all (Q20: a purely
  /// additive bond took the bar and both rears to `available=0`).
  Set<String> tuningLostBySelection({
    required Set<String> selected,
    String? exceptPrimary,
    Set<String> alsoLosing = const {},
  }) {
    final losing = <String>{...alsoLosing};
    for (final uuid in selected) {
      final owner = ownerOf(uuid);
      if (owner == null || owner == exceptPrimary) continue;
      final source = memberByUuid(owner);
      if (source != null) losing.addAll(bondMemberUuids(source));
    }
    return losing;
  }

  /// Whether [uuid] must be freed from whatever it is bonded to before a new
  /// bond can claim it.
  ///
  /// The question is [isStandalone], NOT `ownerOf(uuid) != target`. For a
  /// group's COORDINATOR `ownerOf` returns that speaker's own uuid, so an
  /// owner-based test reads it as unbonded, skips the free, and the bond write
  /// then silently no-ops. Hardware-caught: it dissolved a live zone without
  /// forming the new group.
  ///
  /// [keep] is the target's own current members (freeing those would undo the
  /// thing being built). [absorbing] is true for a home-theater target, which
  /// takes a speaker straight out of a pair or zone with its tuning intact.
  bool mustFreeBeforeBonding(
    String uuid, {
    required Set<String> keep,
    required bool absorbing,
  }) {
    if (keep.contains(uuid) || isStandalone(uuid)) return false;
    final owner = ownerOf(uuid);
    // NO owner at all: a home theater's own PRIMARY. `ownerOf` returns null
    // for a soundbar. Where there is nothing to free it FROM, and asking
    // anyway costs a no-op write plus an 18s poll on a condition already met.
    if (owner == null) return false;
    final src = memberByUuid(owner);
    // Bonded, but the owner doesn't resolve to a VISIBLE member: the
    // `ZoneGroup ID="…:orphan"` case, an Invisible survivor whose partner is
    // gone. `memberByUuid` filters `Invisible`, so `src` is always null here,
    // but `freeSpeaker` walks `groups[].members` unfiltered and DOES recover it
    // (targeted `SeparateStereoPair` on the stale map). Must free: absorbing
    // out of a bond we can't classify is not a measured case.
    if (src == null) return true;
    return !(absorbing && canAbsorbFrom(src));
  }

  /// Whether `AddHTSatellite` can take a speaker straight out of [source]
  /// without freeing it first. True for an `AddBondedZones`-style bond (pair,
  /// zone, custom group), false for a home theater (never measured: one
  /// soundbar on the test system). A false here means the caller must free the
  /// speaker before bonding, or the write fails.
  bool canAbsorbFrom(ZoneGroupMember source) => source.isGroup;
}
