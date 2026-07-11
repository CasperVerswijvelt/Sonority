package be.casperverswijvelt.sonority

import io.flutter.embedding.android.FlutterActivity

/// Launched by the system when a Profile widget is placed. Runs the dedicated
/// `widgetConfig` Dart entrypoint (a lightweight profile picker) rather than the
/// full app; the Dart side reads the widget id, saves the choice, and calls
/// `finishHomeWidgetConfigure()` to complete.
class ProfileWidgetConfigActivity : FlutterActivity() {
    override fun getDartEntrypointFunctionName(): String = "widgetConfig"
}
