import 'package:flutter/material.dart';

/// Prompts for a new room name, pre-filled with [current]. Returns the trimmed
/// new name, or null if cancelled / unchanged. Shared by the room and
/// home-theater detail pages.
Future<String?> showRenameDialog(BuildContext context, String current) async {
  final controller = TextEditingController(text: current);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Rename room'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Room name'),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save')),
      ],
    ),
  );
  if (result == null || result.isEmpty || result == current) return null;
  return result;
}
