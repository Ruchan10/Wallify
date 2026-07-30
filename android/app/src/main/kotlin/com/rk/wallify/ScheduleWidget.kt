package com.rk.wallify

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.*

class ScheduleWidget : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            val views = buildRemoteViews(context)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun buildRemoteViews(context: Context): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_schedule)
        val prefs = WidgetUtils.getPrefs(context)
        WidgetUtils.applyDynamicColors(views, prefs)
        WidgetUtils.applyDynamicProgressTint(views, prefs, R.id.progress_bar)

        val interval = prefs.all["flutter.wallpaper_interval"]?.let {
            when (it) {
                is Int -> it; is Long -> it.toInt(); is String -> it.toIntOrNull(); else -> null
            }
        } ?: 60

        val autoEnabled = prefs.getBoolean("flutter.autoWallpaperEnabled", false)
        val lastChangeStr = prefs.getString("flutter.lastWallpaperChange", null)

        val fmt = SimpleDateFormat("MMM d, h:mm a", Locale.getDefault())

        if (autoEnabled && lastChangeStr != null) {
            try {
                val parseFmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
                val lastChange = parseFmt.parse(lastChangeStr)
                if (lastChange != null) {
                    val now = System.currentTimeMillis()
                    val totalInterval = interval * 60_000L
                    val nextChange = lastChange.time + totalInterval
                    val elapsed = now - lastChange.time
                    val progress = ((elapsed.toFloat() / totalInterval) * 100).toInt().coerceIn(0, 100)

                    views.setProgressBar(R.id.progress_bar, 100, progress, false)
                    views.setTextViewText(R.id.tv_last_time, fmt.format(lastChange))
                    views.setTextViewText(R.id.tv_next_time, fmt.format(Date(nextChange)))

                    val remaining = nextChange - now
                    val status = when {
                        remaining <= 0 -> "Change due any minute"
                        remaining < 60_000 -> "Change due any minute"
                        else -> {
                            val mins = (remaining / 60_000).toInt()
                            if (mins >= 60) {
                                "Next change in ${mins / 60}h ${mins % 60}m"
                            } else {
                                "Next change in $mins min"
                            }
                        }
                    }
                    views.setTextViewText(R.id.tv_status, status)
                } else {
                    setDefaultState(views, interval)
                }
            } catch (_: Exception) {
                setDefaultState(views, interval)
            }
        } else {
            setDefaultState(views, interval)
        }

        views.setOnClickPendingIntent(R.id.widget_root, WidgetUtils.buildOpenAppIntent(context, 0))
        return views
    }

    private fun setDefaultState(views: RemoteViews, interval: Int) {
        views.setProgressBar(R.id.progress_bar, 100, 0, false)
        views.setTextViewText(R.id.tv_last_time, "--")
        views.setTextViewText(R.id.tv_next_time, "--")
        views.setTextViewText(R.id.tv_status, "Auto change is off")
    }

    companion object {
        fun triggerUpdate(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, ScheduleWidget::class.java)
            val ids = appWidgetManager.getAppWidgetIds(component)
            if (ids.isNotEmpty()) {
                val intent = Intent(context, ScheduleWidget::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                context.sendBroadcast(intent)
            }
        }
    }
}
