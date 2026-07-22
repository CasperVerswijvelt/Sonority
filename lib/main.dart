import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/sonos/diagnostics_log.dart';
import 'demo/demo_mode.dart';
import 'features/profiles/profile_widget.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Capture uncaught errors into the rolling diagnostics log so they land in a
  // shared bundle. Keep the default console/redscreen behaviour intact.
  final priorOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    DiagnosticsLog.add('FlutterError: ${details.exceptionAsString()}');
    priorOnError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    DiagnosticsLog.add('Uncaught: $error');
    return false; // not handled — let the platform log it too.
  };
  // Orientation is governed per-platform, not locked here: iPhone stays
  // portrait (Info.plist UISupportedInterfaceOrientations), iPad allows all
  // orientations + Split View (…~ipad), Android phones stay portrait
  // (AndroidManifest screenOrientation), macOS is a fixed-size window. The
  // responsive layout (kWideLayoutBreakpoint) adapts to whatever size results.
  runApp(ProviderScope(
    overrides: kDemoMode ? demoOverrides() : const [],
    child: const SonorityApp(),
  ));
}

/// Dedicated entrypoint for the Android home-screen-widget configuration
/// activity — a lightweight profile picker, not the full app. Referenced by
/// `ProfileWidgetConfigActivity.getDartEntrypointFunctionName()`.
@pragma('vm:entry-point')
void widgetConfig() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WidgetConfigApp());
}
