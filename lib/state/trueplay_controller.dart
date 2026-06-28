import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/sonos_models.dart';
import '../data/sonos/room_calibration.dart';
import '../data/sonos/sonos_repository.dart';
import 'sonos_controller.dart' show sonosRepositoryProvider;

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
  }) =>
      TrueplayState(byUuid: byUuid ?? this.byUuid, busy: busy ?? this.busy);
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

  Future<Map<String, RoomCalibration>> _readAll(List<SonosDevice> targets) async {
    final results = <String, RoomCalibration>{};
    await Future.wait(targets.map((d) async {
      try {
        results[d.uuid] = await _repo.roomCalibration(d.ip!);
      } catch (_) {
        // unreachable / unsupported speaker — leave it out of the map
      }
    }));
    return results;
  }

  /// Fetch (or refresh) calibration status for a set of speakers.
  Future<void> load(Iterable<SonosDevice> devices) async {
    final targets = _withIp(devices);
    if (targets.isEmpty) return;
    _setBusy(targets.map((d) => d.uuid), true);
    final results = await _readAll(targets);
    state = state.copyWith(byUuid: {...state.byUuid, ...results});
    _setBusy(targets.map((d) => d.uuid), false);
  }

  /// Toggle Trueplay on/off across all [devices] (e.g. every bonded member of a
  /// home theater, so separately-tuned fronts engage too), then re-read to
  /// confirm. Reversible; never re-bonds or re-measures.
  Future<void> setEnabled(Iterable<SonosDevice> devices, bool on) async {
    final targets = _withIp(devices);
    if (targets.isEmpty) return;
    _setBusy(targets.map((d) => d.uuid), true);
    try {
      await Future.wait(targets.map((d) async {
        try {
          await _repo.setRoomCalibration(d.ip!, on);
        } catch (_) {}
      }));
      final results = await _readAll(targets);
      state = state.copyWith(byUuid: {...state.byUuid, ...results});
    } finally {
      _setBusy(targets.map((d) => d.uuid), false);
    }
  }
}
