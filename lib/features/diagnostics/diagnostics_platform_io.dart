import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// e.g. `android 34` / `macos Version 15.3 (Build 24D60)`.
String osDescription() =>
    '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';

/// The device's network interfaces + addresses (no netmask — `dart:io` doesn't
/// expose it). Only useful for "speakers not found" discovery bugs, but it's the
/// one signal available when the topology comes back empty.
Future<String> networkInterfacesText() async {
  final ifaces = await NetworkInterface.list(
    includeLoopback: false,
    includeLinkLocal: true,
  );
  final b = StringBuffer();
  for (final i in ifaces) {
    b.writeln('${i.name}:');
    for (final a in i.addresses) {
      b.writeln('  ${a.address}  (${a.type.name})');
    }
  }
  final s = b.toString().trimRight();
  return s.isEmpty ? '(no interfaces)' : s;
}

/// Writes [bytes] to a temp file named [name] and returns its path.
// ponytail: no cleanup — the zip is consumed asynchronously by the share/email
// sheet (deleting it here would race), and the OS reclaims the temp dir. Add a
// sweep only if leftover bundles ever matter.
Future<String> writeTempFile(String name, List<int> bytes) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes);
  return file.path;
}
