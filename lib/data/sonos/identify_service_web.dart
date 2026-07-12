import 'identify_errors.dart';
import 'soap_client.dart';

/// Web stub for [IdentifyServiceClient] — the chime needs a local `dart:io`
/// HTTP server, which browsers can't run. The only web build is demo mode
/// (`--dart-define=DEMO=true`), where identify is either overridden or never
/// tapped; this exists purely so the engine compiles for the screenshot-only
/// web target. `chirp()` throws the same [SpeakerUnreachable] the IO impl uses
/// when a speaker can't be reached.
class IdentifyServiceClient {
  final void Function(String message)? onLog;
  IdentifyServiceClient([SonosSoapClient? client, this.onLog]);

  Future<void> chirp(String speakerIp) async => throw const SpeakerUnreachable();

  Future<void> dispose() async {}
}
