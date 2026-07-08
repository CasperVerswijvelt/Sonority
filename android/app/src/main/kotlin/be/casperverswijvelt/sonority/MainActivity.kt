package be.casperverswijvelt.sonority

import android.content.Intent
import android.graphics.BitmapFactory
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Hosts the app-shortcut channel: publishes full-colour dynamic shortcuts (a
/// per-profile colour circle + glyph, rendered on the Dart side) and delivers
/// taps back to Flutter. No plugin — the Dart side is `profile_shortcuts.dart`.
class MainActivity : FlutterActivity() {
    private val channelName = "be.casperverswijvelt.sonority/shortcuts"
    private val extraId = "shortcut_id"
    private val actionApply = "be.casperverswijvelt.sonority.APPLY_PROFILE"
    private var channel: MethodChannel? = null

    // Profile id of the shortcut that cold-started the app, pulled by Dart via
    // `getInitialShortcut` once the engine is ready.
    private var launchShortcutId: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        this.channel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setShortcuts" -> {
                    setShortcuts(call.argument<List<Map<String, Any>>>("items") ?: emptyList())
                    result.success(null)
                }
                "getInitialShortcut" -> {
                    result.success(launchShortcutId)
                    launchShortcutId = null
                }
                else -> result.notImplemented()
            }
        }
        // Cold start via a shortcut: stash for Dart to pull.
        launchShortcutId =
            intent?.takeIf { it.action == actionApply }?.getStringExtra(extraId)
    }

    // Warm tap (launchMode=singleTop): deliver straight to Dart.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == actionApply) {
            intent.getStringExtra(extraId)?.let {
                channel?.invokeMethod("applyShortcut", it)
            }
        }
    }

    private fun setShortcuts(items: List<Map<String, Any>>) {
        val shortcuts = items.mapNotNull { item ->
            val id = item["id"] as? String ?: return@mapNotNull null
            val title = item["title"] as? String ?: return@mapNotNull null
            val intent = Intent(this, MainActivity::class.java).apply {
                action = actionApply
                putExtra(extraId, id)
            }
            val builder = ShortcutInfoCompat.Builder(this, id)
                .setShortLabel(title)
                .setIntent(intent)
            (item["png"] as? ByteArray)?.let { png ->
                BitmapFactory.decodeByteArray(png, 0, png.size)?.let { bmp ->
                    builder.setIcon(IconCompat.createWithBitmap(bmp))
                }
            }
            builder.build()
        }
        ShortcutManagerCompat.setDynamicShortcuts(this, shortcuts)
    }
}
