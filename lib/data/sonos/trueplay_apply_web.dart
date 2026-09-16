import 'identify_errors.dart';
import 'trueplay_codec.dart';

/// The public Sonos guest api-key — sufficient for a spectral-tuning apply (any
/// `X-Sonos-Api-Key` header qualifies; absent → HTTP 400).
const kSonosGuestApiKey = '123e4567-e89b-12d3-a456-426655440000';

/// Web stub for [TrueplayApplyClient] — the `:1443` API needs a `dart:io`
/// `HttpClient` with cert verification bypassed, which browsers can't do. The
/// only web build is demo mode (`--dart-define=DEMO=true`), where the client is
/// overridden; this exists purely so the engine compiles for the screenshot-only
/// web target.
class TrueplayApplyClient {
  const TrueplayApplyClient();

  Future<int> postConfig({
    required String ip,
    required String rincon,
    required String configId,
    required String encodedBase64,
    bool live = false,
  }) async =>
      throw const SpeakerUnreachable();

  Future<({int status, TrueplayDeviceConfig? config, String raw})>
      readDeviceConfig({
    required String ip,
    required String rincon,
  }) async =>
          throw const SpeakerUnreachable();

  Future<int> applySpectral({
    required String ip,
    required String rincon,
    required SpectralTuning tuning,
    bool live = false,
  }) async =>
      throw const SpeakerUnreachable();

  Future<int> clearAllTunings({
    required String ip,
    required String rincon,
    bool live = false,
  }) async =>
      throw const SpeakerUnreachable();
}
