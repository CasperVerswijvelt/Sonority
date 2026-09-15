import 'package:flutter/material.dart';

import '../../core/l10n.dart';

/// Minimum length of the reporter's problem description. A diagnostics bundle
/// with no explanation costs a round-trip before triage can start, so the email
/// escalation won't build one until there's at least a sentence.
const kMinIssueNoteLength = 20;

/// Prompts for a description of the problem before a diagnostics bundle is
/// emailed. Returns the trimmed text, or null if cancelled — the caller then
/// builds nothing. Continue stays disabled until the text passes
/// [kMinIssueNoteLength]. [initial] pre-fills the field so a mail composer that
/// never opened (no mail app configured) doesn't cost the reporter their typed
/// text.
Future<String?> showIssueNoteDialog(BuildContext context, {String? initial}) =>
    showDialog<String>(
      context: context,
      // The only dialog in the app that blocks a scrim tap: everywhere else a
      // dismiss costs nothing, here it silently discards several typed
      // sentences. Back still cancels, which reads as deliberate.
      barrierDismissible: false,
      builder: (ctx) => _IssueNoteDialog(initial: initial),
    );

/// A widget class rather than a `StatefulBuilder` only so the controller has a
/// [State.dispose] to live in; the dialog itself just needs setState to enable
/// Continue live on the threshold.
class _IssueNoteDialog extends StatefulWidget {
  const _IssueNoteDialog({this.initial});

  final String? initial;

  @override
  State<_IssueNoteDialog> createState() => _IssueNoteDialogState();
}

class _IssueNoteDialogState extends State<_IssueNoteDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _controller.text.trim();
    return AlertDialog(
      // A 3-line field + helper + actions can outgrow the dialog at a large
      // text scale with the keyboard up.
      scrollable: true,
      title: Text(context.l10n.diagNoteTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        // Guidance as a wrapping hint, not a floating label: the label
        // clips to one line at dialog width, and the box is 3 lines tall
        // anyway. Helper stays short so it fits beside the counter.
        decoration: InputDecoration(
          hintText: context.l10n.diagNoteHint,
          hintMaxLines: 3,
          helperText: context.l10n.diagNoteHelper(kMinIssueNoteLength),
          // Counter only while short: Material's "n/max" shape reads as an
          // exceeded limit once past a MINimum ("200/20").
          counterText: text.length >= kMinIssueNoteLength
              ? ''
              : '${text.length}/$kMinIssueNoteLength',
        ),
        onChanged: (_) => setState(() {}),
      ),
      // Both TextButton: the theme stretches a FilledButton full width,
      // which would stack the actions (see confirm_dialog.dart).
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.actionCancel),
        ),
        TextButton(
          onPressed: text.length >= kMinIssueNoteLength
              ? () => Navigator.pop(context, text)
              : null,
          child: Text(context.l10n.actionContinue),
        ),
      ],
    );
  }
}
