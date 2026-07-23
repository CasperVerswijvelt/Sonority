import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// A settings block: a full-width divider then flat, full-width, square rows —
/// visually distinct from the rounded content cards above it (settings read as
/// settings, not as more content). Its [children] are flat tiles/rows that own
/// their internal padding (e.g. a `ListTile`). Shared by the room / home-theater
/// Trueplay control and the profile-entity saved settings; the diagnostics sheet
/// footer uses the same divider-then-flat-tiles shape.
///
/// A [ListTileTheme] squares any child tile's hover/tap ink ([kFlatTileShape]),
/// overriding the rounded `listTileTheme` default that's meant for card-nested
/// tiles — so rows read as full-bleed, not as rounded cards, with no per-row code.
class SettingsSection extends StatelessWidget {
  final List<Widget> children;
  const SettingsSection({super.key, required this.children});

  @override
  Widget build(BuildContext context) => ListTileTheme(
        data: const ListTileThemeData(shape: kFlatTileShape),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [const Divider(height: 1), ...children],
        ),
      );
}
