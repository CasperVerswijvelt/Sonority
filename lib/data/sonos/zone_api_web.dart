/// Web stub for [ZoneApiClient] — see `zone_api.dart`. The demo web build never
/// talks to a speaker, so [supported] simply reports false and the caller takes
/// its SOAP path; the write throws if anything ever reaches it.
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

  Future<bool> supported(String ip) async => false;

  Future<List<ActiveZone>?> activeZones(String ip) async => null;

  Future<void> updateDefinition({
    required String ip,
    required String zoneId,
    required String rawMap,
    bool live = false,
  }) async => throw UnsupportedError('The zones API is unavailable on web.');

  Future<List<ZoneDefinition>> definitions(String ip) async => const [];

  Future<void> addDefinition({
    required String ip,
    required String name,
    required String rawMap,
    bool live = false,
  }) async => throw UnsupportedError('The zones API is unavailable on web.');

  Future<void> activate({
    required String ip,
    required String zoneId,
    bool live = false,
  }) async => throw UnsupportedError('The zones API is unavailable on web.');

  Future<void> deactivate({
    required String ip,
    required String zoneId,
    bool live = false,
  }) async => throw UnsupportedError('The zones API is unavailable on web.');

  Future<void> removeDefinition({
    required String ip,
    required String zoneId,
    bool live = false,
  }) async => throw UnsupportedError('The zones API is unavailable on web.');
}

class ZoneApiException implements Exception {
  final String reason;
  const ZoneApiException(this.reason);
  @override
  String toString() => 'ZoneApiException: $reason';
}
