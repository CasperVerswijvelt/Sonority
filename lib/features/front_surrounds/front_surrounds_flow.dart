import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/sonos_controller.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/bonding_progress_screen.dart';
import '../widgets/bondable_speaker_tile.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/identify_controls.dart';
import '../widgets/info_note.dart';
import '../widgets/speaker_diagram.dart';
import '../widgets/speaker_side_card.dart';

/// Seeds the configure-HT selectors from [member]'s current bond: front uuids
/// ordered [left, right] (a single device on both fronts — an Amp — collapses to
/// one), rear surrounds [rearLeft, rearRight], sub uuids (up to two), and the
/// first step that still needs attention (fronts → surrounds → sub, else 0).
({List<String> fronts, List<String> surrounds, List<String> subs, int step})
    seedHtRoles(ZoneGroupMember member) {
  final ca = member.channelAssignments;
  final fronts = <String>[];
  final lf = ca[SonosChannel.leftFront], rf = ca[SonosChannel.rightFront];
  if (lf != null && lf == rf) {
    fronts.add(lf); // one device on both fronts ⇒ an Amp
  } else {
    if (lf != null) fronts.add(lf);
    if (rf != null) fronts.add(rf);
  }
  final surrounds = <String>[
    if (ca[SonosChannel.leftRear] case final u?) u,
    if (ca[SonosChannel.rightRear] case final u?) u,
  ];
  final subs = member.subUuids;
  final step = fronts.isEmpty
      ? 0
      : surrounds.isEmpty
          ? 1
          : subs.isEmpty
              ? 2
              : 0;
  return (fronts: fronts, surrounds: surrounds, subs: subs, step: step);
}

/// Guided flow to complete a home-theater layout in-app: dedicated front L/R
/// (two speakers or a single Amp), rear surrounds (L/R), and a sub — each step
/// optional. Applies in stages with live per-step progress (see
/// [SonosController.applyHomeTheaterLayout]).
class FrontSurroundsFlow extends ConsumerStatefulWidget {
  final String soundbarUuid;
  const FrontSurroundsFlow({super.key, required this.soundbarUuid});

  @override
  ConsumerState<FrontSurroundsFlow> createState() => _FrontSurroundsFlowState();
}

class _FrontSurroundsFlowState extends ConsumerState<FrontSurroundsFlow>
    with IdentifyMixin {
  int _step = 0;
  final List<String> _fronts = []; // uuids, order [left, right] (or [amp])
  final List<String> _surrounds = []; // uuids, order [rearLeft, rearRight]
  final List<String> _subs = []; // uuids, up to two (HT dual-sub)

  @override
  void initState() {
    super.initState();
    // Seed the selection from the HT's current layout so already-bonded speakers
    // show pre-selected (WYSIWYG) — deselecting one then unbonds it on apply. Read
    // once from the authoritative channel map; build() keeps it live thereafter.
    final member = ref
        .read(sonosControllerProvider)
        .value
        ?.allMembers
        .where((m) => m.uuid == widget.soundbarUuid)
        .cast<ZoneGroupMember?>()
        .firstOrNull;
    if (member == null) return;
    final seed = seedHtRoles(member);
    _fronts.addAll(seed.fronts);
    _surrounds.addAll(seed.surrounds);
    _subs.addAll(seed.subs);
    _step = seed.step;
  }

  @override
  Widget build(BuildContext context) {
    final system = ref.watch(sonosControllerProvider).value;
    final member = system?.allMembers
        .where((m) => m.uuid == widget.soundbarUuid)
        .cast<ZoneGroupMember?>()
        .firstOrNull;
    final soundbar = system?.device(widget.soundbarUuid);

    if (system == null || member == null || soundbar == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Speakers free to assign, minus ones already chosen in another role here.
    // Already-bonded speakers of *this* HT aren't in `bondableSpeakers`, so add
    // the current-role picks explicitly — they must show selected & deselectable.
    final chosenElsewhere = <String>{..._fronts, ..._surrounds, ..._subs};
    List<SonosDevice> avail(List<String> keepFor) {
      final out = <SonosDevice>[
        for (final d in system.bondableSpeakers)
          if (keepFor.contains(d.uuid) || !chosenElsewhere.contains(d.uuid)) d,
      ];
      for (final id in keepFor) {
        if (out.any((d) => d.uuid == id)) continue;
        final d = system.device(id);
        if (d != null) out.add(d);
      }
      return out;
    }

    final freeSubs = <SonosDevice>[
      ...system.bondableSubs,
      for (final id in _subs)
        if (!system.bondableSubs.any((d) => d.uuid == id))
          if (system.device(id) case final d?) d,
    ];

    // Chime only for a standalone speaker; an already-bonded pick (a current
    // satellite shown pre-selected) can only blink its LED.
    Widget idControls(SonosDevice d) =>
        identifyButtons(d, chime: system.isStandalone(d.uuid));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up home theater'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: ScrolledUnderDivider(),
        ),
      ),
      body: SafeArea(
        child: Stepper(
          currentStep: _step,
          type: StepperType.vertical,
          onStepTapped: (i) => setState(() => _step = i),
          controlsBuilder: (context, _) =>
              _controls(context, system, member, soundbar),
          steps: [
            Step(
              title: const Text('Front speakers'),
              subtitle: const Text('Optional'),
              isActive: _step >= 0,
              state: _fronts.isNotEmpty && _frontsValid
                  ? StepState.complete
                  : StepState.indexed,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pick two speakers (or a single Amp) for the front '
                      'left & right, then set which is which.',
                      style: Theme.of(context).textTheme.bodySmall),
                  Gap.s,
                  _ChooseSpeakers(
                    candidates: avail(_fronts),
                    selected: _fronts,
                    onToggle: _toggleFront,
                    identifyControls: idControls,
                  ),
                  if (_ampMode) ...[
                    Gap.m,
                    _AmpWiringNote(
                      amp: system.device(_fronts.first),
                      identifyControls: idControls,
                    ),
                  ] else if (_fronts.length == 2) ...[
                    Gap.m,
                    _AssignSides(
                      system: system,
                      selected: _fronts,
                      leftLabel: 'LEFT',
                      rightLabel: 'RIGHT',
                      onSwap: () => setState(
                          () => _fronts.setAll(0, [_fronts[1], _fronts[0]])),
                      identifyControls: idControls,
                    ),
                  ],
                ],
              ),
            ),
            Step(
              title: const Text('Rear surrounds'),
              subtitle: const Text('Optional'),
              isActive: _step >= 1,
              state: _surrounds.length == 2 ? StepState.complete : StepState.indexed,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pick two speakers for the rear left & right surrounds.',
                      style: Theme.of(context).textTheme.bodySmall),
                  Gap.s,
                  _ChooseSpeakers(
                    candidates: avail(_surrounds),
                    selected: _surrounds,
                    onToggle: _toggleSurround,
                    identifyControls: idControls,
                    allowAmp: false,
                  ),
                  if (_surrounds.length == 2) ...[
                    Gap.m,
                    _AssignSides(
                      system: system,
                      selected: _surrounds,
                      leftLabel: 'REAR LEFT',
                      rightLabel: 'REAR RIGHT',
                      onSwap: () => setState(() =>
                          _surrounds.setAll(0, [_surrounds[1], _surrounds[0]])),
                      identifyControls: idControls,
                    ),
                  ],
                ],
              ),
            ),
            Step(
              title: const Text('Subwoofer'),
              subtitle: const Text('Optional'),
              isActive: _step >= 2,
              state: _subs.isNotEmpty ? StepState.complete : StepState.indexed,
              content: _ChooseSub(
                subs: freeSubs,
                selected: _subs,
                onToggle: _toggleSub,
                identifyControls: idControls,
              ),
            ),
            Step(
              title: const Text('Review & apply'),
              isActive: _step >= 3,
              content: _Review(
                  system: system,
                  member: member,
                  additions: _additions(system),
                  subCount: _subs.length),
            ),
          ],
        ),
      ),
    );
  }

  bool _deviceIsAmp(String uuid) =>
      ref.read(sonosControllerProvider).value?.device(uuid)?.isAmp ?? false;

  bool get _ampMode => _fronts.length == 1 && _deviceIsAmp(_fronts.first);
  bool get _frontsValid => _fronts.isEmpty || _fronts.length == 2 || _ampMode;
  bool get _surroundsValid => _surrounds.isEmpty || _surrounds.length == 2;

  /// The selection differs from what's currently bonded — the only case worth
  /// applying (an unchanged layout is a zero-write no-op, so we disable Apply for
  /// it). Compares fronts/surrounds channel→uuid and the sub set to the live map.
  bool _differs(SonosSystem system, ZoneGroupMember member) {
    final desired = {
      for (final e in _additions(system).entries) e.key: e.value.uuid,
    };
    final current = {
      for (final c in const [
        SonosChannel.leftFront,
        SonosChannel.rightFront,
        SonosChannel.leftRear,
        SonosChannel.rightRear,
      ])
        if (member.channelAssignments[c] case final u?) c: u,
    };
    if (!mapEquals(desired, current)) return true;
    return !setEquals(_subs.toSet(), member.subUuids.toSet());
  }

  void _toggleFront(SonosDevice d) => setState(() {
        if (_fronts.contains(d.uuid)) {
          _fronts.remove(d.uuid);
          return;
        }
        if (d.isAmp) {
          _fronts
            ..clear()
            ..add(d.uuid);
          return;
        }
        if (_ampMode) _fronts.clear();
        if (_fronts.length < 2) _fronts.add(d.uuid);
      });

  void _toggleSurround(SonosDevice d) => setState(() {
        if (_surrounds.contains(d.uuid)) {
          _surrounds.remove(d.uuid);
        } else if (_surrounds.length < 2) {
          _surrounds.add(d.uuid);
        }
      });

  void _toggleSub(SonosDevice d) => setState(() {
        if (_subs.contains(d.uuid)) {
          _subs.remove(d.uuid);
        } else if (_subs.length < 2) {
          _subs.add(d.uuid); // HT supports up to two Subs
        }
      });

  /// The role → speaker map this flow will bond.
  Map<SonosChannel, SonosDevice> _additions(SonosSystem system) {
    final out = <SonosChannel, SonosDevice>{};
    SonosDevice? dev(String uuid) => system.device(uuid);
    if (_ampMode) {
      final amp = dev(_fronts.first);
      if (amp != null) {
        out[SonosChannel.leftFront] = amp;
        out[SonosChannel.rightFront] = amp;
      }
    } else if (_fronts.length == 2) {
      final l = dev(_fronts[0]), r = dev(_fronts[1]);
      if (l != null && r != null) {
        out[SonosChannel.leftFront] = l;
        out[SonosChannel.rightFront] = r;
      }
    }
    if (_surrounds.length == 2) {
      final l = dev(_surrounds[0]), r = dev(_surrounds[1]);
      if (l != null && r != null) {
        out[SonosChannel.leftRear] = l;
        out[SonosChannel.rightRear] = r;
      }
    }
    // Subs are threaded separately (see [_subDevices]) — the channel can repeat,
    // so it can't live in this one-per-channel map.
    return out;
  }

  /// The chosen Sub device(s) — up to two for a dual-sub HT.
  List<SonosDevice> _subDevices(SonosSystem system) =>
      [for (final u in _subs) system.device(u)].whereType<SonosDevice>().toList();

  Widget _controls(BuildContext context, SonosSystem system,
      ZoneGroupMember member, SonosDevice soundbar) {
    final canNext = switch (_step) {
      0 => _frontsValid,
      1 => _surroundsValid,
      _ => true,
    };
    final isLast = _step == 3;
    final canApply =
        _frontsValid && _surroundsValid && _differs(system, member);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          if (_step > 0)
            TextButton(
              onPressed: () => setState(() => _step--),
              child: const Text('Back'),
            ),
          Gap.s,
          Expanded(
            child: FilledButton(
              onPressed: isLast
                  ? (canApply ? () => _apply(member, soundbar) : null)
                  : (canNext ? () => setState(() => _step++) : null),
              child: Text(isLast ? 'Apply' : 'Continue'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _apply(ZoneGroupMember member, SonosDevice soundbar) async {
    final system = ref.read(sonosControllerProvider).value;
    if (system == null) return;
    final additions = _additions(system);
    final subs = _subDevices(system);

    // Speakers bonded now but not in the new selection → they'll be unbonded.
    // Live writes are destructive, so confirm before removing any (gotcha #3).
    final desiredUuids = <String>{..._fronts, ..._surrounds, ..._subs};
    final removed = <String>{
      for (final c in const [
        SonosChannel.leftFront,
        SonosChannel.rightFront,
        SonosChannel.leftRear,
        SonosChannel.rightRear,
      ])
        ...member.uuidsForChannel(c),
      ...member.subUuids,
    }.difference(desiredUuids);
    if (removed.isNotEmpty && !await _confirmRemoval(system, removed)) return;
    if (!mounted) return;

    final controller = ref.read(sonosControllerProvider.notifier);
    final router = GoRouter.of(context);
    final outcome = await showBondingProgress(
      context,
      title: 'Set up home theater',
      run: () => controller.applyHomeTheaterLayout(
        soundbar: member,
        soundbarDevice: soundbar,
        layout: additions,
        subs: subs,
      ),
    );
    // No success toast — the progress screen already showed the outcome.
    if (outcome == BondingOutcome.success) router.pop();
  }

  /// Confirms unbonding the speakers the user deselected (they become standalone
  /// rooms again). Shows their type since a bonded speaker's name is absorbed.
  Future<bool> _confirmRemoval(SonosSystem system, Set<String> removed) async {
    final types = [
      for (final u in removed) system.device(u)?.typeLabel ?? 'Speaker',
    ].join(', ');
    return confirmDialog(
      context,
      icon: Icons.link_off,
      title: 'Unbond ${removed.length} speaker${removed.length == 1 ? '' : 's'}?',
      message: '$types will be removed from this home theater and become '
          'standalone rooms again. The rest of your layout stays as it is.',
      confirmLabel: 'Unbond',
    );
  }
}

class _ChooseSpeakers extends StatelessWidget {
  final List<SonosDevice> candidates;
  final List<String> selected;
  final void Function(SonosDevice device) onToggle;
  final Widget Function(SonosDevice device) identifyControls;
  final bool allowAmp;

  const _ChooseSpeakers({
    required this.candidates,
    required this.selected,
    required this.onToggle,
    required this.identifyControls,
    this.allowAmp = true,
  });

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) {
      return const Text(
        'No free speakers available. They must be standalone (not already part '
        'of a home theater or stereo pair).',
      );
    }
    final hasAmp = allowAmp && candidates.any((d) => d.isAmp);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            hasAmp
                ? 'Pick two speakers (ideally identical), or a single Sonos Amp '
                    'that drives both front speakers.'
                : 'Pick exactly two — ideally an identical pair.',
            style: Theme.of(context).textTheme.bodySmall),
        Gap.s,
        ...candidates.map((d) {
          final isSel = selected.contains(d.uuid);
          final isAmp = allowAmp && d.isAmp;
          final disabled = !isSel && !isAmp && selected.length >= 2;
          return BondableSpeakerTile(
            device: d,
            selected: isSel,
            onChanged: disabled ? null : (_) => onToggle(d),
            subtitle: isAmp
                ? '${d.typeLabel} — drives both fronts (L + R)'
                : d.typeLabel,
            secondary: identifyControls(d),
          );
        }),
      ],
    );
  }
}

class _ChooseSub extends StatelessWidget {
  final List<SonosDevice> subs;
  final List<String> selected; // uuids, up to two
  final void Function(SonosDevice device) onToggle;
  final Widget Function(SonosDevice device) identifyControls;

  const _ChooseSub({
    required this.subs,
    required this.selected,
    required this.onToggle,
    required this.identifyControls,
  });

  @override
  Widget build(BuildContext context) {
    if (subs.isEmpty) {
      return const Text(
          'No free subwoofer found. A Sonos Sub must be standalone (not already '
          'bonded to another home theater).');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pick one or two subwoofers to add as low-frequency channels.',
            style: Theme.of(context).textTheme.bodySmall),
        Gap.s,
        ...subs.map((d) {
          final isSel = selected.contains(d.uuid);
          return BondableSpeakerTile(
            device: d,
            selected: isSel,
            onChanged: (!isSel && selected.length >= 2) ? null : (_) => onToggle(d),
            subtitle: d.typeLabel,
            secondary: identifyControls(d),
          );
        }),
      ],
    );
  }
}

/// Amp mode: the Amp drives both fronts itself — nothing to assign in-app.
class _AmpWiringNote extends StatelessWidget {
  final SonosDevice? amp;
  final Widget Function(SonosDevice device) identifyControls;

  const _AmpWiringNote({required this.amp, required this.identifyControls});

  @override
  Widget build(BuildContext context) {
    final amp = this.amp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'The ${amp?.modelName ?? 'Amp'} drives both front channels. Wire your '
          'left & right speakers to its L/R speaker outputs — there\'s nothing '
          'to assign here.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (amp != null) ...[
          Gap.s,
          identifyControls(amp),
        ],
      ],
    );
  }
}

class _AssignSides extends StatelessWidget {
  final SonosSystem system;
  final List<String> selected;
  final String leftLabel;
  final String rightLabel;
  final VoidCallback onSwap;
  final Widget Function(SonosDevice device) identifyControls;

  const _AssignSides({
    required this.system,
    required this.selected,
    required this.leftLabel,
    required this.rightLabel,
    required this.onSwap,
    required this.identifyControls,
  });

  @override
  Widget build(BuildContext context) {
    if (selected.length != 2) {
      return const Text('Choose two speakers first.');
    }
    final left = system.device(selected[0]);
    final right = system.device(selected[1]);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
                child: SpeakerSideCard(
                    side: leftLabel,
                    device: left,
                    controls: left == null ? null : identifyControls(left))),
            IconButton.filledTonal(
              onPressed: onSwap,
              icon: const Icon(Icons.swap_horiz),
              tooltip: 'Swap sides',
            ),
            Expanded(
                child: SpeakerSideCard(
                    side: rightLabel,
                    device: right,
                    controls: right == null ? null : identifyControls(right))),
          ],
        ),
        Gap.s,
        Text('Tap swap if the sides are reversed.',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _Review extends StatelessWidget {
  final SonosSystem system;
  final ZoneGroupMember member;
  final Map<SonosChannel, SonosDevice> additions;

  /// Resulting Sub count (existing ∪ newly picked) — for the diagram chip.
  final int subCount;
  const _Review(
      {required this.system,
      required this.member,
      required this.additions,
      required this.subCount});

  @override
  Widget build(BuildContext context) {
    if (additions.isEmpty && subCount == 0) {
      return const Text('Nothing selected yet — choose speakers above.');
    }
    // The diagram shows the DESIRED end state (the current selection), which is
    // pre-seeded from the live layout — so a deselected role correctly shows
    // empty. Speaker TYPE, not room name: a bonded name is absorbed into the HT.
    String? label(SonosChannel ch) => additions[ch]?.typeLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpeakerDiagram(
          soundbarLabel: system.device(member.uuid)?.typeLabel,
          frontLeftLabel: label(SonosChannel.leftFront),
          frontRightLabel: label(SonosChannel.rightFront),
          rearLeftLabel: label(SonosChannel.leftRear),
          rearRightLabel: label(SonosChannel.rightRear),
          subCount: subCount,
        ),
        Gap.m,
        const InfoNote(
          'The chosen speakers become hidden satellites of the soundbar (which '
          'stays the center channel). Bonding runs in steps and can take a '
          'little while; Trueplay may need re-tuning afterward. You can change '
          'this anytime.',
        ),
      ],
    );
  }
}
