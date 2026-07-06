import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../core/tone_generator.dart';
import 'soap_client.dart';

/// Plays a short chime on a specific speaker so the user can tell which physical
/// box will be Left vs Right.
///
/// How: starts a tiny local HTTP server serving an in-memory WAV, then uses the
/// speaker's `AVTransport` service to set that URL and play it. The speaker must
/// be standalone (our front candidates are), and the phone must be on the same
/// LAN as the speaker (it always is — that's how discovery worked).
class IdentifyServiceClient {
  final SonosSoapClient _soap;
  final void Function(String message)? onLog;
  IdentifyServiceClient([SonosSoapClient? client, this.onLog])
      : _soap = client ?? SonosSoapClient();

  static const _service = 'urn:schemas-upnp-org:service:AVTransport:1';
  static const _control = '/MediaRenderer/AVTransport/Control';
  static const _rcService = 'urn:schemas-upnp-org:service:RenderingControl:1';
  static const _rcControl = '/MediaRenderer/RenderingControl/Control';

  HttpServer? _server;
  Uint8List? _wav;
  Completer<void>? _fetchSignal;

  /// Plays the chime on the speaker at [speakerIp]. Saves the current volume/
  /// mute, unmutes and sets an audible level, plays, then restores — so a
  /// muted or quiet speaker still produces an identifiable sound.
  ///
  /// Throws [SpeakerUnreachable] if the speaker never fetches the served clip
  /// (e.g. phone and speaker aren't on the same LAN, or running in an emulator).
  Future<void> chirp(String speakerIp) async {
    final url = await _ensureServing(speakerIp);
    onLog?.call('serving chime at $url');
    _fetchSignal = Completer<void>();

    int? prevVolume;
    bool? prevMute;
    try {
      prevVolume = await _getVolume(speakerIp);
      prevMute = await _getMute(speakerIp);
      onLog?.call('volume=$prevVolume mute=$prevMute');
      if (prevMute == true) await _setMute(speakerIp, false);
      final target = (prevVolume == null || prevVolume < 20) ? 30 : prevVolume;
      await _setVolume(speakerIp, target);
    } catch (e) {
      onLog?.call('volume prep skipped: $e');
    }

    // DIDL-Lite metadata — Sonos plays bare http(s) URIs more reliably when
    // given minimal metadata describing the item.
    const metadata =
        '<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" '
        'xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">'
        '<item id="0" parentID="-1" restricted="1">'
        '<dc:title>Sonority chime</dc:title>'
        '<upnp:class>object.item.audioItem.musicTrack</upnp:class>'
        '</item></DIDL-Lite>';

    try {
      await _soap.call(
        ip: speakerIp,
        controlPath: _control,
        serviceType: _service,
        action: 'SetAVTransportURI',
        args: {
          'InstanceID': '0',
          'CurrentURI': url,
          'CurrentURIMetaData': metadata,
        },
      );
      onLog?.call('SetAVTransportURI ok');
      await _soap.call(
        ip: speakerIp,
        controlPath: _control,
        serviceType: _service,
        action: 'Play',
        args: {'InstanceID': '0', 'Speed': '1'},
      );
      onLog?.call('Play ok');

      // Confirm the speaker can actually reach us; otherwise it plays nothing.
      try {
        await _fetchSignal!.future.timeout(const Duration(seconds: 4));
      } on TimeoutException {
        throw const SpeakerUnreachable();
      }

      // Let the chime finish before restoring volume.
      await Future<void>.delayed(const Duration(milliseconds: 1800));
    } finally {
      try {
        if (prevVolume != null) await _setVolume(speakerIp, prevVolume);
        if (prevMute == true) await _setMute(speakerIp, true);
        onLog?.call('restored volume=$prevVolume mute=$prevMute');
      } catch (e) {
        onLog?.call('volume restore skipped: $e');
      }
    }
  }

  Future<int?> _getVolume(String ip) async {
    final body = await _soap.call(
      ip: ip,
      controlPath: _rcControl,
      serviceType: _rcService,
      action: 'GetVolume',
      args: {'InstanceID': '0', 'Channel': 'Master'},
    );
    return int.tryParse(body.childText('CurrentVolume') ?? '');
  }

  Future<bool?> _getMute(String ip) async {
    final body = await _soap.call(
      ip: ip,
      controlPath: _rcControl,
      serviceType: _rcService,
      action: 'GetMute',
      args: {'InstanceID': '0', 'Channel': 'Master'},
    );
    final t = body.childText('CurrentMute');
    return t == null ? null : t == '1';
  }

  Future<void> _setVolume(String ip, int volume) => _soap.call(
        ip: ip,
        controlPath: _rcControl,
        serviceType: _rcService,
        action: 'SetVolume',
        args: {'InstanceID': '0', 'Channel': 'Master', 'DesiredVolume': '$volume'},
      );

  Future<void> _setMute(String ip, bool mute) => _soap.call(
        ip: ip,
        controlPath: _rcControl,
        serviceType: _rcService,
        action: 'SetMute',
        args: {'InstanceID': '0', 'Channel': 'Master', 'DesiredMute': mute ? '1' : '0'},
      );

  Future<String> _ensureServing(String speakerIp) async {
    final wav = _wav ??= generateChimeWav();
    final server = _server ??= await _startServer(wav);
    final host = await _lanIpFor(speakerIp);
    return 'http://$host:${server.port}/chime.wav';
  }

  Future<HttpServer> _startServer(Uint8List wav) async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    server.listen((req) async {
      onLog?.call(
          'HTTP ${req.method} ${req.uri} from ${req.connectionInfo?.remoteAddress.address}');
      if (_fetchSignal != null && !_fetchSignal!.isCompleted) {
        _fetchSignal!.complete();
      }
      final res = req.response;
      res.headers.contentType = ContentType('audio', 'wav');
      res.headers.set(HttpHeaders.contentLengthHeader, wav.length);
      res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      if (req.method != 'HEAD') res.add(wav);
      await res.close();
    });
    return server;
  }

  /// Pick the phone's IPv4 on the same /24 as the speaker (falls back to any
  /// non-loopback IPv4) so the speaker can reach the served file.
  Future<String> _lanIpFor(String speakerIp) async {
    final interfaces =
        await NetworkInterface.list(type: InternetAddressType.IPv4);
    final lastDot = speakerIp.lastIndexOf('.');
    final prefix = lastDot > 0 ? '${speakerIp.substring(0, lastDot)}.' : null;

    if (prefix != null) {
      for (final ni in interfaces) {
        for (final a in ni.addresses) {
          if (a.address.startsWith(prefix)) return a.address;
        }
      }
    }
    for (final ni in interfaces) {
      for (final a in ni.addresses) {
        if (!a.isLoopback) return a.address;
      }
    }
    throw Exception('No LAN IP found to serve the chime from.');
  }

  Future<void> dispose() async {
    await _server?.close(force: true);
    _server = null;
  }
}

/// Thrown when a speaker accepts the play command but never fetches the clip,
/// meaning it can't reach this device over the network.
class SpeakerUnreachable implements Exception {
  const SpeakerUnreachable();
  @override
  String toString() =>
      'The speaker could not reach your phone to play the sound. Make sure '
      'your phone and speakers are on the same Wi‑Fi network. (Android '
      'emulators can’t reach speakers on your LAN — use a real device.)';
}
