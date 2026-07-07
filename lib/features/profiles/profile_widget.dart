import 'dart:convert';

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

/// Wires widget taps to [onApply] with the tapped profile's id — both the tap
/// that cold-started the app and taps while it runs. Call once at app start.
void initProfileWidget(void Function(String id) onApply) {
  HomeWidget.setAppGroupId(_appGroupId);
  void dispatch(Uri? uri) {
    if (uri == null || uri.host != 'apply') return;
    final id = uri.queryParameters['id'];
    if (id != null && id.isNotEmpty) onApply(id);
  }

  HomeWidget.widgetClicked.listen(dispatch);
  HomeWidget.initiallyLaunchedFromHomeWidget().then(dispatch);
}

/// Publishes the profile list to the shared store for the iOS widget's picker
/// (its AppIntent reads `widget_profiles`). Call whenever profiles change.
/// Harmless on Android (the widget there is configured per-instance instead).
Future<void> publishWidgetProfiles(List<Profile> profiles) async {
  final data = [
    for (final p in profiles)
      {
        'id': p.id,
        'name': p.name,
        'sf': sfSymbolName(p.iconId),
        'color': _hex(profileColor(p.color)),
      },
  ];
  await HomeWidget.saveWidgetData<String>('widget_profiles', jsonEncode(data));
  await HomeWidget.updateWidget(iOSName: _iosWidgetName);
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Persists one widget instance's chosen profile (id + name + rendered avatar)
/// to the shared store and refreshes the widget. Keyed by [widgetId] so each
/// placed widget can show a different profile.
Future<void> _saveWidgetProfile(int widgetId, Profile p) async {
  await HomeWidget.saveWidgetData<String>('profileId_$widgetId', p.id);
  await HomeWidget.saveWidgetData<String>('profileName_$widgetId', p.name);
  // Render the colour circle + glyph to a PNG the native widget loads.
  await HomeWidget.renderFlutterWidget(
    _WidgetAvatar(iconId: p.iconId, color: p.color),
    key: 'avatar_$widgetId',
    logicalSize: const Size(96, 96),
  );
  await HomeWidget.updateWidget(
      qualifiedAndroidName: _androidProvider, iOSName: _iosWidgetName);
}

class _WidgetAvatar extends StatelessWidget {
  final String iconId;
  final int color;
  const _WidgetAvatar({required this.iconId, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 96,
        height: 96,
        decoration:
            BoxDecoration(color: profileColor(color), shape: BoxShape.circle),
        child: Icon(profileIcon(iconId), color: Colors.white, size: 52),
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
