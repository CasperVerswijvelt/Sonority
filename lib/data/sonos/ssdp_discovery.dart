// [SsdpDiscovery] uses `dart:io` (raw UDP + TCP sockets), which doesn't exist
// on web. This barrel picks the real IO implementation everywhere except web,
// where it swaps in a throwing stub so the engine still compiles for the
// screenshot-only demo web build (see `lib/demo/demo_mode.dart`).
export 'ssdp_discovery_io.dart'
    if (dart.library.html) 'ssdp_discovery_web.dart';
