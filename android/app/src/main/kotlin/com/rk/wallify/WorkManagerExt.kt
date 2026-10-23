package com.rk.wallify

import android.content.Context
import android.content.SharedPreferences
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit

object WorkManagerExt {

    /** Changes asked for from the widget, the notification and the app shortcut. */
    private const val MANUAL_WORK_NAME = "wallify_manual_change"

    /** The auto change interval in minutes, at least WorkManager's minimum of 15. */
    fun intervalMinutes(prefs: SharedPreferences): Int {
        val intervalValue = prefs.all["flutter.wallpaper_interval"]
        return when (intervalValue) {
            is Int -> intervalValue
            is Long -> intervalValue.toInt()
            is String -> intervalValue.toIntOrNull()
            else -> null
        }?.coerceAtLeast(15) ?: 60
    }

    fun scheduleAutoChange(context: Context, forceReset: Boolean = false) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val autoEnabled = prefs.getBoolean("flutter.autoWallpaperEnabled", false)
        if (!autoEnabled && !forceReset) {
            return
        }

        val intervalMinutes = intervalMinutes(prefs)

        val requiresBatteryNotLow = prefs.getBoolean("flutter.constraint_battery_not_low", false)
        val requiresStorageNotLow = prefs.getBoolean("flutter.constraint_storage_not_low", false)
        val sources = (prefs.getString("flutter.wallpaperSource", "toppicks") ?: "toppicks")
            .split(",").map { it.trim() }.filter { it.isNotEmpty() }.toSet()

        // The Charging constraint is checked by the worker, as "plugged in". The
        // WorkManager one only counts the battery actually filling, so it held
        // changes back while battery protection kept the charge at 80-85%, and
        // stopped a running change (to be run again) whenever charging paused.
        val constraints = Constraints.Builder()
            .setRequiresBatteryNotLow(requiresBatteryNotLow)
            .setRequiresStorageNotLow(requiresStorageNotLow)
            .setRequiredNetworkType(
                if (sources == setOf("folder")) NetworkType.NOT_REQUIRED else NetworkType.CONNECTED
            )
            .build()

        val request = PeriodicWorkRequestBuilder<WallpaperBackgroundWorker>(
            intervalMinutes.toLong(), TimeUnit.MINUTES
        )
            .setConstraints(constraints)
            .build()

        val policy = if (forceReset) {
            ExistingPeriodicWorkPolicy.CANCEL_AND_REENQUEUE
        } else {
            ExistingPeriodicWorkPolicy.UPDATE
        }

        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            WallpaperBackgroundWorker.WORK_NAME,
            policy,
            request
        )
        WorkerLogger.i(context, "WorkManager", "Periodic auto wallpaper scheduled (interval=${intervalMinutes}m, policy=$policy)")
    }

    fun cancelAutoChange(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(WallpaperBackgroundWorker.WORK_NAME)
        WorkerLogger.i(context, "WorkManager", "Cancelled periodic auto wallpaper work")
    }

    /**
     * Changes the wallpaper now. Through WorkManager rather than a plain thread:
     * once the receiver that started a thread returns, Android may freeze or kill
     * the process mid-change. Taps while one is still pending are dropped.
     */
    fun changeNow(context: Context) {
        val request = OneTimeWorkRequestBuilder<WallpaperBackgroundWorker>()
            .setInputData(workDataOf(WallpaperBackgroundWorker.KEY_MANUAL to true))
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(
            MANUAL_WORK_NAME,
            ExistingWorkPolicy.KEEP,
            request
        )
        WorkerLogger.i(context, "WorkManager", "Manual wallpaper change requested")
    }
}
