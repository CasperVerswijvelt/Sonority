import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../../core/theme.dart';
import 'profile.dart';
import 'profile_store.dart';
import 'profile_ui.dart';

/// Home-screen widget: a single, user-configured profile the user taps to apply.
/// The native widget UI is per-platform (RemoteViews on Android, WidgetKit on
/// iOS); this file is the shared Dart glue — `home_widget` bridges the data +
/// launch handling. Like app shortcuts, a tap can't run the multi-minute apply
/// in the widget's process, so it just launches the app and funnels the profile
/// id into the same apply seam.

/// iOS App Group (shared container between app + widget extension). Harmless on
/// Android. Must match the group added in Xcode + the widget extension.
const _appGroupId = 'group.be.casperverswijvelt.sonority';

/// Fully-qualified Android provider class (for `updateWidget`).
const _androidProvider = 'be.casperverswijvelt.sonority.ProfileWidgetProvider';

/// iOS WidgetKit widget name (the `kind` string in the extension).
const _iosWidgetName = 'ProfileWidget';

/// home_widget only bridges iOS/Android; on macOS every call throws
/// MissingPluginException, so gate like [profile_shortcuts].
bool get _supported => Platform.isIOS || Platform.isAndroid;

/// Parses a widget-tap deep link (`sonority://apply?...&id=<profileId>`) to the
/// tapped profile id, or null if it isn't a valid apply link. Top-level so it's
/// unit-testable without the plugin.
@visibleForTesting
String? applyIdFromWidgetUri(Uri? uri) {
  if (uri == null || uri.host != 'apply') return null;
  final id = uri.queryParameters['id'];
  return (id != null && id.isNotEmpty) ? id : null;
}

/// Wires widget taps to [onApply] with the tapped profile's id — both the tap
/// that cold-started the app and taps while it runs. Call once at app start.
void initProfileWidget(void Function(String id) onApply) {
  if (!_supported) return;
  void dispatch(Uri? uri) {
    final id = applyIdFromWidgetUri(uri);
    if (id != null) onApply(id);
  }

  HomeWidget.setAppGroupId(_appGroupId);
  HomeWidget.widgetClicked.listen(dispatch);
  HomeWidget.initiallyLaunchedFromHomeWidget().then(dispatch);
}

/// Keeps placed widgets in sync when profiles change (rename / recolour / icon).
/// iOS: publish the whole list — the widget's AppIntent re-resolves the selected
/// profile from it, so it refreshes automatically. Android: the tile is baked at
/// config time, so re-render any placed widget whose profile is in the new list.
Future<void> publishWidgetProfiles(List<Profile> profiles) async {
  if (!_supported) return;
  final data = [
    for (final p in profiles)
      {
        'id': p.id,
        'name': p.name,
        'sf': sfSymbolName(p.iconId),
        'color': hexColor(profileColor(p.color)),
      },
  ];
  await HomeWidget.saveWidgetData<String>('widget_profiles', jsonEncode(data));

  if (Platform.isIOS) {
    // iOS-only: updateWidget with just iOSName throws on Android (it resolves an
    // Android provider class `<pkg>.null`). Android reloads via _saveWidgetProfile.
    await HomeWidget.updateWidget(iOSName: _iosWidgetName);
    return;
  }

  // Android: re-render any placed widget whose profile is in the new list.
  final byId = {for (final p in profiles) p.id: p};
  for (final w in await HomeWidget.getInstalledWidgets()) {
    final wid = w.androidWidgetId;
    if (wid == null) continue;
    final p = byId[await HomeWidget.getWidgetData<String>('profileId_$wid')];
    if (p != null) await _saveWidgetProfile(wid, p);
  }
}

/// ARGB colour → `#RRGGBB` (drops alpha). Top-level for unit testing.
@visibleForTesting
String hexColor(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Persists one Android widget instance's chosen profile: the tap-target id and
/// a SQUARE tile image (profile colour + glyph + name) rendered in Flutter. The
/// provider shows the tile `fitCenter`, so it's always the largest square that
/// fits the widget's space. Keyed by [widgetId] so each placed widget can show a
/// different profile. (iOS doesn't use this — its SwiftUI widget renders itself.)
Future<void> _saveWidgetProfile(int widgetId, Profile p) async {
  await HomeWidget.saveWidgetData<String>('profileId_$widgetId', p.id);
  await HomeWidget.renderFlutterWidget(
    _WidgetTile(iconId: p.iconId, color: p.color, name: p.name),
    key: 'tile_$widgetId',
    logicalSize: const Size(300, 300),
  );
  await HomeWidget.updateWidget(qualifiedAndroidName: _androidProvider);
}

/// The Android widget's visual: a square, full-colour rounded tile with the
/// white glyph + profile name. Rendered to a PNG and shown `fitCenter`.
class _WidgetTile extends StatelessWidget {
  final String iconId;
  final int color;
  final String name;
  const _WidgetTile(
      {required this.iconId, required this.color, required this.name});

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          width: 300,
          height: 300,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: profileColor(color),
            borderRadius: BorderRadius.circular(64),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(profileIcon(iconId), color: Colors.white, size: 120),
              const SizedBox(height: 16),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
}

/// The Android widget-configuration UI. Runs as its own Flutter entrypoint
/// (`widgetConfig` in main.dart) so picking a profile for a freshly-placed
/// widget doesn't spin up the whole app + discovery. Pick → save → finish.
class WidgetConfigApp extends StatelessWidget {
  const WidgetConfigApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(null),
        home: const _WidgetConfigScreen(),
      );
}

class _WidgetConfigScreen extends StatefulWidget {
  const _WidgetConfigScreen();
  @override
  State<_WidgetConfigScreen> createState() => _WidgetConfigScreenState();
}

class _WidgetConfigScreenState extends State<_WidgetConfigScreen> {
  late final Future<List<Profile>> _profiles = ProfileStore().load();

  Future<void> _pick(Profile p) async {
    final idStr = await HomeWidget.initiallyLaunchedFromHomeWidgetConfigure();
    final widgetId = int.tryParse(idStr ?? '');
    if (widgetId != null) await _saveWidgetProfile(widgetId, p);
    await HomeWidget.finishHomeWidgetConfigure();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pick a profile')),
      body: FutureBuilder<List<Profile>>(
        future: _profiles,
        builder: (context, snap) {
          final list = snap.data;
          if (list == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No profiles yet — create one in Sonority first.',
                    textAlign: TextAlign.center),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final p in list)
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: profileColor(p.color), shape: BoxShape.circle),
                    child: Icon(profileIcon(p.iconId),
                        color: Colors.white, size: 22),
                  ),
                  title: Text(p.name),
                  onTap: () => _pick(p),
                ),
            ],
          );
        },
      ),
    );
  }
}
