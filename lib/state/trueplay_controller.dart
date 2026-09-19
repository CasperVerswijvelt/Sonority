import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/sonos_models.dart';
import '../data/sonos/diagnostics_log.dart';
import '../data/sonos/room_calibration.dart';
import '../data/sonos/sonos_repository.dart';
import 'sonos_controller.dart'
    show sonosControllerProvider, sonosRepositoryProvider;

/// Trueplay state is a per-speaker `RenderingControl` read, orthogonal to the
/// topology, so it lives in its own provider rather than the `SonosSystem`
/// notifier. Keyed by device UUID.
@immutable
class TrueplayState {
  final Map<String, RoomCalibration> byUuid;
  final Set<String> busy; // device UUIDs currently fetching or toggling

  const TrueplayState({this.byUuid = const {}, this.busy = const {}});

  TrueplayState copyWith({
    Map<String, RoomCalibration>? byUuid,
    Set<String>? busy,
  }) => TrueplayState(byUuid: byUuid ?? this.byUuid, busy: busy ?? this.busy);
}

/// Starts a full [TrueplayController.loadAll] after the current frame: the
/// one call a bond-aware setup flow makes from `initState`.
///
/// Deferred because `load` touches provider state synchronously, which Riverpod
/// forbids during build. Best-effort: a system that hasn't been discovered yet,
/// or a flow the user has already left, simply skips it.
void loadTrueplayForPickers(WidgetRef ref) {
  final system = ref.read(sonosControllerProvider).value;
  if (system == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (ref.context.mounted) {
      ref.read(trueplayControllerProvider.notifier).loadAll(system);
    }
  });
}

final trueplayControllerProvider =
    NotifierProvider<TrueplayController, TrueplayState>(TrueplayController.new);

class TrueplayController extends Notifier<TrueplayState> {
  @override
  TrueplayState build() => const TrueplayState();

  SonosRepository get _repo => ref.read(sonosRepositoryProvider);

  List<SonosDevice> _withIp(Iterable<SonosDevice> devices) =>
      devices.where((d) => d.ip != null).toList();

  void _setBusy(Iterable<String> uuids, bool busy) {
    final next = {...state.busy};
    busy ? next.addAll(uuids) : next.removeAll(uuids);
    state = state.copyWith(busy: next);
  }

  Future<Map<String, RoomCalibration>> _readAll(
    List<SonosDevice> targets,
  ) async {
    final results = <String, RoomCalibration>{};
    await Future.wait(
      targets.map((d) async {
        try {
          results[d.uuid] = await _repo.roomCalibration(d.ip!);
        } catch (_) {
          // unreachable / unsupported speaker — leave it out of the map
        }
      }),
    );
    return results;
  }

  /// Folds a fresh read into the cache, EVICTING any target that didn't answer.
  ///
  /// A merge kept the previous value for a speaker whose re-read faulted, and
  /// the flows seed that cache before they bond (`loadTrueplayForPickers` reads
  /// every device), while bonding closes :1400 on each member for ~20-30s. So
  /// the reading left behind was a PRE-bond `available: true` for exactly the
  /// speakers the bond had just wiped, and `tunedCount` is what gates the
  /// destructive-enable confirm: a stale reading could suppress the dialog that
  /// stops a user destroying the tunings that are left. Unknown is the honest
  /// state, and it keeps the warning on.
  void _fold(List<SonosDevice> targets, Map<String, RoomCalibration> results) {
    final next = {...state.byUuid};
    for (final d in targets) {
      final fresh = results[d.uuid];
      if (fresh == null) {
        next.remove(d.uuid);
      } else {
        next[d.uuid] = fresh;
      }
    }
    state = state.copyWith(byUuid: next);
  }

  /// Fetch calibration for EVERY speaker in [system], for the bond-aware
  /// pickers.
  ///
  /// Every device, not just the candidates: taking a satellite out of another
  /// home theater costs that bond's soundbar and Sub their tuning too, and
  /// neither is ever a candidate. Gathering only candidates left them out of
  /// the cost line and out of the named losers. Both setup flows call this, so
  /// they can't drift.
  Future<void> loadAll(SonosSystem system) =>
      load(system.devicesByUuid.values);

  /// Fetch (or refresh) calibration status for a set of speakers.
  ///
  /// Each speaker settles on its OWN, rather than the whole batch clearing when
  /// the slowest one returns. `busy` suppresses every tuning claim in both
  /// setup flows (a speaker nobody has asked yet must not be described), and
  /// `loadAll` reads the entire household the moment a flow opens. Batched,
  /// one unreachable speaker held all of them busy for a full 8s SOAP timeout,
  /// which is long enough to cover the taps it takes to pick two speakers: the
  /// review card, the only gate before Apply, could render with no cost line at
  /// all because every speaker in it was still "pending".
  Future<void> load(Iterable<SonosDevice> devices) async {
    final targets = _withIp(devices);
    if (targets.isEmpty) return;
    _setBusy(targets.map((d) => d.uuid), true);
    try {
      await Future.wait(targets.map((d) async {
        try {
          final fresh = await _repo.roomCalibration(d.ip!);
          _fold([d], {d.uuid: fresh});
        } catch (_) {
          // Unreachable or unsupported. Same verdict as a batch read: no entry,
          // which [_fold] turns into an eviction rather than a stale keep.
          _fold([d], const {});
        } finally {
          _setBusy([d.uuid], false);
        }
      }));
    } finally {
      // Belt and braces. A stuck `busy` flag is silent and permanent, and it
      // suppresses exactly the copy that warns about a destructive write.
      _setBusy(targets.map((d) => d.uuid), false);
    }
  }

  /// Toggle Trueplay on/off across all [devices] (e.g. every bonded member of a
  /// home theater, so separately-tuned fronts engage too), then re-read to
  /// confirm. Reversible; never re-bonds or re-measures.
  Future<void> setEnabled(Iterable<SonosDevice> devices, bool on) async {
    final targets = _withIp(devices);
    if (targets.isEmpty) return;
    _setBusy(targets.map((d) => d.uuid), true);
    try {
      await Future.wait(
        targets.map((d) async {
          try {
            await _repo.setRoomCalibration(d.ip!, on);
          } catch (e) {
            // Per-device best-effort (one speaker faulting never sinks the rest),
            // but record it — this path has no progress tracker, so otherwise the
            // fault would be invisible in the diagnostics bundle.
            DiagnosticsLog.add('[trueplay] set $on @ ${d.ip} failed: $e');
          }
        }),
      );
      _fold(targets, await _readAll(targets));
    } finally {
      _setBusy(targets.map((d) => d.uuid), false);
    }
  }
}
