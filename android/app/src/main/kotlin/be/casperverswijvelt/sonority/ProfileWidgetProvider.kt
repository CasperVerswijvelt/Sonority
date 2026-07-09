package be.casperverswijvelt.sonority

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import kotlin.math.ceil

/// Home-screen widget showing a user-picked SET of profiles as a grid of square
/// tiles, each independently tap-to-apply. Tiles are rendered to square PNGs in
/// Flutter (keyed `tile_<profileId>`); this provider wires a GridView collection
/// (see [ProfileTileRemoteViewsService]), picks the row/column split that makes
/// the tiles the largest possible squares for the current widget size, and
/// centres the grid. Per tile, a fill-in intent launches
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

    // Re-pack the grid when the user resizes the widget.
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
        val count = maxOf(1, readWidgetProfileIds(prefs, id).size)

        // Current size in dp (portrait: MIN_WIDTH = width, MAX_HEIGHT = height).
        val opts = mgr.getAppWidgetOptions(id)
        val wDp = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH).takeIf { it > 0 } ?: DEFAULT_DP
        val hDp = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT).takeIf { it > 0 } ?: DEFAULT_DP
        val (cols, rows) = bestGrid(count, wDp, hDp)
        // Tiles fill their cells so the grid fills the widget with a uniform
        // GAP_DP on every edge and between tiles (cells may be slightly
        // non-square). The factory reads cellH to size each tile's height.
        val cellW = maxOf(MIN_CELL_DP, (wDp - (cols + 1) * GAP_DP) / cols)
        val cellH = maxOf(MIN_CELL_DP, (hDp - (rows + 1) * GAP_DP) / rows)
        // Short edge drives the glyph/label sizes (see ProfileTileFactory), so the
        // grid matches the iOS widget's spec.
        prefs.edit()
            .putInt("cellH_$id", cellH)
            .putInt("tileS_$id", minOf(cellW, cellH))
            .apply()

        val views = RemoteViews(context.packageName, R.layout.profile_widget)

        // Collection adapter. The unique data Uri per widget id is REQUIRED —
        // without it every placed widget shares one factory and shows the same
        // tiles.
        val serviceIntent = Intent(context, ProfileTileRemoteViewsService::class.java).apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            data = Uri.fromParts("widget", id.toString(), null)
        }
        views.setRemoteAdapter(R.id.grid, serviceIntent)
        views.setEmptyView(R.id.grid, R.id.empty)
        views.setInt(R.id.grid, "setNumColumns", cols)
        val density = context.resources.displayMetrics.density
        views.setInt(R.id.grid, "setColumnWidth", (cellW * density).toInt())

        // Uniform GAP_DP between tiles on both axes (horizontal/verticalSpacing in
        // XML) and as the outer margin (padding, px). Cells fill, so the leftover
        // per axis works out to one GAP_DP on each edge.
        val contentWpx = ((cols * cellW + (cols - 1) * GAP_DP) * density).toInt()
        val contentHpx = ((rows * cellH + (rows - 1) * GAP_DP) * density).toInt()
        val hPad = maxOf(0, ((wDp * density).toInt() - contentWpx) / 2)
        val vPad = maxOf(0, ((hDp * density).toInt() - contentHpx) / 2)
        views.setViewPadding(R.id.grid, hPad, vPad, hPad, vPad)

        // Template must be MUTABLE and carry NO data so each item's fill-in can
        // supply its own `id=` Uri.
        val template = Intent(context, MainActivity::class.java).apply {
            action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            flags = flags or PendingIntent.FLAG_MUTABLE
        }
        views.setPendingIntentTemplate(
            R.id.grid, PendingIntent.getActivity(context, id, template, flags))

        // The empty state says "Tap to pick profiles" — make that true: tapping
        // it opens this widget's configure screen.
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
        // Force the factory to re-read (tile set / sizes may have changed).
        mgr.notifyAppWidgetViewDataChanged(id, R.id.grid)
    }

    // Drop the removed widgets' per-widget prefs (the shared per-profile tiles
    // stay — other widgets may use them).
    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val edit = HomeWidgetPlugin.getData(context).edit()
        appWidgetIds.forEach { id ->
            edit.remove("profileIds_$id").remove("profileId_$id")
                .remove("cellH_$id").remove("tileS_$id")
        }
        edit.apply()
    }

    companion object {
        private const val GAP_DP = 8
        private const val MIN_CELL_DP = 24
        private const val DEFAULT_DP = 110

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
