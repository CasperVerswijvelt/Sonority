import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/sonos_controller.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/entity_cards.dart';
import '../widgets/info_note.dart';
import '../widgets/section_header.dart';
import 'profile.dart';
import 'profile_controller.dart';
import 'profile_ui.dart';

/// Captures a profile from a live snapshot: pick which of the current entities
/// (home theaters / stereo pairs / rooms) to include, name it, save.
///
/// Two modes: when [profileId] is null this creates a new profile (name it +
/// save). When set it **re-snapshots** an existing one: it drops the name/
/// appearance editor, pre-selects the entities originally in the profile, and on
/// confirm hands the recaptured entities back to the detail screen (via
/// `Navigator.pop`) as an unsaved change — the detail screen's Save commits it.
class ProfileCreateScreen extends ConsumerStatefulWidget {
  final String? profileId;
  const ProfileCreateScreen({super.key, this.profileId});

  @override
  ConsumerState<ProfileCreateScreen> createState() => _State();
}

class _State extends ConsumerState<ProfileCreateScreen> {
  final _name = TextEditingController();
  final List<EntitySnapshot> _entities = [];
  final Map<String, bool> _included = {};
  bool _seeded = false;
  bool _saveAudio = false;
  bool _saveVolume = false;
  bool _saving = false;
  String _iconId = kDefaultProfileIcon;
  int _color = 0;

  void _seed(SonosSystem system, Profile? existing, List<Profile> profiles) {
    if (_seeded) return;
    _name.text = existing?.name ?? _defaultName(profiles);
    _iconId = existing?.iconId ?? kDefaultProfileIcon;
    _color = existing?.color ?? 0;
    // Re-snapshot: default the settings toggles to what the profile already
    // captured, so recapturing doesn't silently drop its saved EQ/volume.
    _saveAudio = existing?.hasAudioSettings ?? false;
    _saveVolume = existing?.hasVolume ?? false;
    // Re-snapshot pre-selects the entities that were originally in the profile.
    // Match by involved UUIDs, not primaryUuid — current live bonding may differ
    // from what the profile stored, which is the whole point of re-snapshotting.
    final originalUuids =
        existing?.entities.expand((e) => e.involvedUuids).toSet();
    for (final m in system.allMembers) {
      final e = EntitySnapshot.fromMember(m);
      _entities.add(e);
      _included[e.primaryUuid] = originalUuids == null
          ? true
          : e.involvedUuids.any(originalUuids.contains);
    }
    _seeded = true;
  }

  /// A helpful default that isn't already taken ("My setup", then "My setup 2",
  /// …) so New profile doesn't open on a name-collision error.
  String _defaultName(List<Profile> profiles) {
    final base = context.l10n.profileDefaultName;
    if (!isProfileNameTaken(profiles, base)) return base;
    for (var i = 2;; i++) {
      final candidate = '$base $i';
      if (!isProfileNameTaken(profiles, candidate)) return candidate;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final system = ref.watch(sonosControllerProvider).value;
    final profiles = ref.watch(profilesProvider).value ?? const [];
    final isResnapshot = widget.profileId != null;
    final existing = isResnapshot
        ? profiles
            .where((p) => p.id == widget.profileId)
            .cast<Profile?>()
            .firstOrNull
        : null;

    if (system == null) {
      return Scaffold(
        appBar: AppBar(
            title: Text(isResnapshot
                ? context.l10n.profileResnapshot
                : context.l10n.profileNew)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              context.l10n.profileScanFirstCreate,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    // Re-snapshot needs its profile loaded before seeding name/selection.
    if (isResnapshot && existing == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    _seed(system, existing, profiles);

    final name = _name.text.trim();
    final taken = isProfileNameTaken(profiles, name, exceptId: widget.profileId);
    final anyIncluded = _included.values.any((v) => v);
    final canSave = name.isNotEmpty && !taken && anyIncluded && !_saving;

    return AppScaffold(
      title: isResnapshot
          ? context.l10n.profileResnapshot
          : context.l10n.profileNew,
      bottomOverlay: _BottomButtonBar(
        label: _saving
            ? context.l10n.profileReadingSettings
            : isResnapshot
                ? context.l10n.profileUseSnapshot
                : context.l10n.profileCreate,
        onPressed: canSave ? () => _save(name, existing) : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (isResnapshot) ...[
            // Non-destructive: nothing is written until the user saves on the
            // profile screen, so this is a light note, not a warning.
            InfoNote(context.l10n.profileResnapshotNote),
            Gap.l,
          ] else
            // Name + appearance are edited on the profile screen for an existing
            // profile; only create-new needs them here.
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: ProfileNameField(
                controller: _name,
                iconId: _iconId,
                color: _color,
                nameTaken: taken,
                onChanged: () => setState(() {}),
                onAppearanceChanged: (icon, color) => setState(() {
                  _iconId = icon;
                  _color = color;
                }),
              ),
            ),
          // Only the create flow needs the "what applying does" primer; on
          // re-snapshot the profile already exists and the detail screen owns
          // the review.
          if (!isResnapshot) ...[
            InfoNote(context.l10n.profileApplyPrimer),
            Gap.l,
          ],
          SectionHeader(
            context.l10n.profileIncludeHeader,
            helper: context.l10n.profileIncludeHelper,
          ),
          for (final e in _entities) ...[
            _SelectableEntityCard(
              entity: e,
              system: system,
              included: _included[e.primaryUuid] ?? true,
              onChanged: (v) => setState(() => _included[e.primaryUuid] = v),
            ),
            Gap.s,
          ],
          Gap.l,
          SectionHeader(
            context.l10n.profileSpeakerSettingsHeader,
            helper: context.l10n.profileSpeakerSettingsHelper,
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                // Split card: each tile rounds only the corners it shares with
                // the card, so the ink highlight matches (top tile → top corners,
                // bottom tile → bottom corners; the divider edge stays square).
                SwitchListTile(
                  value: _saveAudio,
                  onChanged: (v) => setState(() => _saveAudio = v),
                  shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(12))),
                  secondary: const Icon(Icons.tune),
                  title: Text(context.l10n.profileSaveAudio),
                  subtitle: Text(context.l10n.profileSaveAudioSubtitle),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: _saveVolume,
                  onChanged: (v) => setState(() => _saveVolume = v),
                  shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(bottom: Radius.circular(12))),
                  secondary: const Icon(Icons.volume_up),
                  title: Text(context.l10n.profileSaveVolume),
                  subtitle: Text(context.l10n.profileSaveVolumeSubtitle),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save(String name, Profile? existing) async {
    var chosen = [
      for (final e in _entities)
        if (_included[e.primaryUuid] ?? false) e,
    ];
    final router = GoRouter.of(context);
    final notifier = ref.read(profilesProvider.notifier);

    // Reading settings is several SOAP calls per speaker — show progress and
    // enrich the snapshots before returning/saving them.
    if (_saveAudio || _saveVolume) {
      setState(() => _saving = true);
      try {
        chosen = await ref
            .read(sonosControllerProvider.notifier)
            .captureSettings(chosen, audio: _saveAudio, volume: _saveVolume);
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
    if (!mounted) return;

    if (existing != null) {
      // Re-snapshot: hand the recaptured entities back to the profile screen as
      // an unsaved change — it commits them on Save, no overwrite here.
      router.pop(chosen);
    } else {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      await notifier.add(Profile(
          id: id, name: name, entities: chosen, iconId: _iconId, color: _color));
      router.go('/profiles');
    }
  }
}

class _SelectableEntityCard extends StatelessWidget {
  final EntitySnapshot entity;
  final SonosSystem system;
  final bool included;
  final ValueChanged<bool> onChanged;

  const _SelectableEntityCard({
    required this.entity,
    required this.system,
    required this.included,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Compact summary, matching the profile detail / overview tiles.
    final model = EntityCardModel.fromSnapshot(system, entity.toMember());
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: CheckboxListTile(
        value: included,
        onChanged: (v) => onChanged(v ?? false),
        secondary: Icon(model.icon),
        title: Text(entity.label),
        subtitle: Text(model.subtitle),
      ),
    );
  }
}

/// A full-width button over a scrim so the list scrolls visibly behind it.
class _BottomButtonBar extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const _BottomButtonBar({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [surface.withValues(alpha: 0), surface, surface],
        ),
      ),
      child: FilledButton(onPressed: onPressed, child: Text(label)),
    );
  }
}
