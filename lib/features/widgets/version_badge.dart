import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'sheet_scaffold.dart';

const _repoUrl = 'https://github.com/CasperVerswijvelt/Sonority';

/// Muted `v<version>` label for an app-bar `actions:` slot. Reads the built
/// package version at runtime so it tracks pubspec automatically. Tapping it
/// opens a bottom sheet with the changelog and a GitHub link.
class VersionBadge extends StatelessWidget {
  const VersionBadge({super.key});

  static final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: _info,
      builder: (context, snap) {
        final info = snap.data;
        if (info == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Center(
            child: _VersionPill(
              'v${info.version}',
              onTap: () => showVersionSheet(context, info),
            ),
          ),
        );
      },
    );
  }
}

/// The muted rounded pill, shared by the app-bar badge and the changelog
/// sheet's header (where it shows the full `v<version>-<build>` label).
class _VersionPill extends StatelessWidget {
  const _VersionPill(this.text, {this.onTap});
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.onSurface.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            text,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Changelog sheet opened by tapping the [VersionBadge]. Uses the same
/// modal-sheet chrome (drag handle + scroll-under divider) as the diagnostics
/// sheet via [SheetScaffold].
Future<void> showVersionSheet(BuildContext context, PackageInfo info) {
  return showAppSheet<void>(
    context,
    SheetScaffold(
      title: 'Changelog',
      trailing: _VersionPill(fullVersionLabel(info)),
      body: FutureBuilder<String>(
        future: rootBundle.loadString('CHANGELOG.md'),
        builder: (ctx, snap) {
          final md = snap.data;
          if (md == null) return const SizedBox.shrink();
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _ChangelogView(parseChangelog(md)),
          );
        },
      ),
      footer: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: () => launchUrl(
                Uri.parse(_repoUrl),
                mode: LaunchMode.externalApplication,
              ),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              icon: const Icon(Icons.open_in_new),
              label: const Text('GitHub'),
            ),
          ),
        ),
      ),
    ),
  );
}

/// `v0.5.0-8` — version plus the rebuild counter, decoded from the build
/// number per docs/PUBLISHING.md (`N = major*1000000 + minor*10000 +
/// patch*100 + build`). Falls back to the raw build number if N doesn't fit
/// that scheme.
String fullVersionLabel(PackageInfo info) {
  final parts = info.version.split('.').map(int.tryParse).toList();
  final n = int.tryParse(info.buildNumber);
  if (parts.length == 3 && !parts.contains(null) && n != null) {
    final build =
        n - (parts[0]! * 1000000 + parts[1]! * 10000 + parts[2]! * 100);
    if (build >= 0 && build < 100) return 'v${info.version}-$build';
  }
  return 'v${info.version} (${info.buildNumber})';
}

enum ChangelogKind { release, section, bullet }

class ChangelogEntry {
  ChangelogEntry(this.kind, this.text);
  final ChangelogKind kind;
  String text;
}

/// Line-based parser for this repo's Keep-a-Changelog format: `## [x.y.z] - date`
/// releases, `### Added/Changed/…` sections and `-` bullets (with wrapped
/// continuation lines joined). The file preamble, `**` emphasis, and headers
/// with no bullets under them (e.g. an empty `[Unreleased]`) are dropped.
/// ponytail: covers exactly the shapes CHANGELOG.md uses; grow it (or swap in a
/// markdown package) only if the file's format grows.
List<ChangelogEntry> parseChangelog(String markdown) {
  final entries = <ChangelogEntry>[];
  for (final raw in markdown.split('\n')) {
    final line = raw.trimRight();
    if (line.startsWith('## ')) {
      final m = RegExp(r'^## \[(.+?)\](?:\s*-\s*(.+))?$').firstMatch(line);
      final text = m == null
          ? line.substring(3)
          : (m[2] == null ? m[1]! : '${m[1]} — ${m[2]}');
      entries.add(ChangelogEntry(ChangelogKind.release, text));
    } else if (entries.isEmpty) {
      // Preamble before the first release header.
    } else if (line.startsWith('### ')) {
      entries.add(ChangelogEntry(ChangelogKind.section, line.substring(4)));
    } else if (line.startsWith('- ')) {
      entries.add(ChangelogEntry(ChangelogKind.bullet, line.substring(2)));
    } else if (line.startsWith('  ') &&
        entries.last.kind == ChangelogKind.bullet) {
      entries.last.text += ' ${line.trim()}';
    }
  }
  for (final e in entries) {
    e.text = e.text.replaceAll('**', '');
  }
  // Walk bottom-up so each header knows whether any bullets sit under it.
  final kept = <ChangelogEntry>[];
  var bulletsInSection = false;
  var bulletsInRelease = false;
  for (final e in entries.reversed) {
    switch (e.kind) {
      case ChangelogKind.bullet:
        bulletsInSection = bulletsInRelease = true;
        kept.add(e);
      case ChangelogKind.section:
        if (bulletsInSection) kept.add(e);
        bulletsInSection = false;
      case ChangelogKind.release:
        if (bulletsInRelease) kept.add(e);
        bulletsInSection = bulletsInRelease = false;
    }
  }
  return kept.reversed.toList();
}

class _ChangelogView extends StatelessWidget {
  const _ChangelogView(this.entries);
  final List<ChangelogEntry> entries;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in entries)
          switch (e.kind) {
            ChangelogKind.release => Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 2),
                child: Text(e.text, style: text.titleMedium),
              ),
            ChangelogKind.section => Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(e.text, style: text.labelLarge),
              ),
            ChangelogKind.bullet => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: Text(e.text, style: text.bodySmall)),
                  ],
                ),
              ),
          },
      ],
    );
  }
}
