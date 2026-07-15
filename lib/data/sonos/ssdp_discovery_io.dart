import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'diagnostics_log.dart';

/// Discovers Sonos players on the local network via SSDP.
///
/// Sonos uses SSDP (not mDNS). We send an `M-SEARCH` UDP datagram to the
/// multicast group `239.255.255.250:1900` and collect `LOCATION` headers from
/// the unicast replies. Each location points at a player's
/// `http://<ip>:1400/xml/device_description.xml`.
///
/// If SSDP yields nothing we fall back to a unicast sweep of the local /24
/// on TCP port 1400. Multicast sends silently fail on physical iPhones
/// (they need the restricted `com.apple.developer.networking.multicast`
/// entitlement; unicast only needs the local-network permission) and are
/// filtered by some mesh/guest networks. One hit is enough — the repository
/// recovers the rest of the system from topology.
class SsdpDiscovery {
  static final InternetAddress _multicast = InternetAddress('239.255.255.250');
  static const int _port = 1900;
  static const String _searchTarget = 'urn:schemas-upnp-org:device:ZonePlayer:1';

  /// Returns the set of unique device-description URLs that responded within
  /// [timeout]. Sends the query a few times because UDP is lossy.
  Future<Set<String>> discover({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final locations = <String>{};
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.multicastHops = 4;

      final completer = Completer<void>();
      final sub = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = socket!.receive();
        if (dg == null) return;
        final text = String.fromCharCodes(dg.data);
        final loc = _extractLocation(text);
        if (loc != null) locations.add(loc);
      });

      final message = _searchMessage();
      // Send the M-SEARCH a few times to ride over lost datagrams.
      for (var i = 0; i < 3; i++) {
        socket.send(message, _multicast, _port);
      }

      Timer(timeout, () {
        if (!completer.isCompleted) completer.complete();
      });
      await completer.future;
      await sub.cancel();
    } finally {
      socket?.close();
    }
    if (locations.isEmpty) {
      DiagnosticsLog.add(
          'discovery: SSDP multicast found none — falling back to unicast /24 sweep');
      final swept = await _scanSubnet();
      DiagnosticsLog.add('discovery: unicast sweep found ${swept.length}');
      return swept;
    }
    DiagnosticsLog.add('discovery: SSDP multicast found ${locations.length}');
    return locations;
  }

  /// Unicast fallback: probe every /24 neighbour on TCP :1400 and synthesize
  /// the same description URLs SSDP would have returned.
  Future<Set<String>> _scanSubnet() async {
    final locations = <String>{};
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final candidates = <String>{
      for (final i in interfaces)
        for (final a in i.addresses)
          if (!a.address.startsWith('169.254.')) ...subnetHosts(a.address),
    };
    await Future.wait(candidates.map((ip) async {
      try {
        final s = await Socket.connect(ip, 1400,
            timeout: const Duration(milliseconds: 600));
        s.destroy();
        locations.add('http://$ip:1400/xml/device_description.xml');
      } catch (_) {
        // Not a Sonos player (or not up) — skip.
      }
    }));
    return locations;
  }

  List<int> _searchMessage() {
    final msg = 'M-SEARCH * HTTP/1.1\r\n'
        'HOST: 239.255.255.250:$_port\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 1\r\n'
        'ST: $_searchTarget\r\n'
        '\r\n';
    return msg.codeUnits;
  }

  /// The other hosts of [ip]'s /24 (`.1`–`.254`, excluding [ip] itself).
  // ponytail: dart:io exposes no netmask — assume /24. On a wider subnet the
  // sweep still succeeds if ANY player shares this /24 slice (topology
  // recovers the rest); only all-players-outside-the-slice fails. If that
  // bites, add real netmask detection (platform channel / getifaddrs).
  static List<String> subnetHosts(String ip) {
    final prefix = ip.substring(0, ip.lastIndexOf('.'));
    return [
      for (var h = 1; h <= 254; h++)
        if ('$prefix.$h' != ip) '$prefix.$h',
    ];
  }

  String? _extractLocation(String response) {
    for (final line in const LineSplitter().convert(response)) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      if (line.substring(0, idx).trim().toLowerCase() == 'location') {
        final value = line.substring(idx + 1).trim();
        if (value.contains(':1400')) return value;
      }
    }
    return null;
  }
}
