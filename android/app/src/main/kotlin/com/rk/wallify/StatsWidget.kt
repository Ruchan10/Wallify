package com.rk.wallify

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class StatsWidget : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            val views = buildRemoteViews(context)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun buildRemoteViews(context: Context): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_stats)
        val prefs = WidgetUtils.getPrefs(context)
        WidgetUtils.applyDynamicColors(views, prefs)

        val totalChanges = prefs.getInt("flutter.totalWallpaperChanges", 0)
        views.setTextViewText(R.id.tv_total_changes, totalChanges.toString())

        val interval = prefs.all["flutter.wallpaper_interval"]?.let {
            when (it) {
                is Int -> it
                is Long -> it.toInt()
                is String -> it.toIntOrNull()
                else -> null
            }
        } ?: 60
        views.setTextViewText(R.id.tv_interval, "${interval}m")

        val autoEnabled = prefs.getBoolean("flutter.autoWallpaperEnabled", false)
        views.setTextViewText(R.id.tv_auto_status, if (autoEnabled) "ON" else "OFF")

        views.setOnClickPendingIntent(R.id.widget_root, WidgetUtils.buildOpenAppIntent(context, 0))
        return views
    }

    companion object {
        fun triggerUpdate(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, StatsWidget::class.java)
            val ids = appWidgetManager.getAppWidgetIds(component)
            if (ids.isNotEmpty()) {
                val intent = Intent(context, StatsWidget::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                context.sendBroadcast(intent)
            }
        }
    }
}
