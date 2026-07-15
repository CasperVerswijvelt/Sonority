import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:file_saver/file_saver.dart';
import 'package:share_plus/share_plus.dart';

import '../../state/sonos_controller.dart';
import '../widgets/sheet_scaffold.dart';
import 'diagnostics_bundle.dart';

const _devEmail = 'casperverswijveltdev@gmail.com';

/// Which share-bar action is in flight, so the spinner shows on the button that
/// was actually pressed (not always the primary one).
enum _Action { email, share, save }

/// Opens the diagnostics bottom sheet: a hide-nothing technical topology view
/// plus a way to package it (+ raw data, logs) into a zip and escalate it.
Future<void> showDiagnosticsSheet(BuildContext context) =>
    showAppSheet<void>(context, const _DiagnosticsSheet());

class _DiagnosticsSheet extends ConsumerStatefulWidget {
  const _DiagnosticsSheet();

  @override
  ConsumerState<_DiagnosticsSheet> createState() => _DiagnosticsSheetState();
}

class _DiagnosticsSheetState extends ConsumerState<_DiagnosticsSheet> {
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
    setState(() => _busy = which);
    try {
      final String path;
      try {
        final built = await _collect();
        if (built == null) {
          _snack('No system to collect — scan first.');
          return;
        }
        path = built;
      } catch (e) {
        _snack('Could not build the diagnostics bundle: $e');
        return;
      }
      try {
        await action(path);
      } catch (e) {
        _snack('Could not complete the action: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _save(String path) async {
    // file_saver opens a native save dialog on every platform; filePath lets it
    // copy the temp zip to the chosen location without loading it into Dart.
    final saved = await FileSaver.instance.saveAs(
      name: path.split('/').last.replaceAll('.zip', ''),
      filePath: path,
      fileExtension: 'zip',
      mimeType: MimeType.zip,
    );
    if (saved != null) _snack('Saved to $saved');
  }

  /// Spinner on the button whose action is running, else its normal icon.
  Widget _busyIcon(_Action which, IconData icon) => _busy == which
      ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Icon(icon);

  Future<void> _email(String path) => FlutterEmailSender.send(
    Email(
      subject: 'Sonority diagnostics',
      recipients: const [_devEmail],
      body:
          'Describe what went wrong (what you tried, what you expected, '
          'what happened):\n\n\n'
          '——— the diagnostics bundle is attached below ———',
      attachmentPaths: [path],
    ),
  );

  Future<void> _share(String path) {
    // iPad requires a non-null sharePositionOrigin or share_plus throws/crashes;
    // anchor the popover to the sheet. Ignored on other platforms.
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

    return SheetScaffold(
      icon: Icons.bug_report_outlined,
      title: 'Diagnostics',
      body: system == null
          ? const Center(child: Text('No system discovered yet.'))
          : Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SelectableText(
                  topologyText(system),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ),
            ),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1),
          SwitchListTile(
            value: _includeLogs,
            onChanged: _isBusy ? null : (v) => setState(() => _includeLogs = v),
            title: const Text('Include app logs'),
            subtitle: const Text(
              'SOAP faults, bond retries, discovery, errors (logs.txt)',
            ),
            dense: true,
          ),
          SwitchListTile(
            value: _includeNetwork,
            onChanged: _isBusy
                ? null
                : (v) => setState(() => _includeNetwork = v),
            title: const Text('Include phone network info'),
            subtitle: const Text(
              "This device's network interface addresses (network.txt)",
            ),
            dense: true,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Always included: topology (room names, IPs, MACs, models), raw '
              'device descriptions, and your saved profiles/room names.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (_isBusy || system == null)
                          ? null
                          : () => _run(
                              _emailSupported ? _Action.email : _Action.share,
                              _emailSupported ? _email : _share,
                            ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 52),
                      ),
                      icon: _busyIcon(
                        _emailSupported ? _Action.email : _Action.share,
                        _emailSupported ? Icons.mail_outline : Icons.share,
                      ),
                      label: Text(
                        _busy ==
                                (_emailSupported
                                    ? _Action.email
                                    : _Action.share)
                            ? 'Collecting…'
                            : _emailSupported
                            ? 'Email to developer'
                            : 'Share diagnostics',
                      ),
                    ),
                  ),
                  // The generic share sheet as a secondary action — redundant with
                  // the primary button when email isn't supported, so drop it there.
                  if (_emailSupported) ...[
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: (_isBusy || system == null)
                          ? null
                          : () => _run(_Action.share, _share),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        minimumSize: const Size(0, 52),
                      ),
                      child: _busyIcon(_Action.share, Icons.share),
                    ),
                  ],
                  // Explicit save-to-disk (native save dialog). Off on web,
                  // where the bundle build (dart:io) can't run anyway.
                  if (!kIsWeb) ...[
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: (_isBusy || system == null)
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
          ),
        ],
      ),
    );
  }
}
