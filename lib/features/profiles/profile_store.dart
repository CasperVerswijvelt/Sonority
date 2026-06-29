import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'profile.dart';

/// Persists the user's profiles as one JSON blob in SharedPreferences (the same
/// pattern the stereo-pair name snapshots already use).
class ProfileStore {
  static const _key = 'profiles';

  Future<List<Profile>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return [for (final p in list) Profile.fromJson(p as Map<String, dynamic>)];
  }

  Future<void> save(List<Profile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(profiles.map((p) => p.toJson()).toList()));
  }
}
