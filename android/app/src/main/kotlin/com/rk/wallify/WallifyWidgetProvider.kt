package com.rk.wallify

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class WallifyWidgetProvider : AppWidgetProvider() {

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
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.edit().putInt("flutter.wallpaperLocation", location).apply()
                Log.d(TAG, "Widget: location set to $location")
                triggerUpdate(context)
            }

            ACTION_CHANGE_NOW -> {
                Log.d(TAG, "Widget: change now triggered")
                Thread {
                    WallpaperUtils.downloadAndSetWallpaperBackground(context)
                    triggerUpdate(context)
                }.start()
            }
        }
    }

    private fun buildRemoteViews(context: Context): RemoteViews {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val location = prefs.all["flutter.wallpaperLocation"]?.let {
            when (it) {
                is Int -> it
                is Long -> it.toInt()
                is String -> it.toIntOrNull()
                else -> null
            }
        } ?: 3

        val interval = prefs.all["flutter.wallpaper_interval"]?.let {
            when (it) {
                is Int -> it
                is Long -> it.toInt()
                is String -> it.toIntOrNull()
                else -> null
            }
        } ?: 60

        val autoEnabled = prefs.getBoolean("flutter.autoWallpaperEnabled", false)
        val lastChangeStr = prefs.getString("flutter.lastWallpaperChange", null)

        val views = RemoteViews(context.packageName, R.layout.widget_layout)
        applyLocationStyles(views, location)
        applyCountdownText(views, autoEnabled, lastChangeStr, interval)
        applyClickHandlers(context, views, location)
        return views
    }

    private fun applyLocationStyles(views: RemoteViews, location: Int) {
        val selectedAlpha = "#FFFFFFFF"
        val unselectedAlpha = "#70FFFFFF"

        val homeColor = if (location == 1) selectedAlpha else unselectedAlpha
        val lockColor = if (location == 2) selectedAlpha else unselectedAlpha
        val bothColor = if (location == 3) selectedAlpha else unselectedAlpha

        views.setTextColor(R.id.option_home, android.graphics.Color.parseColor(homeColor))
        views.setTextColor(R.id.option_lock, android.graphics.Color.parseColor(lockColor))
        views.setTextColor(R.id.option_both, android.graphics.Color.parseColor(bothColor))
    }

    private fun applyCountdownText(views: RemoteViews, autoEnabled: Boolean, lastChangeStr: String?, intervalMinutes: Int) {
        val text = if (!autoEnabled) {
            "Auto change is off"
        } else if (lastChangeStr == null) {
            "Next change in $intervalMinutes min"
        } else {
            try {
                val fmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
                val lastChange = fmt.parse(lastChangeStr)
                if (lastChange != null) {
                    val nextChange = lastChange.time + intervalMinutes * 60_000L
                    val remaining = nextChange - System.currentTimeMillis()
                    if (remaining <= 0) {
                        "Change due any minute"
                    } else {
                        val mins = (remaining / 60_000).toInt()
                        if (mins >= 60) {
                            val hrs = mins / 60
                            val remMins = mins % 60
                            "Next change in ${hrs}h ${remMins}m"
                        } else {
                            "Next change in $mins min"
                        }
                    }
                } else {
                    "Next change in $intervalMinutes min"
                }
            } catch (e: Exception) {
                "Next change in $intervalMinutes min"
            }
        }
        views.setTextViewText(R.id.tv_countdown, text)
    }

    private fun applyClickHandlers(context: Context, views: RemoteViews, currentLocation: Int) {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        views.setOnClickPendingIntent(R.id.option_home, buildLocationIntent(context, 1, flags))
        views.setOnClickPendingIntent(R.id.option_lock, buildLocationIntent(context, 2, flags))
        views.setOnClickPendingIntent(R.id.option_both, buildLocationIntent(context, 3, flags))
        views.setOnClickPendingIntent(R.id.btn_change_now, buildChangeNowIntent(context, flags))
    }

    private fun buildLocationIntent(context: Context, location: Int, flags: Int): PendingIntent {
        val intent = Intent(context, WallifyWidgetProvider::class.java).apply {
            action = ACTION_SET_LOCATION
            putExtra(EXTRA_LOCATION, location)
        }
        return PendingIntent.getBroadcast(context, REQ_LOCATION_BASE + location, intent, flags)
    }

    private fun buildChangeNowIntent(context: Context, flags: Int): PendingIntent {
        val intent = Intent(context, WallifyWidgetProvider::class.java).apply {
            action = ACTION_CHANGE_NOW
        }
        return PendingIntent.getBroadcast(context, REQ_CHANGE_NOW, intent, flags)
    }

    companion object {
        private const val TAG = "WallifyWidget"
        private const val PREFS_NAME = "FlutterSharedPreferences"

        const val ACTION_SET_LOCATION = "com.rk.wallify.ACTION_SET_LOCATION"
        const val ACTION_CHANGE_NOW = "com.rk.wallify.ACTION_CHANGE_NOW"
        const val EXTRA_LOCATION = "location"
        private const val REQ_LOCATION_BASE = 100
        private const val REQ_CHANGE_NOW = 200

        fun triggerUpdate(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, WallifyWidgetProvider::class.java)
            val ids = appWidgetManager.getAppWidgetIds(component)
            if (ids.isNotEmpty()) {
                val intent = Intent(context, WallifyWidgetProvider::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                context.sendBroadcast(intent)
            }
        }
    }
}
