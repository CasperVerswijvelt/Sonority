import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:file_saver/file_saver.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n.dart';
import '../../state/localized_error.dart';
import '../../state/sonos_controller.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/busy_spinner.dart';
import 'diagnostics_bundle.dart';

const _devEmail = 'casperverswijveltdev@gmail.com';

/// Which share-bar action is in flight, so the spinner shows on the button that
/// was actually pressed (not always the primary one).
enum _Action { email, share, save }

/// The Diagnostics tab: a hide-nothing technical topology view plus a way to
/// package it (+ raw data, logs) into a zip and escalate it. A bottom-bar
/// destination (see `app.dart`), so it's a full page — not a modal.
class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  bool _includeLogs = true;
  bool _includeNetwork = true;
  _Action? _busy; // null = idle; else the action currently running

  bool get _isBusy => _busy != null;

  Future<String?> _collect() async {
    final system = ref.read(sonosControllerProvider).value;
    if (system == null) return null;
    final pkg = await PackageInfo.fromPlatform();
    return buildDiagnosticsZip(
      system: system,
      repo: ref.read(sonosRepositoryProvider),
      package: pkg,
      now: DateTime.now(),
      options: DiagnosticsOptions(
        includeLogs: _includeLogs,
        includeNetwork: _includeNetwork,
      ),
    );
  }

  // flutter_email_sender supports iOS, Android and macOS (recipient + plaintext
  // body + attachment — the only fields we set; it drops cc/bcc/HTML on macOS,
  // which we don't use). Web uses mailto with no attachment, so exclude it and
  // fall back to Share there.
  bool get _emailSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> _run(
    _Action which,
    Future<void> Function(String path) action,
  ) async {
    final l10n = context.l10n;
    setState(() => _busy = which);
    try {
      final String path;
      try {
        final built = await _collect();
        if (built == null) {
          _snack(l10n.diagNoSystemToCollect);
          return;
        }
        path = built;
      } catch (e) {
        _snack(l10n.diagBuildFailed(localizedError(l10n, e)));
        return;
      }
      try {
        await action(path);
      } catch (e) {
        _snack(l10n.diagActionFailed(localizedError(l10n, e)));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _save(String path) async {
    final l10n = context.l10n;
    // file_saver opens a native save dialog on every platform; filePath lets it
    // copy the temp zip to the chosen location without loading it into Dart.
    final saved = await FileSaver.instance.saveAs(
      name: path.split('/').last.replaceAll('.zip', ''),
      filePath: path,
      fileExtension: 'zip',
      mimeType: MimeType.zip,
    );
    if (saved != null) _snack(l10n.diagSavedTo(saved));
  }

  /// Spinner on the button whose action is running, else its normal icon.
  Widget _busyIcon(_Action which, IconData icon) =>
      _busy == which ? const BusySpinner() : Icon(icon);

  Future<void> _email(String path) => FlutterEmailSender.send(
    Email(
      subject: 'Sonority diagnostics',
      recipients: const [_devEmail],
      body: context.l10n.diagEmailBody,
      attachmentPaths: [path],
    ),
  );

  Future<void> _share(String path) {
    // iPad requires a non-null sharePositionOrigin or share_plus throws/crashes;
    // anchor the popover to this widget. Ignored on other platforms.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    return SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        subject: 'Sonority diagnostics',
        sharePositionOrigin: origin,
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final system = ref.watch(sonosControllerProvider).value;
    final hasSystem = system != null;

    return AppScaffold(
      title: context.l10n.diagTitle,
      body: Column(
        children: [
          Expanded(
            child: system == null
                ? Center(child: Text(context.l10n.diagNoSystem))
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: SelectableText(
                        topologyText(system),
                        selectionWidthStyle: ui.BoxWidthStyle.tight,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
          ),
          // Bundle-content toggles + note + escalation actions, pinned below the
          // scrolling topology.
          const Divider(height: 1),
          SwitchListTile(
            value: _includeLogs,
            onChanged: _isBusy ? null : (v) => setState(() => _includeLogs = v),
            title: Text(context.l10n.diagIncludeLogs),
            subtitle: Text(context.l10n.diagIncludeLogsSubtitle),
            dense: true,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          ),
          SwitchListTile(
            value: _includeNetwork,
            onChanged:
                _isBusy ? null : (v) => setState(() => _includeNetwork = v),
            title: Text(context.l10n.diagIncludeNetwork),
            subtitle: Text(context.l10n.diagIncludeNetworkSubtitle),
            dense: true,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              context.l10n.diagAlwaysIncluded,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_isBusy || !hasSystem)
                        ? null
                        : () => _run(
                            _emailSupported ? _Action.email : _Action.share,
                            _emailSupported ? _email : _share,
                          ),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                    icon: _busyIcon(
                      _emailSupported ? _Action.email : _Action.share,
                      _emailSupported ? Icons.mail_outline : Icons.share,
                    ),
                    label: Text(
                      _busy ==
                              (_emailSupported ? _Action.email : _Action.share)
                          ? context.l10n.diagCollecting
                          : _emailSupported
                              ? context.l10n.diagEmailToDeveloper
                              : context.l10n.diagShareDiagnostics,
                    ),
                  ),
                ),
                // The generic share sheet as a secondary action — redundant with
                // the primary button when email isn't supported, so drop it there.
                if (_emailSupported) ...[
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: (_isBusy || !hasSystem)
                        ? null
                        : () => _run(_Action.share, _share),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      minimumSize: const Size(0, 52),
                    ),
                    child: _busyIcon(_Action.share, Icons.share),
                  ),
                ],
                // Explicit save-to-disk (native save dialog). Off on web, where
                // the bundle build (dart:io) can't run anyway.
                if (!kIsWeb) ...[
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: (_isBusy || !hasSystem)
                        ? null
                        : () => _run(_Action.save, _save),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      minimumSize: const Size(0, 52),
                    ),
                    child: _busyIcon(_Action.save, Icons.save_alt),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
