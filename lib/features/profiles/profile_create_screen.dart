import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/sonos_controller.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/info_note.dart';
import '../widgets/section_header.dart';
import '../widgets/settings_section.dart';
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
    const base = 'My setup';
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
        appBar: AppBar(title: Text(isResnapshot ? 'Re-snapshot' : 'New profile')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Scan your system first (System tab), then create a '
              'profile from it.',
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
      title: isResnapshot ? 'Re-snapshot' : 'New profile',
      bottomOverlay: _BottomButtonBar(
        label: _saving
            ? 'Reading settings…'
            : isResnapshot
                ? 'Use snapshot'
                : 'Create profile',
        onPressed: canSave ? () => _save(name, existing) : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (isResnapshot) ...[
            // Non-destructive: nothing is written until the user saves on the
            // profile screen, so this is a light note, not a warning.
            const InfoNote(
              'Recapture your current setup, then review and save it '
              'on the profile screen.',
            ),
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
            const InfoNote(
              'Applying a profile later rebuilds these speakers into this '
              'layout. Any speaker that’s part of a different setup at that '
              'time is removed from it first — which can dissolve another '
              'stereo pair or zone and free its other speakers.',
            ),
            Gap.l,
          ],
          const SectionHeader(
            'Include',
            helper: 'Pick which of your current home theaters, pairs and '
                'rooms to capture in this profile.',
          ),
          for (final e in _entities)
            _SelectableEntityCard(
              entity: e,
              included: _included[e.primaryUuid] ?? true,
              onChanged: (v) => setState(() => _included[e.primaryUuid] = v),
            ),
          Gap.l,
          const SectionHeader(
            'Speaker settings',
            helper: 'Optionally snapshot each speaker’s current settings and '
                'restore them when this profile is applied.',
          ),
          // Flat settings rows (not a card) — these are toggles, matching the
          // Trueplay / diagnostics registers.
          SettingsSection(children: [
            SwitchListTile(
              value: _saveAudio,
              onChanged: (v) => setState(() => _saveAudio = v),
              secondary: const Icon(Icons.tune),
              title: const Text('Save audio settings'),
              subtitle: const Text(
                  'EQ, night sound, speech enhancement, sub & surround '
                  'levels, lip sync & more'),
            ),
            const Divider(height: 1),
            SwitchListTile(
              value: _saveVolume,
              onChanged: (v) => setState(() => _saveVolume = v),
              secondary: const Icon(Icons.volume_up),
              title: const Text('Save volume'),
              subtitle: const Text(
                  'Applying the profile will change how loud each speaker plays'),
            ),
          ]),
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
      final now = DateTime.now();
      await notifier.add(Profile(
          id: now.microsecondsSinceEpoch.toString(),
          name: name,
          entities: chosen,
          iconId: _iconId,
          color: _color,
          updatedAt: now));
      router.go('/profiles');
    }
  }
}

/// A card-less selection row (the shared selection register) for one capturable
/// entity — checkbox + name + kind, matching the speaker pickers in the flows.
class _SelectableEntityCard extends StatelessWidget {
  final EntitySnapshot entity;
  final bool included;
  final ValueChanged<bool> onChanged;

  const _SelectableEntityCard({
    required this.entity,
    required this.included,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: included,
      onChanged: (v) => onChanged(v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(entity.label),
      subtitle: Text(entity.kindLabel),
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
