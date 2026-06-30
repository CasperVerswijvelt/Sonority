import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/sonos/cancellation.dart';
import '../../state/sonos_controller.dart';
import 'apply_progress_view.dart';

/// How a bonding operation ended, returned by [showBondingProgress].
enum BondingOutcome { success, failed, aborted }

/// Runs a bonding operation behind the shared, non-dismissable full-screen
/// progress dialog and returns how it ended. Every bonding change (HT setup,
/// profile apply, stereo create/separate, HT-role removal) goes through here so
/// they all look and behave the same.
///
/// [run] should invoke the controller method (e.g. `() => ctrl.applyProfile(p)`);
/// the controller drives [applyProgressProvider] (timeline) and
/// [operationLogProvider] (raw log) as it works.
Future<BondingOutcome> showBondingProgress(
  BuildContext context, {
  required String title,
  required Future<void> Function() run,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  container.read(applyProgressProvider.notifier).clear();
  container.read(operationLogProvider.notifier).clear();
  final outcome = await Navigator.of(context).push<BondingOutcome>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => BondingProgressScreen(title: title, run: run),
    ),
  );
  return outcome ?? BondingOutcome.aborted;
}

class BondingProgressScreen extends ConsumerStatefulWidget {
  final String title;
  final Future<void> Function() run;

  const BondingProgressScreen({
    super.key,
    required this.title,
    required this.run,
  });

  @override
  ConsumerState<BondingProgressScreen> createState() =>
      _BondingProgressScreenState();
}

class _BondingProgressScreenState extends ConsumerState<BondingProgressScreen> {
  bool _finished = false;
  bool _failed = false;
  bool _aborting = false;
  bool _showLogs = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    setState(() {
      _finished = false;
      _failed = false;
      _aborting = false;
    });
    final navigator = Navigator.of(context);
    try {
      await widget.run();
      if (mounted) setState(() => _finished = true);
    } on OperationCancelled {
      // User abort — the controller already restored a usable state.
      if (mounted) navigator.pop(BondingOutcome.aborted);
    } catch (_) {
      // The failing step + the raw log carry the reason; show Retry/Done.
      if (mounted) setState(() => _finished = _failed = true);
    }
  }

  Future<void> _confirmAbort() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber),
        title: const Text('Abort?'),
        content: const Text(
            'Stopping now can leave your speakers in an in-between state — some '
            'changes may be half-applied. You can re-apply afterwards to fix it.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep going')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Abort'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() => _aborting = true);
      ref.read(sonosControllerProvider.notifier).cancelActiveOperation();
    }
  }

  void _retry() {
    ref.read(applyProgressProvider.notifier).clear();
    ref.read(operationLogProvider.notifier).clear();
    _run();
  }

  Future<void> _copyLogs() async {
    final log = ref.read(operationLogProvider).join('\n');
    await Clipboard.setData(ClipboardData(text: log));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logs copied to clipboard.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = ref.watch(applyProgressProvider);
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(widget.title),
          actions: [
            IconButton(
              tooltip: 'Copy logs',
              onPressed: _copyLogs,
              icon: const Icon(Icons.copy_all),
            ),
            IconButton(
              tooltip: _showLogs ? 'Show steps' : 'Show raw log',
              onPressed: () => setState(() => _showLogs = !_showLogs),
              icon: Icon(_showLogs
                  ? Icons.view_timeline_outlined
                  : Icons.terminal),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: _showLogs
                    ? const _RawLogView()
                    : ApplyProgressView(steps: steps),
              ),
              _BottomBar(
                finished: _finished,
                failed: _failed,
                aborting: _aborting,
                onAbort: _confirmAbort,
                onRetry: _retry,
                onDone: () => Navigator.of(context).pop(
                    _failed ? BondingOutcome.failed : BondingOutcome.success),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The accumulating raw log, monospace + selectable, auto-scrolled to newest.
class _RawLogView extends ConsumerStatefulWidget {
  const _RawLogView();

  @override
  ConsumerState<_RawLogView> createState() => _RawLogViewState();
}

class _RawLogViewState extends ConsumerState<_RawLogView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(operationLogProvider);
    final theme = Theme.of(context);
    // Keep the newest line in view as the log grows.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
    if (lines.isEmpty) {
      return Center(
        child: Text('No log output yet.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      );
    }
    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: SelectableText(
          lines.join('\n'),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final bool finished;
  final bool failed;
  final bool aborting;
  final VoidCallback onAbort;
  final VoidCallback onRetry;
  final VoidCallback onDone;

  const _BottomBar({
    required this.finished,
    required this.failed,
    required this.aborting,
    required this.onAbort,
    required this.onRetry,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget child;
    if (!finished) {
      child = OutlinedButton.icon(
        onPressed: aborting ? null : onAbort,
        icon: const Icon(Icons.stop_circle_outlined),
        label: Text(aborting ? 'Aborting…' : 'Abort'),
        style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
      );
    } else if (failed) {
      child = Row(
        children: [
          Expanded(
            child: OutlinedButton(onPressed: onDone, child: const Text('Done')),
          ),
          Gap.s,
          Expanded(
            child: FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ),
        ],
      );
    } else {
      child = FilledButton(onPressed: onDone, child: const Text('Done'));
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(width: double.infinity, child: child),
    );
  }
}
