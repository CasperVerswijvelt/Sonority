import 'package:shared_preferences/shared_preferences.dart';

import '../data/sonos/key_value_store.dart';

/// [KeyValueStore] backed by `shared_preferences` — the app's persistent store,
/// injected into [SonosRepository] so the engine (`lib/data/sonos/`) stays free
/// of any Flutter dependency.
class SharedPreferencesKeyValueStore implements KeyValueStore {
  @override
  Future<String?> getString(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> setString(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
}
