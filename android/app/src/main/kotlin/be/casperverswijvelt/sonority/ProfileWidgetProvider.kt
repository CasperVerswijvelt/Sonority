package be.casperverswijvelt.sonority

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// Home-screen widget showing one configured profile. The whole tile (profile
/// colour + glyph + name) is rendered to a square PNG in Flutter and shown
/// `fitCenter`, so it's always the largest square that fits the widget's space.
/// A tap launches the app with `sonority://apply?homeWidget=1&id=<profileId>`,
/// which Flutter routes into the apply flow. Per-widget data (the tile image +
/// profile id) is written from Dart (keyed by widgetId) via home_widget.
class ProfileWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { id ->
            val tilePath = widgetData.getString("tile_$id", null)
            val profileId = widgetData.getString("profileId_$id", null)

            val views = RemoteViews(context.packageName, R.layout.profile_widget).apply {
                tilePath?.let { path ->
                    BitmapFactory.decodeFile(path)?.let { setImageViewBitmap(R.id.widget_tile, it) }
                }
                // Canonical shape shared with iOS; home_widget's iOS isWidgetUrl
                // requires the homeWidget marker, Dart reads only `id`.
                val uri = profileId?.let { Uri.parse("sonority://apply?homeWidget=1&id=$it") }
                val pendingIntent =
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, uri)
                setOnClickPendingIntent(R.id.widget_tile, pendingIntent)
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
