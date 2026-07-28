package com.rk.wallify

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.widget.RemoteViews
import java.io.File

class CurrentWallpaperWidget : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            val views = buildRemoteViews(context)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun buildRemoteViews(context: Context): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_current_wallpaper)
        val prefs = WidgetUtils.getPrefs(context)

        val wallpaperFile = File(context.filesDir, "live_wallpaper.jpg")
        if (wallpaperFile.exists()) {
            try {
                val bm = BitmapFactory.decodeFile(wallpaperFile.absolutePath)
                if (bm != null) {
                    val scaled = android.graphics.Bitmap.createScaledBitmap(bm, 360, 640, true)
                    views.setImageViewBitmap(R.id.iv_current_wallpaper, scaled)
                    if (bm !== scaled) bm.recycle()
                }
            } catch (_: Exception) { }
        }

        val source = prefs.getString("flutter.wallpaperSource", "internet") ?: "internet"
        val sourceLabel = source.split(",").joinToString(", ") { it.replaceFirstChar { c -> c.uppercase() } }
        views.setTextViewText(R.id.tv_wallpaper_source, sourceLabel)

        val lastChange = prefs.getString("flutter.lastWallpaperChange", null)
        views.setTextViewText(R.id.tv_last_changed, lastChange ?: "No changes yet")

        views.setOnClickPendingIntent(R.id.widget_root, WidgetUtils.buildOpenAppIntent(context, 0))
        return views
    }

    companion object {
        fun triggerUpdate(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, CurrentWallpaperWidget::class.java)
            val ids = appWidgetManager.getAppWidgetIds(component)
            if (ids.isNotEmpty()) {
                val intent = Intent(context, CurrentWallpaperWidget::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                context.sendBroadcast(intent)
            }
        }
    }
}
