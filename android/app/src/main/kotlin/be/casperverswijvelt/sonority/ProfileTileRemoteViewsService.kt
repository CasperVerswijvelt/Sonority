package be.casperverswijvelt.sonority

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.BitmapFactory
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.util.TypedValue
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray

/// The widget's ordered profile ids: the JSON list, or the pre-multi-profile
/// single-id key (lazy migration of widgets placed before this feature). Shared
/// by [ProfileWidgetProvider] (to size the grid) and the factory below.
fun readWidgetProfileIds(prefs: SharedPreferences, widgetId: Int): List<String> {
    prefs.getString("profileIds_$widgetId", null)?.let { raw ->
        return try {
            val arr = JSONArray(raw)
            List(arr.length()) { arr.getString(it) }
        } catch (_: Exception) {
            emptyList()
        }
    }
    return prefs.getString("profileId_$widgetId", null)?.let { listOf(it) } ?: emptyList()
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

/// Backs the [ProfileWidgetProvider] GridView: one tonal tile per chosen profile
/// (rounded card tinted to the accent, the accent-tinted glyph, and a native
/// label). Reads the ordered id list + per-profile glyph PNG / colour / name from
/// the home_widget shared prefs (written by Dart), and gives each tile a fill-in
/// intent carrying its own profile id so a tap applies THAT profile.
class ProfileTileRemoteViewsService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        ProfileTileFactory(applicationContext, intent)
}

private class ProfileTileFactory(
    private val context: Context,
    intent: Intent,
) : RemoteViewsService.RemoteViewsFactory {
    private val widgetId = intent.getIntExtra(
        AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)

    private data class Tile(
        val id: String, val path: String, val name: String, val colorHex: String?)

    private var items: List<Tile> = emptyList()
    private var cellH = 72
    private var tileS = 72

    override fun onCreate() {}

    override fun onDataSetChanged() {
        val prefs = HomeWidgetPlugin.getData(context)
        cellH = prefs.getInt("cellH_$widgetId", 72)
        tileS = prefs.getInt("tileS_$widgetId", 72)
        items = readWidgetProfileIds(prefs, widgetId).mapNotNull { id ->
            prefs.getString("tile_$id", null)?.let { path ->
                Tile(id, path, prefs.getString("tileName_$id", "") ?: "",
                    prefs.getString("tileColor_$id", null))
            }
        }
    }

    override fun onDestroy() {}
    override fun getCount() = items.size
    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount() = 1
    override fun getItemId(position: Int) = position.toLong()
    override fun hasStableIds() = true

    override fun getViewAt(position: Int): RemoteViews {
        val tile = items[position]
        val accent = tile.colorHex?.let { runCatching { Color.parseColor(it) }.getOrNull() }
            ?: Color.GRAY
        val dark = (context.resources.configuration.uiMode and
            Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        val tones = ProfileTonal.of(accent, dark)
        val glyphDp = (0.30f * tileS).coerceIn(18f, 40f)
        val labelSp = (0.12f * tileS).coerceIn(11f, 15f)

        return RemoteViews(context.packageName, R.layout.profile_tile_item).apply {
            // Card fill + accent-tinted glyph (the PNG is white → tinted here).
            setInt(R.id.tile_bg, "setColorFilter", tones.card)
            setInt(R.id.widget_tile, "setColorFilter", tones.icon)
            BitmapFactory.decodeFile(tile.path)?.let { setImageViewBitmap(R.id.widget_tile, it) }
            // Label: text, colour, and size (matches the iOS spec).
            setTextViewText(R.id.widget_label, tile.name)
            setInt(R.id.widget_label, "setTextColor", tones.label)
            setTextViewTextSize(R.id.widget_label, TypedValue.COMPLEX_UNIT_SP, labelSp)
            // Cell height + glyph size (API 31+; below, the layout defaults apply).
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                setViewLayoutHeight(R.id.tile_cell, cellH.toFloat(), TypedValue.COMPLEX_UNIT_DIP)
                setViewLayoutWidth(R.id.widget_tile, glyphDp, TypedValue.COMPLEX_UNIT_DIP)
                setViewLayoutHeight(R.id.widget_tile, glyphDp, TypedValue.COMPLEX_UNIT_DIP)
            }
            // Id in the fill-in DATA Uri (not an extra): makes each fill-in
            // filterEquals-distinct and, merged over the no-data template, yields
            // action=LAUNCH + data=…id=<id> — the shape Flutter parses.
            setOnClickFillInIntent(
                R.id.tile_cell,
                Intent().apply { data = Uri.parse("sonority://apply?homeWidget=1&id=${tile.id}") })
        }
    }
}
