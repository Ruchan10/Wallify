package com.rk.wallify

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

object WidgetUtils {
    const val PREFS_NAME = "FlutterSharedPreferences"
    const val EXTRA_NAVIGATE_TO = "navigate_to"

    fun getFlags(): Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    } else {
        PendingIntent.FLAG_UPDATE_CURRENT
    }

    fun buildOpenAppIntent(context: Context, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_NAVIGATE_TO, "settings")
        }
        return PendingIntent.getActivity(context, requestCode, intent, getFlags())
    }

    fun getPrefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun getLastChangeText(prefs: android.content.SharedPreferences, autoEnabled: Boolean, intervalMinutes: Int): String {
        val lastChangeStr = prefs.getString("flutter.lastWallpaperChange", null)
        return if (!autoEnabled) {
            "Auto change is off"
        } else if (lastChangeStr == null) {
            "Next change in $intervalMinutes min"
        } else {
            try {
                val fmt = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault())
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
                            "Next in ${hrs}h ${remMins}m"
                        } else {
                            "Next in $mins min"
                        }
                    }
                } else {
                    "Next change in $intervalMinutes min"
                }
            } catch (_: Exception) {
                "Next change in $intervalMinutes min"
            }
        }
    }
}
