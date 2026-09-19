// [TrueplayApplyClient] talks to a player's `:1443` REST API over a `dart:io`
// `HttpClient` (self-signed cert), which doesn't exist on web. This barrel picks
// the real IO implementation everywhere except web, where it swaps in a throwing
// stub so the engine still compiles for the screenshot-only demo web build (see
// `lib/demo/demo_mode.dart`).
export 'trueplay_apply_io.dart'
    if (dart.library.html) 'trueplay_apply_web.dart';
