import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'profile.dart';
import 'profile_ui.dart';

/// App-icon quick actions (long-press shortcuts) for applying profiles.
///
/// Custom, asset-free, no plugin — a single [MethodChannel] to native code that
/// owns both the shortcut list and tap delivery on each platform:
///  - **iOS**: monochrome **SF Symbols** (`UIApplicationShortcutIcon(systemImageName:)`),
///    the only colour iOS home-screen quick actions allow.
///  - **Android**: a full-colour per-profile icon — the profile's colour circle +
///    Material glyph, rendered here to a PNG and wrapped natively as the icon.
///
/// A tap only hands the profile id back to Dart (via [initProfileShortcuts]); the
/// long-running scan→apply happens in the app — it can't run in an OS shortcut's
/// short execution window.
const _channel = MethodChannel('be.casperverswijvelt.sonority/shortcuts');

/// iOS shows at most 4 quick actions; Android surfaces a similar handful. Publish
/// the first N in list order and drop the rest.
const maxProfileShortcuts = 4;

/// The profiles that actually get published, in order (respects the OS cap).
List<Profile> shortcutProfiles(List<Profile> profiles) =>
    profiles.take(maxProfileShortcuts).toList();

bool get _supported => Platform.isIOS || Platform.isAndroid;

/// Wires up tap delivery once: warm taps arrive as `applyShortcut` calls from
/// native; a cold-start tap is pulled via `getInitialShortcut`. Both funnel the
/// profile id to [onApply].
void initProfileShortcuts(void Function(String id) onApply) {
  if (!_supported) return;
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'applyShortcut' && call.arguments is String) {
      onApply(call.arguments as String);
    }
  });
  _channel.invokeMethod<String>('getInitialShortcut').then((id) {
    if (id != null) onApply(id);
  }).catchError((_) {/* channel not implemented (e.g. macOS) */});
}

/// Republishes the shortcut list from the current [profiles]. Call whenever
/// profiles change so titles/icons/order stay in sync.
Future<void> syncProfileShortcuts(List<Profile> profiles) async {
  if (!_supported) return;
  final items = <Map<String, Object>>[];
  for (final p in shortcutProfiles(profiles)) {
    items.add({
      'id': p.id,
      'title': p.name,
      // iOS uses the SF Symbol; Android uses the rendered PNG. Each side reads
      // only what it needs, so sending both is harmless.
      'sfSymbol': sfSymbolName(p.iconId),
      if (Platform.isAndroid) 'png': await _renderAvatarPng(p.iconId, p.color),
    });
  }
  await _channel.invokeMethod('setShortcuts', {'items': items});
}

/// Renders a profile's avatar (colour circle + Material glyph) to a square PNG
/// for the Android launcher icon — reuses [profileColor] / [profileIcon] so it
/// matches the in-app tile exactly.
Future<Uint8List> _renderAvatarPng(String iconId, int color,
    {double size = 144}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawCircle(
    Offset(size / 2, size / 2),
    size / 2,
    Paint()
      ..isAntiAlias = true
      ..color = profileColor(color),
  );
  final icon = profileIcon(iconId);
  final tp = TextPainter(
    textDirection: TextDirection.ltr,
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: size * 0.55,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: Colors.white,
      ),
    ),
  )..layout();
  tp.paint(canvas, Offset((size - tp.width) / 2, (size - tp.height) / 2));
  final image =
      await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}
