import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/sonos/cancellation.dart';
import '../../state/sonos_controller.dart';
import 'app_scaffold.dart';
import 'apply_progress_view.dart';
import 'max_width_body.dart';

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
  // Push on the ROOT navigator so the dialog covers the bottom nav bar too —
  // bonding must fully block navigation while it runs.
  final outcome = await Navigator.of(context, rootNavigator: true)
      .push<BondingOutcome>(
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
  // _aborting: the Abort button was pressed (drives its "Aborting…" label and
  // the cancel). _aborted: the op actually ended via cancellation — only this
  // drives the outcome/header, so a late abort that the op outran still reports
  // its true success/failure.
  bool _aborting = false;
  bool _aborted = false;
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
      _aborted = false;
    });
    final navigator = Navigator.of(context);
    try {
      await widget.run();
      if (mounted) setState(() => _finished = true);
    } on OperationCancelled {
      // Abort button → surface like a failure (the step reads 'Aborted', Retry
      // re-runs). A pre-flight confirm decline (no Abort pressed) just closes.
      if (!_aborting) {
        if (mounted) navigator.pop(BondingOutcome.aborted);
      } else if (mounted) {
        setState(() => _finished = _failed = _aborted = true);
      }
    } catch (_) {
      // The failing step + the raw log carry the reason; show Retry/Done.
      if (mounted) setState(() => _finished = _failed = true);
    }
  }

  // No confirm dialog — abort should stop as fast as possible. The aborted step
  // is marked in the timeline and re-applying afterwards fixes any half-state.
  void _abort() {
    setState(() => _aborting = true);
    ref.read(sonosControllerProvider.notifier).cancelActiveOperation();
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
        const SnackBar(content: Text('Logs copied to clipboard.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = ref.watch(applyProgressProvider);
    return PopScope(
      canPop: false,
      child: Scaffold(
        // Fixed app bar, matching the rest of the app's pages.
        appBar: AppBar(
          automaticallyImplyLeading: false,
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: ScrolledUnderDivider(),
          ),
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
              icon: Icon(
                _showLogs ? Icons.view_timeline_outlined : Icons.terminal,
              ),
            ),
          ],
        ),
        body: MaxWidthBody(
          child: _showLogs
              ? const _RawLogView()
              : ApplyProgressView(steps: steps, aborted: _aborted),
        ),
        bottomNavigationBar: SafeArea(
          child: _BottomBar(
            finished: _finished,
            failed: _failed,
            aborting: _aborting,
            onAbort: _abort,
            onRetry: _retry,
            onDone: () => Navigator.of(context).pop(
              _aborted
                  ? BondingOutcome.aborted
                  : _failed
                  ? BondingOutcome.failed
                  : BondingOutcome.success,
            ),
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
      return Center(child: Text('No log output yet.', style: theme.mutedText));
    }
    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: SelectableText(
          lines.join('\n'),
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.5,
          ),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final Widget child;
    if (!finished) {
      // Same shape as the Done button, but red.
      child = FilledButton(
        onPressed: aborting ? null : onAbort,
        style: FilledButton.styleFrom(
          backgroundColor: scheme.error,
          foregroundColor: scheme.onError,
        ),
        child: Text(aborting ? 'Aborting…' : 'Abort'),
      );
    } else {
      // Color Done by result: green on success, red/error on failure (or abort).
      // Green is shared with the timeline's success nodes (successGreen).
      final doneColor = failed ? scheme.error : successGreen(theme);
      child = Row(
        children: [
          Expanded(
            child: FilledButton(
              onPressed: onDone,
              style: FilledButton.styleFrom(
                backgroundColor: doneColor,
                foregroundColor: failed
                    ? scheme.onError
                    : onSuccessGreen(theme),
              ),
              child: const Text('Done'),
            ),
          ),
          if (failed) ...[
            Gap.s,
            Expanded(
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ),
          ],
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Reassure on failure/abort: our writes are diff-based and
          // idempotent, so a partial run leaves a safe state that re-applying
          // (Retry) converges — nothing is stuck half-bonded.
          if (finished && failed) ...[
            Text(
              'Your speakers are in a safe state — nothing was left '
              'half-applied. Fix the issue and retry.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            Gap.s,
          ],
          SizedBox(width: double.infinity, child: child),
        ],
      ),
    );
  }
}
