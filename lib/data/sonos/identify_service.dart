// [IdentifyServiceClient] serves the chime WAV from a `dart:io` HTTP server,
// which doesn't exist on web. This barrel picks the real IO implementation
// everywhere except web, where it swaps in a throwing stub so the engine still
// compiles for the screenshot-only demo web build (see `lib/demo/demo_mode.dart`).
// [SpeakerUnreachable] is re-exported so callers keep importing one file.
export 'identify_errors.dart';
export 'identify_service_io.dart'
    if (dart.library.html) 'identify_service_web.dart';
