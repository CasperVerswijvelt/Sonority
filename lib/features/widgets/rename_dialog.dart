import 'package:flutter/material.dart';

import '../../core/l10n.dart';

/// Prompts for a new room name, pre-filled with [current]. Returns the trimmed
/// new name, or null if cancelled / unchanged. Shared by the room and
/// home-theater detail pages.
Future<String?> showRenameDialog(BuildContext context, String current) async {
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => _RenameDialog(current: current),
  );
  if (result == null || result.isEmpty || result == current) return null;
  return result;
}

/// A widget class only so the controller has a [State.dispose] to live in —
/// disposing it after `showDialog` returns would kill it mid exit-animation,
/// while the field is still on screen.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.current});

  final String current;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.widgetsRenameRoomTitle),
    content: TextField(
      controller: _controller,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(labelText: context.l10n.widgetsRoomNameLabel),
      onSubmitted: (v) => Navigator.pop(context, v.trim()),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.actionCancel),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: Text(context.l10n.actionSave),
      ),
    ],
  );
}
