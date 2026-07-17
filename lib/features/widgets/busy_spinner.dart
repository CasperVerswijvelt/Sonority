import 'package:flutter/material.dart';

/// A small inline progress indicator sized for buttons / icons — the shared form
/// of the `SizedBox(…, CircularProgressIndicator(strokeWidth: 2))` idiom that was
/// copy-pasted across the button/icon busy states.
class BusySpinner extends StatelessWidget {
  final double size;
  const BusySpinner({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
}
