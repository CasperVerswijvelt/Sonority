import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../state/sonos_controller.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/busy_view.dart';
import '../widgets/identify_controls.dart';
import '../widgets/member_channel_card.dart';

/// A standalone (unbonded) Sub shown as a pushed page: identify it, plus a note
/// on how to put it to use (a standalone sub has no config of its own). A page,
/// not a sheet, so the rule stays uniform — anything you can act on (here,
/// identify) is a page — and its failure toast renders on the root messenger
/// instead of behind a modal.
class SubScreen extends ConsumerWidget {
  final String uuid;
  const SubScreen({super.key, required this.uuid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(sonosControllerProvider).value?.device(uuid);
    if (sub == null) {
      return AppScaffold(
        title: context.l10n.discoverySubwoofer,
        body: const Padding(
            padding: EdgeInsets.all(24), child: MissingRoomView()),
      );
    }
    return AppScaffold(
      title: context.l10n.discoverySubwoofer,
      subtitle: sub.typeLabel,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(kPageGutter, 8, kPageGutter, 16),
        children: [
          MemberChannelCard(
            icon: Icons.graphic_eq,
            type: sub.typeLabel,
            trailing: speakerIdentifyButton(sub),
          ),
          Gap.m,
          Text(
            context.l10n.discoverySubUnbondedNote,
            style: Theme.of(context).mutedText,
          ),
        ],
      ),
    );
  }
}
