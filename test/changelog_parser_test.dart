import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sonority/features/widgets/version_badge.dart';

const _sample = '''
# Changelog

All notable changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

## [0.5.0] - 2026-07-06

### Added
- **Dual Subs** — a home theater can now bond **two Subs**, with both shown
  in the layout diagram and re-applied from a profile.
- Room renaming.

### Changed
- Discovery auto-scans on launch.

## [0.4.0] - 2026-06-28

### Notes
- Sonos invalidates Trueplay when the bonded set changes.
''';

void main() {
  test('parses releases, sections and wrapped bullets; drops preamble and '
      'empty sections', () {
    final entries = parseChangelog(_sample);
    final rendered =
        entries.map((e) => '${e.kind.name}: ${e.text}').toList();
    expect(rendered, [
      'release: 0.5.0 — 2026-07-06',
      'section: Added',
      'bullet: Dual Subs — a home theater can now bond two Subs, with both '
          'shown in the layout diagram and re-applied from a profile.',
      'bullet: Room renaming.',
      'section: Changed',
      'bullet: Discovery auto-scans on launch.',
      'release: 0.4.0 — 2026-06-28',
      'section: Notes',
      'bullet: Sonos invalidates Trueplay when the bonded set changes.',
    ]);
  });

  test('parses the real CHANGELOG format markers', () {
    final entries = parseChangelog('## [Unreleased]\n\n### Added\n- One.\n');
    expect(entries.first.text, 'Unreleased');
    expect(entries.last.text, 'One.');
  });

  test('fullVersionLabel decodes the rebuild counter, falls back on raw', () {
    PackageInfo info(String v, String b) => PackageInfo(
        appName: '', packageName: '', version: v, buildNumber: b);
    expect(fullVersionLabel(info('0.5.0', '50008')), 'v0.5.0-8');
    expect(fullVersionLabel(info('1.0.0', '1000000')), 'v1.0.0-0');
    expect(fullVersionLabel(info('0.5.0', '99999')), 'v0.5.0 (99999)');
    expect(fullVersionLabel(info('0.5', '50008')), 'v0.5 (50008)');
  });

  testWidgets('version dialog shows version+build and the bundled changelog',
      (tester) async {
    final info = PackageInfo(
      appName: 'Sonority',
      packageName: 'be.casperverswijvelt.sonority',
      version: '0.5.0',
      buildNumber: '50008',
    );
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => showVersionDialog(ctx, info),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('v0.5.0-8'), findsOneWidget);
    // Real CHANGELOG.md asset loaded and parsed. Match the header shape, not a
    // literal version/date — those change on every release cut.
    expect(find.textContaining(RegExp(r'^\d+\.\d+\.\d+ — \d{4}-\d{2}-\d{2}$')),
        findsWidgets);
    expect(find.text('GitHub'), findsOneWidget);
  });
}
