/// Web stub for [SsdpDiscovery] — browsers can't do UDP/raw sockets, so real
/// discovery is impossible on web. The only web build is demo mode
/// (`--dart-define=DEMO=true`), where `_DemoSonosRepository` overrides
/// `discover()` and this is never called. It exists purely so the engine
/// compiles for the screenshot-only web target.
class SsdpDiscovery {
  Future<Set<String>> discover({
    Duration timeout = const Duration(seconds: 4),
  }) async =>
      throw UnsupportedError('SSDP discovery is not available on web');

  /// Pure string math, kept for API parity with the IO impl.
  static List<String> subnetHosts(String ip) {
    final prefix = ip.substring(0, ip.lastIndexOf('.'));
    return [
      for (var h = 1; h <= 254; h++)
        if ('$prefix.$h' != ip) '$prefix.$h',
    ];
  }
}
