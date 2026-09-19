// [ZoneApiClient] talks to a player's `:1443` REST + websocket API over
// `dart:io`, which doesn't exist on web. This barrel picks the real IO
// implementation everywhere except web, where it swaps in a throwing stub so the
// engine still compiles for the screenshot-only demo web build (see
// `lib/demo/demo_mode.dart`).
export 'zone_api_io.dart' if (dart.library.html) 'zone_api_web.dart';
