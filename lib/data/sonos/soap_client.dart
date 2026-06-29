import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

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
    final body = buildEnvelope(serviceType: serviceType, action: action, args: args);

    final res = await _http.post(
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
    ).timeout(timeout);

    final doc = XmlDocument.parse(res.body);
    if (res.statusCode != 200) {
      final fault = doc.findAllElements('faultstring');
      final code = doc.findAllElements('errorCode');
      throw SonosSoapException(
        action,
        statusCode: res.statusCode,
        faultCode: code.isEmpty ? null : code.first.innerText,
        faultString: fault.isEmpty ? res.reasonPhrase : fault.first.innerText,
      );
    }

    final bodies = doc.findAllElements('Body', namespace: '*');
    if (bodies.isEmpty) {
      throw SonosSoapException(action, faultString: 'Missing SOAP Body in response');
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
      ..write('<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" ')
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

  static String _escape(String input) => input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

/// Raised when a Sonos device returns a SOAP fault.
class SonosSoapException implements Exception {
  final String action;
  final int? statusCode;
  final String? faultCode;
  final String? faultString;

  SonosSoapException(this.action, {this.statusCode, this.faultCode, this.faultString});

  @override
  String toString() =>
      'SonosSoapException($action, status=$statusCode, code=$faultCode, msg=$faultString)';
}
