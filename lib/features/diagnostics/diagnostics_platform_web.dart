// Web stubs — the diagnostics bundle is never built on web (the only web build
// is the screenshot-only demo). These exist purely so the app compiles for web.

String osDescription() => 'web';

Future<String> networkInterfacesText() async => '(unavailable on web)';

Future<String> writeTempFile(String name, List<int> bytes) async =>
    throw UnsupportedError('Diagnostics bundle is not available on web');
