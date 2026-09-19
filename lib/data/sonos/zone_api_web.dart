/// Web stub for [ZoneApiClient] — see `zone_api.dart`. The demo web build never
/// talks to a speaker, so the read reports "no zone service" and opening a
/// session throws if anything ever reaches it.
library;

class ActiveZoneMember {
  final String uuid;
  final bool disconnected;
  const ActiveZoneMember({required this.uuid, required this.disconnected});
}

class ActiveZone {
  final String zoneId;
  final List<ActiveZoneMember> members;
  const ActiveZone({required this.zoneId, required this.members});
}

List<Map<String, Object>> zoneMembersFromMap(String rawMap) => const [];

class ZoneDefinition {
  final String zoneId;
  final String name;
  final String rawMap;
  const ZoneDefinition({
    required this.zoneId,
    required this.name,
    required this.rawMap,
  });
}

class ZoneApiClient {
  final Duration timeout;
  const ZoneApiClient({this.timeout = const Duration(seconds: 8)});

  Future<List<ActiveZone>?> activeZones(String ip) async => null;

  Future<T> withSession<T>(
          String ip, Future<T> Function(ZoneSession session) body,
          {bool live = false}) async =>
      throw UnsupportedError('The zones API is unavailable on web.');
}

/// Present only so callers type-check; nothing can obtain one on web.
abstract interface class ZoneSession {
  List<ActiveZone> get activeZones;
  List<ZoneDefinition> get definitions;
  Future<List<ZoneDefinition>> nextDefinitions();
  Future<void> addDefinition({required String name, required String rawMap});
  Future<void> updateDefinition(
      {required String zoneId, required String rawMap});
  Future<void> activate(String zoneId);
  Future<void> deactivate(String zoneId);
  Future<void> removeDefinition(String zoneId);
}

class ZoneApiException implements Exception {
  final String reason;
  const ZoneApiException(this.reason);
  @override
  String toString() => 'ZoneApiException: $reason';
}
