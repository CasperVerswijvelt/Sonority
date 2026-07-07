package be.casperverswijvelt.sonority

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// Home-screen widget showing one configured profile (avatar + name); a tap
/// launches the app with `sonority://apply?id=<profileId>`, which Flutter routes
/// into the apply flow. Per-widget data is written from Dart (keyed by widgetId)
/// via home_widget.
class ProfileWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { id ->
            val name = widgetData.getString("profileName_$id", null) ?: "Tap to set up"
            val profileId = widgetData.getString("profileId_$id", null)
            val avatarPath = widgetData.getString("avatar_$id", null)

            val views = RemoteViews(context.packageName, R.layout.profile_widget).apply {
                setTextViewText(R.id.widget_name, name)
                avatarPath?.let { path ->
                    BitmapFactory.decodeFile(path)?.let { setImageViewBitmap(R.id.widget_avatar, it) }
                }
                val uri = profileId?.let { Uri.parse("sonority://apply?id=$it") }
                val pendingIntent =
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, uri)
                setOnClickPendingIntent(R.id.widget_container, pendingIntent)
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
