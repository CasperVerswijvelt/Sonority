// The diagnostics bundle needs `dart:io` (OS version, network interfaces, and
// writing the zip to a temp file), which doesn't exist on web. This barrel picks
// the real IO implementation everywhere except web, where throwing/empty stubs
// keep the screenshot-only demo web build compiling (see demo_mode.dart).
export 'diagnostics_platform_io.dart'
    if (dart.library.html) 'diagnostics_platform_web.dart';
