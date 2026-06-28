import 'package:flutter/material.dart';

/// An app-bar refresh button that shows a spinner while its async [onRefresh]
/// runs, so detail pages give clear feedback (the topology refresh otherwise
/// completes silently).
class RefreshIconButton extends StatefulWidget {
  final Future<void> Function() onRefresh;
  const RefreshIconButton({super.key, required this.onRefresh});

  @override
  State<RefreshIconButton> createState() => _RefreshIconButtonState();
}

class _RefreshIconButtonState extends State<RefreshIconButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(
            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return IconButton(
      tooltip: 'Refresh',
      onPressed: _run,
      icon: const Icon(Icons.refresh),
    );
  }
}
