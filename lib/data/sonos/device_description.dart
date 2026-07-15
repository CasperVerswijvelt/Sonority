import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/sonos_models.dart';

/// Fetches and parses a player's `/xml/device_description.xml`.
class DeviceDescriptionClient {
  final http.Client _http;
  DeviceDescriptionClient([http.Client? client]) : _http = client ?? http.Client();

  /// [locationUrl] is the SSDP `LOCATION`, e.g.
  /// `http://192.168.1.10:1400/xml/device_description.xml`.
  Future<SonosDevice> fetch(String locationUrl) async {
    final uri = Uri.parse(locationUrl);
    final res = await _http
        .get(uri)
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) {
      throw Exception('device_description.xml ${res.statusCode} from $locationUrl');
    }
    return _parse(res.body, ip: uri.host);
  }

  /// Returns the raw `device_description.xml` body verbatim — for the diagnostics
  /// bundle, which wants the full document (capability flags, min-app-version
  /// gates, household id, …) that [_parse] deliberately ignores.
  Future<String> fetchRaw(String locationUrl) async {
    final res = await _http
        .get(Uri.parse(locationUrl))
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) {
      throw Exception('device_description.xml ${res.statusCode} from $locationUrl');
    }
    return res.body;
  }

  SonosDevice _parse(String xml, {required String ip}) {
    final doc = XmlDocument.parse(xml);
    final device = doc.findAllElements('device').first;

    String? text(String tag) {
      final els = device.findElements(tag);
      return els.isEmpty ? null : els.first.innerText.trim();
    }

    final udn = text('UDN') ?? '';
    final uuid = udn.replaceFirst('uuid:', '');

    return SonosDevice(
      uuid: uuid,
      roomName: text('roomName') ?? text('displayName') ?? ip,
      modelName: text('modelName') ?? 'Sonos',
      modelNumber: text('modelNumber'),
      ip: ip,
      mac: text('MACAddress'),
      serial: text('serialNum'),
      softwareVersion: text('softwareVersion') ?? text('displayVersion'),
      hardwareVersion: text('hardwareVersion'),
    );
  }
}
