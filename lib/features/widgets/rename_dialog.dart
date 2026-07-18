import 'package:flutter/material.dart';

import '../../core/l10n.dart';

/// Prompts for a new room name, pre-filled with [current]. Returns the trimmed
/// new name, or null if cancelled / unchanged. Shared by the room and
/// home-theater detail pages.
Future<String?> showRenameDialog(BuildContext context, String current) async {
  final controller = TextEditingController(text: current);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.l10n.widgetsRenameRoomTitle),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: ctx.l10n.widgetsRoomNameLabel),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.l10n.actionCancel)),
        TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(ctx.l10n.actionSave)),
      ],
    ),
  );
  if (result == null || result.isEmpty || result == current) return null;
  return result;
}
