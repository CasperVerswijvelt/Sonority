import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../state/sonos_controller.dart';
import '../widgets/apply_progress_view.dart';
import 'profile.dart';

/// Runs [SonosController.applyProfile] and shows the live per-step progress.
/// Auto-pops on success; on failure it stays so the user sees which entity
/// failed and why, with Retry/Close.
class ProfileApplyScreen extends ConsumerStatefulWidget {
  final Profile profile;
  final Set<String> skip;
  const ProfileApplyScreen({super.key, required this.profile, this.skip = const {}});

  @override
  ConsumerState<ProfileApplyScreen> createState() => _ProfileApplyScreenState();
}

class _ProfileApplyScreenState extends ConsumerState<ProfileApplyScreen> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    setState(() => _failed = false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(sonosControllerProvider.notifier)
          .applyProfile(widget.profile, skip: widget.skip);
      messenger.showSnackBar(
          SnackBar(content: Text('Applied “${widget.profile.name}”.')));
      navigator.pop(true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = ref.watch(applyProgressProvider);
    return PopScope(
      canPop: _failed,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Applying ${widget.profile.name}'),
          automaticallyImplyLeading: _failed,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ApplyProgressView(
                    steps: steps, title: 'Applying “${widget.profile.name}”…'),
              ),
              if (_failed)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Close'),
                        ),
                      ),
                      Gap.s,
                      Expanded(
                        child: FilledButton(
                          onPressed: _run,
                          child: const Text('Retry'),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
