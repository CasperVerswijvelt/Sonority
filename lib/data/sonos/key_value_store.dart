/// Minimal durable string store the repository uses to remember zone/pair
/// member names across app runs (so it can restore them when the bond is later
/// separated). Keeping this a port — rather than importing `shared_preferences`
/// directly — is what lets `lib/data/sonos/` stay pure Dart with no Flutter
/// dependency. The Flutter app injects a `shared_preferences`-backed adapter;
/// tests and CLI use the in-memory default.
abstract interface class KeyValueStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
}

/// In-memory [KeyValueStore] — the pure-Dart default. Does not persist across
/// process restarts, which is fine for tests/CLI; the app injects a persistent
/// implementation so real bonds restore names after a relaunch.
class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> getString(String key) async => _data[key];

  @override
  Future<void> setString(String key, String value) async {
    _data[key] = value;
  }
}
