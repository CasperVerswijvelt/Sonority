import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/profiles/profile_widget.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Single portrait layout everywhere (no landscape to design for).
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const ProviderScope(child: SonorityApp()));
}

/// Dedicated entrypoint for the Android home-screen-widget configuration
/// activity — a lightweight profile picker, not the full app. Referenced by
/// `ProfileWidgetConfigActivity.getDartEntrypointFunctionName()`.
@pragma('vm:entry-point')
void widgetConfig() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WidgetConfigApp());
}
