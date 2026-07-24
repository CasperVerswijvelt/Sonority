import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../state/sonos_controller.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/busy_view.dart';
import '../widgets/identify_controls.dart';
import '../widgets/member_channel_card.dart';
import '../widgets/scroll_footer.dart';
import 'bonding_shortcuts.dart';

/// A standalone (unbonded) Sub shown as a pushed page: identify it, a note that
/// it has no config of its own, and shortcuts into the bonding flows so it isn't
/// a dead end (a Sub is most useful bonded into a home theater or a group). A
/// page, not a sheet, so the rule stays uniform — anything you can act on is a
/// page — and its failure toast renders on the root messenger, not behind a modal.
class SubScreen extends ConsumerWidget {
  final String uuid;
  const SubScreen({super.key, required this.uuid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final system = ref.watch(sonosControllerProvider).value;
    final sub = system?.device(uuid);
    if (sub == null) {
      return AppScaffold(
        title: context.l10n.discoverySubwoofer,
        body: const Padding(
            padding: EdgeInsets.all(24), child: MissingRoomView()),
      );
    }
    final sys = system!;
    final soundbars = homeTheaterTargets(sys);
    return AppScaffold(
      title: context.l10n.discoverySubwoofer,
      subtitle: sub.typeLabel,
      // The sub + note sit at the top; the shortcuts float to the bottom via
      // ScrollFooter, matching the room page.
      body: ScrollFooter(
        padding: const EdgeInsets.symmetric(vertical: 8),
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canGroupSub(sys))
              ActionRow(
                icon: Icons.speaker_group_outlined,
                title: context.l10n.subAddToGroup,
                subtitle: context.l10n.subAddToGroupSubtitle,
                onTap: () => leaveTo(context, '/group?sub=$uuid'),
              ),
            if (soundbars.isNotEmpty)
              ActionRow(
                icon: Icons.surround_sound,
                title: context.l10n.roomAddToHomeTheater,
                subtitle: context.l10n.roomAddToHomeTheaterSubtitle,
                onTap: () => addToHomeTheater(context, soundbars, sub: uuid),
              ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
            child: MemberChannelCard(
              icon: Icons.graphic_eq,
              type: sub.typeLabel,
              trailing: speakerIdentifyButton(sub),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(kPageGutter, 12, kPageGutter, 0),
            child: Text(
              context.l10n.discoverySubUnbondedNote,
              style: Theme.of(context).mutedText,
            ),
          ),
        ],
      ),
    );
  }
}
