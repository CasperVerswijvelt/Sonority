// Generates docs/index.html (the GitHub Pages landing page) from the marketing
// copy that already lives in the repo — no text is duplicated:
//   * tagline   <- pubspec.yaml `description:`
//   * captions  <- design/store.html `SHOTS` array (the store-graphic source)
// Screenshots/badges/logo are reused in place from docs/. Run after copy changes:
//   dart run tool/gen_site.dart
import 'dart:io';

void main() {
  final root = Directory.current.path;
  String read(String p) => File('$root/$p').readAsStringSync();

  final tagline = RegExp(r'^description:\s*"(.*)"', multiLine: true)
      .firstMatch(read('pubspec.yaml'))
      ?.group(1);
  if (tagline == null || tagline.isEmpty) {
    stderr.writeln('gen_site: could not read description: from pubspec.yaml');
    exit(1);
  }

  // ponytail: regex-couples to the SHOTS object shape in store.html; the count
  // assert below fails loudly if that literal ever drifts. Cheaper than a JS parser.
  final shots = RegExp(
    r"src\s*:\s*'([^']*)'\s*,\s*head\s*:\s*'([^']*)'\s*,\s*sub\s*:\s*'([^']*)'",
    dotAll: true,
  ).allMatches(read('design/store.html')).toList();
  if (shots.length != 4) {
    stderr.writeln('gen_site: expected 4 SHOTS in design/store.html, got ${shots.length}');
    exit(1);
  }

  final template = read('tool/site_template.html');
  final rowStart = template.indexOf('<!--ROW-->');
  final rowEnd = template.indexOf('<!--/ROW-->');
  if (rowStart < 0 || rowEnd < 0) {
    stderr.writeln('gen_site: ROW markers missing in tool/site_template.html');
    exit(1);
  }
  final row = template.substring(rowStart + '<!--ROW-->'.length, rowEnd);

  final rows = shots.map((m) {
    // Screenshots live in Git LFS; GitHub Pages serves the LFS *pointer*, not
    // the image, so point at the media endpoint that resolves LFS instead.
    final src = m
        .group(1)!
        .replaceFirst(
          'shots/',
          'https://media.githubusercontent.com/media/'
              'CasperVerswijvelt/Sonority/main/docs/screenshots/',
        );
    return row
        .replaceAll('{{SHOT}}', src)
        .replaceAll('{{HEAD}}', m.group(2)!)
        .replaceAll('{{SUB}}', m.group(3)!);
  }).join();

  final html = template
      .substring(0, rowStart)
      .replaceAll('{{TAGLINE}}', tagline) +
      rows +
      template.substring(rowEnd + '<!--/ROW-->'.length);

  File('$root/docs/index.html').writeAsStringSync(html);
  stdout.writeln('wrote docs/index.html (${shots.length} sections)');
}
