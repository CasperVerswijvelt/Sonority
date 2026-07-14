package be.casperverswijvelt.sonority

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import kotlin.math.ceil

/// The widget's ordered profile ids: the JSON list, or the pre-multi-profile
/// single-id key (lazy migration of widgets placed before that feature).
fun readWidgetProfileIds(prefs: SharedPreferences, widgetId: Int): List<String> {
    prefs.getString("profileIds_$widgetId", null)?.let { raw ->
        return try {
            val arr = org.json.JSONArray(raw)
            List(arr.length()) { arr.getString(it) }
        } catch (_: Exception) {
            emptyList()
        }
    }
    return prefs.getString("profileId_$widgetId", null)?.let { listOf(it) } ?: emptyList()
}

/// Home-screen widget showing a user-picked SET of profiles, each tile taps to
/// apply. Tiles are rendered to PNGs in Flutter (keyed `tile_<profileId>`); this
/// provider lays them out as a weight-filled grid — a vertical LinearLayout of
/// weighted rows, each holding weighted tile cells (see the profile_widget_*
/// layouts). Weights fill the widget exactly at any size, so there's no reading
/// of the launcher-reported pixel size (which varies by launcher/size and used to
/// cause left-anchored dead space, clipped corners, or gap drift). `bestGrid`
/// only picks the row/column split. Per tile, a PendingIntent launches
/// `sonority://apply?homeWidget=1&id=<profileId>` — the shape Flutter parses.
class ProfileWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { buildWidget(context, appWidgetManager, it) }
    }

    // Re-pack the grid when the user resizes the widget (row/column split may change).
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        buildWidget(context, appWidgetManager, appWidgetId)
    }

    private fun buildWidget(context: Context, mgr: AppWidgetManager, id: Int) {
        val prefs = HomeWidgetPlugin.getData(context)
        val tiles = readWidgetProfileIds(prefs, id).mapNotNull { pid ->
            prefs.getString("tile_$pid", null)?.let { path ->
                Tile(pid, path, prefs.getString("tileName_$pid", "") ?: "",
                    prefs.getString("tileColor_$pid", null))
            }
        }
        val views = RemoteViews(context.packageName, R.layout.profile_widget)
        // ESSENTIAL, not redundant: on resize/update the launcher re-applies this
        // RemoteViews onto the EXISTING view tree, where addView APPENDS. Without
        // this clear, every update stacks another full set of tiles into the grid.
        views.removeAllViews(R.id.grid)

        if (tiles.isEmpty()) {
            // Empty state: hide the grid, show the "Tap to pick profiles" label and
            // make tapping it open this widget's configure screen.
            views.setViewVisibility(R.id.grid, android.view.View.GONE)
            views.setViewVisibility(R.id.empty, android.view.View.VISIBLE)
            val configure = Intent(context, ProfileWidgetConfigActivity::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_CONFIGURE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                data = Uri.fromParts("widget", id.toString(), null) // distinct per widget
            }
            views.setOnClickPendingIntent(
                R.id.empty,
                PendingIntent.getActivity(
                    context, id, configure,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            mgr.updateAppWidget(id, views)
            return
        }

        views.setViewVisibility(R.id.empty, android.view.View.GONE)
        views.setViewVisibility(R.id.grid, android.view.View.VISIBLE)

        // Row/column split only — sizes come from layout weights, not these dp.
        val opts = mgr.getAppWidgetOptions(id)
        val wDp = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH).takeIf { it > 0 } ?: DEFAULT_DP
        val hDp = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT).takeIf { it > 0 } ?: DEFAULT_DP
        val (cols, _) = bestGrid(tiles.size, wDp, hDp)
        val dark = (context.resources.configuration.uiMode and
            Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES

        tiles.chunked(cols).forEach { rowTiles ->
            val row = RemoteViews(context.packageName, R.layout.profile_widget_row)
            rowTiles.forEach { row.addView(R.id.row, buildCell(context, it, dark)) }
            // Pad a short last row so its tiles keep the full rows' width.
            repeat(cols - rowTiles.size) {
                row.addView(R.id.row, RemoteViews(context.packageName, R.layout.profile_widget_spacer))
            }
            views.addView(R.id.grid, row)
        }
        mgr.updateAppWidget(id, views)
    }

    private fun buildCell(context: Context, tile: Tile, dark: Boolean): RemoteViews {
        val accent = tile.colorHex?.let { runCatching { Color.parseColor(it) }.getOrNull() } ?: Color.GRAY
        val tones = ProfileTonal.of(accent, dark)
        return RemoteViews(context.packageName, R.layout.profile_tile_cell).apply {
            setInt(R.id.tile_bg, "setColorFilter", tones.card)
            setInt(R.id.widget_tile, "setColorFilter", tones.icon)
            decodeTile(tile.path)?.let { setImageViewBitmap(R.id.widget_tile, it) }
            setTextViewText(R.id.widget_label, tile.name)
            setInt(R.id.widget_label, "setTextColor", tones.label)
            // Launch MainActivity with the apply Uri Flutter parses. Distinct data
            // per profile → distinct PendingIntent even at the same request code.
            val intent = Intent(context, MainActivity::class.java).apply {
                action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
                data = Uri.parse("sonority://apply?homeWidget=1&id=${tile.id}")
            }
            setOnClickPendingIntent(
                R.id.tile_cell,
                PendingIntent.getActivity(
                    context, tile.id.hashCode(), intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        }
    }

    // Tiles are glyph PNGs Flutter renders at ~300·dpr px but shown at ~40dp.
    // Every tile bitmap rides in the single updateAppWidget transaction, and a
    // full-size ARGB glyph is multiple MB — decode downsampled to keep each one
    // small so a widget with many profiles stays well within the RemoteViews
    // bitmap budget (raises the practical ceiling; doesn't make it unbounded).
    private fun decodeTile(path: String): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0) return null
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= TILE_PX) sample *= 2
        return BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
    }

    // Drop the removed widgets' per-widget prefs (the shared per-profile tiles
    // stay — other widgets may use them).
    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val edit = HomeWidgetPlugin.getData(context).edit()
        appWidgetIds.forEach { id ->
            edit.remove("profileIds_$id").remove("profileId_$id")
                // cellH_/tileS_ are no longer written; clean up any left by an
                // older build when its widget is removed.
                .remove("cellH_$id").remove("tileS_$id")
        }
        edit.apply()
    }

    private data class Tile(
        val id: String, val path: String, val name: String, val colorHex: String?)

    companion object {
        private const val DEFAULT_DP = 110

        // Target decoded tile size (px); the glyph is shown at ~40dp, so a couple
        // hundred px is plenty crisp while keeping bitmap memory small.
        private const val TILE_PX = 192

        /// Row/column split that maximises the square tile side for [n] tiles in
        /// a [w]×[h] (dp) box. Mirrored in iOS `bestGrid`.
        fun bestGrid(n: Int, w: Int, h: Int): Pair<Int, Int> {
            if (n <= 1) return 1 to 1
            var best = Triple(1, n, 0.0)
            for (cols in 1..n) {
                val rows = ceil(n.toDouble() / cols).toInt()
                val side = minOf(w.toDouble() / cols, h.toDouble() / rows)
                if (side > best.third) best = Triple(cols, rows, side)
            }
            return best.first to best.second
        }
    }
}

/// The muted-tonal treatment for an accent colour — mirrors Dart `profileTonal`
/// so the widget matches the in-app tile and the iOS widget.
object ProfileTonal {
    data class Tones(val card: Int, val icon: Int, val label: Int)

    fun of(accent: Int, dark: Boolean): Tones {
        return if (dark) {
            val card = blend(accent, 0.30f, 0xFF1B1B20.toInt())
            Tones(card, ensureContrast(lerp(accent, Color.WHITE, 0.30f), card, Color.WHITE),
                0xFFECECEF.toInt())
        } else {
            val card = blend(accent, 0.14f, 0xFFFBFBFD.toInt())
            Tones(card, ensureContrast(accent, card, Color.BLACK), 0xFF1D1D22.toInt())
        }
    }

    // fg at [alpha] composited over an opaque [bg].
    private fun blend(fg: Int, alpha: Float, bg: Int) = lerp(bg, fg, alpha)

    private fun lerp(a: Int, b: Int, t: Float): Int = Color.rgb(
        (Color.red(a) + (Color.red(b) - Color.red(a)) * t).toInt().coerceIn(0, 255),
        (Color.green(a) + (Color.green(b) - Color.green(a)) * t).toInt().coerceIn(0, 255),
        (Color.blue(a) + (Color.blue(b) - Color.blue(a)) * t).toInt().coerceIn(0, 255))

    private fun ensureContrast(fg: Int, bg: Int, toward: Int): Int {
        var c = fg
        var i = 0
        while (i < 8 && contrast(c, bg) < 3.0) {
            c = lerp(c, toward, 0.12f); i++
        }
        return c
    }

    private fun contrast(a: Int, b: Int): Double {
        val la = luminance(a); val lb = luminance(b)
        val hi = maxOf(la, lb); val lo = minOf(la, lb)
        return (hi + 0.05) / (lo + 0.05)
    }

    private fun luminance(c: Int): Double {
        fun ch(v: Int): Double {
            val s = v / 255.0
            return if (s <= 0.03928) s / 12.92 else Math.pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * ch(Color.red(c)) + 0.7152 * ch(Color.green(c)) + 0.0722 * ch(Color.blue(c))
    }
}
