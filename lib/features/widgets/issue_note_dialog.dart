import 'package:flutter/material.dart';

import '../../core/l10n.dart';

/// Minimum length of the reporter's problem description. A diagnostics bundle
/// with no explanation costs a round-trip before triage can start, so the email
/// escalation won't build one until there's at least a sentence.
const kMinIssueNoteLength = 20;

/// Prompts for a description of the problem before a diagnostics bundle is
/// emailed. Returns the trimmed text, or null if cancelled — the caller then
/// builds nothing. Continue stays disabled until the text passes
/// [kMinIssueNoteLength].
Future<String?> showIssueNoteDialog(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    // StatefulBuilder so Continue enables live on the threshold without a
    // widget class of its own.
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final text = controller.text.trim();
        return AlertDialog(
          title: Text(ctx.l10n.diagNoteTitle),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            // Guidance as a wrapping hint, not a floating label: the label
            // clips to one line at dialog width, and the box is 3 lines tall
            // anyway. Helper stays short so it fits beside the counter.
            decoration: InputDecoration(
              hintText: ctx.l10n.diagNoteHint,
              hintMaxLines: 3,
              helperText: ctx.l10n.diagNoteHelper(kMinIssueNoteLength),
              counterText: '${text.length}/$kMinIssueNoteLength',
            ),
            onChanged: (_) => setState(() {}),
          ),
          // Both TextButton: the theme stretches a FilledButton full width,
          // which would stack the actions (see confirm_dialog.dart).
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.l10n.actionCancel),
            ),
            TextButton(
              onPressed: text.length >= kMinIssueNoteLength
                  ? () => Navigator.pop(ctx, text)
                  : null,
              child: Text(ctx.l10n.actionContinue),
            ),
          ],
        );
      },
    ),
  );
}
