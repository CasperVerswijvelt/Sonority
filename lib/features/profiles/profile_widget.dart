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
/// profiles from it, so it refreshes automatically. Android: tiles are baked at
/// config time, so re-render every placed widget's chosen profiles.
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
    // Android provider class `<pkg>.null`). Android reloads below.
    await HomeWidget.updateWidget(iOSName: _iosWidgetName);
    return;
  }

  // Android: re-render each placed widget's chosen tiles, dropping any profile
  // that no longer exists, and lazily upgrade old single-profile widgets.
  final byId = {for (final p in profiles) p.id: p};
  for (final w in await HomeWidget.getInstalledWidgets()) {
    final wid = w.androidWidgetId;
    if (wid == null) continue;
    final ids = await _widgetProfileIds(wid);
    final chosen = [for (final id in ids) byId[id]].whereType<Profile>().toList();
    final chosenIds = [for (final p in chosen) p.id];
    // Re-write the id list if it changed (a profile was deleted, or we're
    // migrating an old profileId_ key to the JSON list).
    if (chosenIds.join(',') != ids.join(',')) {
      await HomeWidget.saveWidgetData<String>(
          'profileIds_$wid', jsonEncode(chosenIds));
    }
    for (final p in chosen) {
      await _renderTile(p);
    }
  }
  await HomeWidget.updateWidget(qualifiedAndroidName: _androidProvider);
}

/// The profile ids a placed Android widget shows, newest key first with a
/// fallback to the pre-multi-profile single-id key (lazy migration).
Future<List<String>> _widgetProfileIds(int widgetId) async {
  final raw = await HomeWidget.getWidgetData<String>('profileIds_$widgetId');
  if (raw != null && raw.isNotEmpty) {
    return (jsonDecode(raw) as List).cast<String>();
  }
  final single = await HomeWidget.getWidgetData<String>('profileId_$widgetId');
  return single != null ? [single] : const [];
}

/// ARGB colour → `#RRGGBB` (drops alpha). Top-level for unit testing.
@visibleForTesting
String hexColor(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Persists one Android widget instance's chosen profiles: the ordered id list
/// (tap targets, order = tile order) and a SQUARE tile image per profile. The
/// native GridView shows each tile `fitCenter`. Tile images are keyed by profile
/// id (`tile_<id>`) so identical profiles across widgets share one render.
/// (iOS doesn't use this — its SwiftUI widget renders itself.)
Future<void> _saveWidgetProfiles(int widgetId, List<Profile> chosen) async {
  await HomeWidget.saveWidgetData<String>(
      'profileIds_$widgetId', jsonEncode([for (final p in chosen) p.id]));
  for (final p in chosen) {
    await _renderTile(p);
  }
  await HomeWidget.updateWidget(qualifiedAndroidName: _androidProvider);
}

/// Renders one profile's GLYPH-ONLY PNG (white, on a transparent square) and
/// stores its accent colour, keyed by profile id (shared across every widget
/// showing it). The native side derives the muted-tonal treatment from the accent
/// + system brightness: it tints a rounded card, tints this glyph to the accent,
/// sizes the glyph, and draws the name as a native label — so glyph, text, and
/// corners never stretch and sizing matches iOS.
Future<void> _renderTile(Profile p) async {
  await HomeWidget.saveWidgetData<String>(
      'tileColor_${p.id}', hexColor(profileColor(p.color)));
  await HomeWidget.saveWidgetData<String>('tileName_${p.id}', p.name);
  await HomeWidget.renderFlutterWidget(
    _WidgetTile(iconId: p.iconId),
    key: 'tile_${p.id}',
    logicalSize: const Size(300, 300),
  );
}

/// The Android tile's glyph: a white Material icon centred on a transparent
/// square. Rendered to a PNG; the native tile tints it to the accent and sizes
/// it (see [_renderTile]).
class _WidgetTile extends StatelessWidget {
  final String iconId;
  const _WidgetTile({required this.iconId});

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        // scaleDown keeps normal glyphs at full size but shrinks an over-wide one
        // (e.g. the sofa) so it fits the square canvas instead of being clipped.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: profileGlyph(iconId, size: 240, color: Colors.white),
        ),
      );
}

/// The Android widget-configuration UI. Runs as its own Flutter entrypoint
/// (`widgetConfig` in main.dart) so picking profiles for a freshly-placed widget
/// doesn't spin up the whole app + discovery. Multi-select + drag-to-order the
/// tiles, save → finish. When reconfiguring an existing widget it pre-selects
/// (and re-orders to) that widget's current profiles.
class WidgetConfigApp extends StatelessWidget {
  const WidgetConfigApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        // Follow the system, like the rest of the app + iOS — the picker + its
        // tonal avatars adapt to light/dark instead of always rendering dark.
        theme: AppTheme.light(null),
        darkTheme: AppTheme.dark(null),
        themeMode: ThemeMode.system,
        home: const _WidgetConfigScreen(),
      );
}

class _WidgetConfigScreen extends StatefulWidget {
  const _WidgetConfigScreen();
  @override
  State<_WidgetConfigScreen> createState() => _WidgetConfigScreenState();
}

class _WidgetConfigScreenState extends State<_WidgetConfigScreen> {
  int? _widgetId;
  /// All profiles in display / tile order (reorderable). Null while loading.
  List<Profile>? _ordered;
  /// Ids the user has ticked (subset of [_ordered]).
  final Set<String> _checked = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final idStr = await HomeWidget.initiallyLaunchedFromHomeWidgetConfigure();
    _widgetId = int.tryParse(idStr ?? '');
    final all = await ProfileStore().load();

    // Pre-select the widget's existing profiles (reconfigure) and float them to
    // the top in their saved order; the rest follow.
    final existing =
        _widgetId != null ? await _widgetProfileIds(_widgetId!) : const <String>[];
    final byId = {for (final p in all) p.id: p};
    final ordered = <Profile>[
      for (final id in existing)
        if (byId[id] != null) byId[id]!,
      for (final p in all)
        if (!existing.contains(p.id)) p,
    ];
    _checked.addAll(existing.where(byId.containsKey));
    if (mounted) setState(() => _ordered = ordered);
  }

  Future<void> _confirm() async {
    if (_widgetId != null) {
      final chosen =
          _ordered!.where((p) => _checked.contains(p.id)).toList();
      await _saveWidgetProfiles(_widgetId!, chosen);
    }
    await HomeWidget.finishHomeWidgetConfigure();
  }

  /// One picker row: a leading checkbox, the tonal avatar + name, and a trailing
  /// drag handle (the only drag origin, since default whole-row drag is off).
  Widget _configRow(BuildContext context, Profile p, int index) {
    final tonal = profileTonal(p.color, Theme.of(context).brightness);
    return ListTile(
      key: ValueKey(p.id),
      onTap: () => setState(() =>
          _checked.contains(p.id) ? _checked.remove(p.id) : _checked.add(p.id)),
      leading: Checkbox(
        value: _checked.contains(p.id),
        onChanged: (on) => setState(() =>
            (on ?? false) ? _checked.add(p.id) : _checked.remove(p.id)),
      ),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: tonal.card,
                borderRadius: BorderRadius.circular(tileRadius)),
            child: Center(
                child: profileGlyph(p.iconId, size: 20, color: tonal.icon)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(p.name, overflow: TextOverflow.ellipsis)),
        ],
      ),
      trailing: ReorderableDragStartListener(
        index: index,
        child: const Icon(Icons.drag_handle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _ordered;
    return Scaffold(
      appBar: AppBar(title: const Text('Pick profiles')),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No profiles yet — create one in Sonority first.',
                        textAlign: TextAlign.center),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ReorderableListView(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        // Explicit drag handle per row (below), so the whole-row
                        // long-press is off and tapping the checkbox never drags.
                        buildDefaultDragHandles: false,
                        header: const Padding(
                          padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                          child: Text(
                            'Pick the profiles to show, and drag the handle to set '
                            'their order.',
                          ),
                        ),
                        onReorder: (oldIndex, newIndex) => setState(() {
                          if (newIndex > oldIndex) newIndex -= 1;
                          list.insert(newIndex, list.removeAt(oldIndex));
                        }),
                        children: [
                          for (var i = 0; i < list.length; i++)
                            _configRow(context, list[i], i),
                        ],
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: FilledButton(
                          onPressed: _checked.isEmpty ? null : _confirm,
                          child: Text(_checked.isEmpty
                              ? 'Select at least one'
                              : 'Add ${_checked.length} to widget'),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
