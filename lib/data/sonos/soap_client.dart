import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'cancellation.dart';
import 'diagnostics_log.dart';

/// Minimal SOAP client for the Sonos local UPnP API (port 1400).
///
/// Every Sonos service is reached the same way: an HTTP POST to a control path
/// with a `SOAPACTION` header and a SOAP envelope body.
class SonosSoapClient {
  final http.Client _http;
  SonosSoapClient([http.Client? client]) : _http = client ?? http.Client();

  static const int port = 1400;

  /// Invoke [action] on [serviceType] at [controlPath] of the player at [ip].
  /// Returns the parsed `<Body>` element of the response. [timeout] can be
  /// shortened for rapid-fire calls (e.g. the LED blink) so a stalled request
  /// fails fast instead of freezing.
  Future<XmlElement> call({
    required String ip,
    required String controlPath,
    required String serviceType,
    required String action,
    Map<String, String> args = const {},
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final uri = Uri.parse('http://$ip:$port$controlPath');
    final body = buildEnvelope(
      serviceType: serviceType,
      action: action,
      args: args,
    );

    final http.Response res;
    try {
      res = await _http
          .post(
            uri,
            headers: {
              'Content-Type': 'text/xml; charset="utf-8"',
              'SOAPACTION': '"$serviceType#$action"',
              // Sonos players are unreliable with HTTP keep-alive: a pooled socket the
              // player has already closed makes the next request hang until timeout
              // (very visible when firing many calls in a row, like the LED blink).
              // Closing per request avoids reusing a dead connection.
              'Connection': 'close',
            },
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      // Recorded for the diagnostics bundle: outside a bonding op these are just
      // thrown and lost. (In a bonding op a timeout is expected/benign — the
      // write still lands — but capturing it here is harmless.)
      DiagnosticsLog.add(
        'SOAP $action @ $ip timed out after ${timeout.inSeconds}s',
      );
      rethrow;
    } catch (e) {
      // Transport-level failure (socket refused/reset, DNS, TLS) — a player
      // power-cycling or off-network. Capture for the bundle too; caught
      // generically so we don't import dart:io (keeps the engine web-safe).
      DiagnosticsLog.add('SOAP $action @ $ip transport error: $e');
      rethrow;
    }

    if (res.statusCode != 200) {
      // A fault body is usually XML, but a truncated/empty/non-XML error body
      // must still surface as a SonosSoapException — not an XmlParserException.
      final doc = _tryParse(res.body);
      final fault = doc?.findAllElements('faultstring');
      final code = doc?.findAllElements('errorCode');
      final ex = SonosSoapException(
        action,
        statusCode: res.statusCode,
        faultCode: (code == null || code.isEmpty) ? null : code.first.innerText,
        faultString: (fault == null || fault.isEmpty)
            ? res.reasonPhrase
            : fault.first.innerText,
      );
      // Deliberately NOT logged to DiagnosticsLog: a SOAP fault is a structured
      // exception that always propagates to a caller, which either narrates it
      // with context (the bond re-assert note) or handles it as expected (a
      // role-gated EQ 803). Logging it here just duplicated the former and
      // spammed the latter. Timeouts + transport errors above ARE logged (opaque,
      // easily lost); a genuinely unhandled fault still reaches main.dart's sink.
      throw ex;
    }

    final doc = XmlDocument.parse(res.body);
    final bodies = doc.findAllElements('Body', namespace: '*');
    if (bodies.isEmpty) {
      DiagnosticsLog.add('SOAP $action @ $ip: missing SOAP Body in response');
      throw SonosSoapException(
        action,
        faultString: 'Missing SOAP Body in response',
      );
    }
    return bodies.first;
  }

  /// Builds a SOAP envelope. Argument values are XML-escaped.
  static String buildEnvelope({
    required String serviceType,
    required String action,
    Map<String, String> args = const {},
  }) {
    final buf = StringBuffer()
      ..write('<?xml version="1.0" encoding="utf-8"?>')
      ..write(
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" ',
      )
      ..write('s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">')
      ..write('<s:Body>')
      ..write('<u:$action xmlns:u="$serviceType">');
    args.forEach((key, value) {
      buf.write('<$key>${_escape(value)}</$key>');
    });
    buf
      ..write('</u:$action>')
      ..write('</s:Body>')
      ..write('</s:Envelope>');
    return buf.toString();
  }

  static XmlDocument? _tryParse(String body) {
    try {
      return XmlDocument.parse(body);
    } on XmlException {
      return null;
    }
  }

  static String _escape(String input) => input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

/// Reading values out of a SOAP response body (the [XmlElement] returned by
/// [SonosSoapClient.call]). Response fields are flat children, so descendant
/// search is fine — unlike `device_description.xml`, which nests sub-devices and
/// must use scoped direct-child lookup instead.
extension SoapBodyText on XmlElement {
  /// First matching element's trimmed text, or null if absent.
  String? childText(String tag) {
    final els = findAllElements(tag);
    return els.isEmpty ? null : els.first.innerText.trim();
  }
}

/// Retries [op] while it fails at the TRANSPORT level — connection refused, or
/// the request timing out — which is exactly what a speaker does for ~20-30s
/// after Sonos detaches it from a bond: its :1400 control port closes and
/// reopens (hardware-observed in two user diagnostics bundles, on both a removed
/// HT satellite and a freed group member). Without this, the first call aimed
/// back at such a speaker fails an operation that would have worked moments
/// later — a profile apply that unbonds speakers and then re-uses them was
/// failing on exactly that.
///
/// A [SonosSoapException] means the speaker answered with a real fault, which no
/// amount of waiting fixes, so it rethrows straight away.
///
/// ponytail: per-call budget (7 waits ≈ 35s, comfortably past the observed
/// window), no shared deadline — so a caller looping over N speakers multiplies
/// it. Fine while only the one or two just-unbonded speakers are ever in the
/// window and the rest answer instantly; if a big zone with a genuinely dead
/// member ever stalls a flow, thread one deadline through the loop instead.
Future<T> retryUnreachable<T>(
  Future<T> Function() op, {
  int attempts = 8,
  Duration interval = const Duration(seconds: 5),
  CancellationToken? cancel,
}) async {
  for (var attempt = 1;; attempt++) {
    try {
      return await op();
    } on SonosSoapException {
      rethrow;
    } catch (_) {
      if (attempt >= attempts) rethrow;
      await interruptibleDelay(interval, cancel);
    }
  }
}

/// Raised when a Sonos device returns a SOAP fault.
class SonosSoapException implements Exception {
  final String action;
  final int? statusCode;
  final String? faultCode;
  final String? faultString;

  SonosSoapException(
    this.action, {
    this.statusCode,
    this.faultCode,
    this.faultString,
  });

  @override
  String toString() =>
      'SonosSoapException($action, status=$statusCode, code=$faultCode, msg=$faultString)';
}
