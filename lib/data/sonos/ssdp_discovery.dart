import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Discovers Sonos players on the local network via SSDP.
///
/// Sonos uses SSDP (not mDNS). We send an `M-SEARCH` UDP datagram to the
/// multicast group `239.255.255.250:1900` and collect `LOCATION` headers from
/// the unicast replies. Each location points at a player's
/// `http://<ip>:1400/xml/device_description.xml`.
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
