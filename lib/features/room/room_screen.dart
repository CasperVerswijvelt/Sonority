import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/models/sonos_models.dart';
import '../../state/sonos_controller.dart';
import '../../state/trueplay_controller.dart';
import '../widgets/busy_view.dart';
import '../widgets/refresh_icon_button.dart';
import '../widgets/trueplay_control.dart';

/// Detail page for a standalone room or a stereo pair. Currently hosts the
/// Trueplay control (kept off the main list to avoid clutter).
class RoomScreen extends ConsumerWidget {
  final String uuid;
  const RoomScreen({super.key, required this.uuid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final system = ref.watch(sonosControllerProvider).value;
    final member = system?.allMembers
        .where((m) => m.uuid == uuid)
        .cast<ZoneGroupMember?>()
        .firstOrNull;

    // A stereo pair acts on both speakers; a standalone room on just itself.
    final devices = <SonosDevice>[
      if (system != null && member != null)
        if (member.isStereoPair)
          ...member.stereoPairUuids
              .map(system.device)
              .whereType<SonosDevice>()
        else if (system.device(uuid) != null)
          system.device(uuid)!,
    ];
    final models =
        devices.map((d) => d.modelName).toSet().join(' + ');

    return Scaffold(
      appBar: AppBar(
        title: Text(member?.zoneName ?? 'Room'),
        actions: [
          RefreshIconButton(onRefresh: () async {
            await ref.read(sonosControllerProvider.notifier).refresh();
            if (devices.isNotEmpty) {
              await ref.read(trueplayControllerProvider.notifier).load(devices);
            }
          }),
        ],
      ),
      body: SafeArea(
        child: member == null
            ? const MissingRoomView()
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(models.isEmpty ? 'Speaker' : models,
                      style: Theme.of(context).textTheme.titleMedium),
                  Gap.l,
                  TrueplayControl(devices: devices),
                ],
              ),
      ),
    );
  }

}
