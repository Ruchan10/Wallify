package com.rk.wallify

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews
import kotlin.random.Random

class QuickToggleWidget : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            val views = buildRemoteViews(context)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_SET_LOCATION -> {
                val location = intent.getIntExtra(EXTRA_LOCATION, 3)
                val prefs = WidgetUtils.getPrefs(context)
                prefs.edit().putInt("flutter.wallpaperLocation", location).apply()
                triggerUpdate(context)
            }
            ACTION_CHANGE_NOW -> {
                Thread {
                    WallpaperUtils.downloadAndSetWallpaperBackground(context, isManual = true)
                    triggerUpdate(context)
                }.start()
            }
            ACTION_RANDOM_LOCATION -> {
                val loc = Random.nextInt(1, 4)
                val prefs = WidgetUtils.getPrefs(context)
                prefs.edit().putInt("flutter.wallpaperLocation", loc).apply()
                triggerUpdate(context)
            }
        }
    }

    private fun buildRemoteViews(context: Context): RemoteViews {
        val prefs = WidgetUtils.getPrefs(context)
        val location = prefs.all["flutter.wallpaperLocation"]?.let {
            when (it) {
                is Int -> it; is Long -> it.toInt(); is String -> it.toIntOrNull(); else -> null
            }
        } ?: 3
        val interval = prefs.all["flutter.wallpaper_interval"]?.let {
            when (it) {
                is Int -> it; is Long -> it.toInt(); is String -> it.toIntOrNull(); else -> null
            }
        } ?: 60
        val autoEnabled = prefs.getBoolean("flutter.autoWallpaperEnabled", false)
        val lastChangeStr = prefs.getString("flutter.lastWallpaperChange", null)
        val source = prefs.getString("flutter.wallpaperSource", "internet") ?: "internet"
        val sourceLabel = source.split(",").joinToString(", ") { it.replaceFirstChar { c -> c.uppercase() } }

        val views = RemoteViews(context.packageName, R.layout.widget_quick_toggle)
        WidgetUtils.applyDynamicColors(views, prefs)
        applyLocationStyles(views, location)
        views.setTextViewText(R.id.tv_countdown, WidgetUtils.getLastChangeText(prefs, autoEnabled, interval))
        views.setTextViewText(R.id.tv_source_value, sourceLabel)

        val flags = WidgetUtils.getFlags()
        views.setOnClickPendingIntent(R.id.option_home, buildLocationIntent(context, 1, flags))
        views.setOnClickPendingIntent(R.id.option_lock, buildLocationIntent(context, 2, flags))
        views.setOnClickPendingIntent(R.id.option_both, buildLocationIntent(context, 3, flags))
        views.setOnClickPendingIntent(R.id.btn_change_now, buildChangeNowIntent(context, flags))
        views.setOnClickPendingIntent(R.id.btn_auto_toggle, buildRandomLocationIntent(context, flags))
        views.setOnClickPendingIntent(R.id.widget_root, WidgetUtils.buildOpenAppIntent(context, 100))
        return views
    }

    private fun applyLocationStyles(views: RemoteViews, location: Int) {
        val sel = "#FFFFFFFF"
        val unsel = "#70FFFFFF"
        views.setTextColor(R.id.option_home, android.graphics.Color.parseColor(if (location == 1) sel else unsel))
        views.setTextColor(R.id.option_lock, android.graphics.Color.parseColor(if (location == 2) sel else unsel))
        views.setTextColor(R.id.option_both, android.graphics.Color.parseColor(if (location == 3) sel else unsel))
    }

    private fun buildLocationIntent(context: Context, location: Int, flags: Int): PendingIntent {
        val intent = Intent(context, QuickToggleWidget::class.java).apply {
            action = ACTION_SET_LOCATION
            putExtra(EXTRA_LOCATION, location)
        }
        return PendingIntent.getBroadcast(context, REQ_LOCATION_BASE + location, intent, flags)
    }

    private fun buildChangeNowIntent(context: Context, flags: Int): PendingIntent {
        val intent = Intent(context, QuickToggleWidget::class.java).apply {
            action = ACTION_CHANGE_NOW
        }
        return PendingIntent.getBroadcast(context, REQ_CHANGE_NOW, intent, flags)
    }

    private fun buildRandomLocationIntent(context: Context, flags: Int): PendingIntent {
        val intent = Intent(context, QuickToggleWidget::class.java).apply {
            action = ACTION_RANDOM_LOCATION
        }
        return PendingIntent.getBroadcast(context, REQ_RANDOM_LOCATION, intent, flags)
    }

    companion object {
        const val ACTION_SET_LOCATION = "com.rk.wallify.qt.ACTION_SET_LOCATION"
        const val ACTION_CHANGE_NOW = "com.rk.wallify.qt.ACTION_CHANGE_NOW"
        const val ACTION_RANDOM_LOCATION = "com.rk.wallify.qt.ACTION_RANDOM_LOCATION"
        const val EXTRA_LOCATION = "location"
        private const val REQ_LOCATION_BASE = 0
        private const val REQ_CHANGE_NOW = 10
        private const val REQ_RANDOM_LOCATION = 20

        fun triggerUpdate(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, QuickToggleWidget::class.java)
            val ids = appWidgetManager.getAppWidgetIds(component)
            if (ids.isNotEmpty()) {
                val intent = Intent(context, QuickToggleWidget::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                context.sendBroadcast(intent)
            }
        }
    }
}
