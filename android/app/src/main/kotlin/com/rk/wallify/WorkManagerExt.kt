package com.rk.wallify

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

object WorkManagerExt {

    fun scheduleAutoChange(context: Context) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val intervalValue = prefs.all["flutter.wallpaper_interval"]
        val intervalMinutes = when (intervalValue) {
            is Int -> intervalValue
            is Long -> intervalValue.toInt()
            is String -> intervalValue.toIntOrNull()
            else -> null
        }?.coerceAtLeast(15) ?: 60

        val requiresCharging = prefs.getBoolean("flutter.constraint_charging", true)
        val requiresBatteryNotLow = prefs.getBoolean("flutter.constraint_battery_not_low", false)
        val requiresStorageNotLow = prefs.getBoolean("flutter.constraint_storage_not_low", false)
        val requiresWifi = prefs.getBoolean("flutter.constraint_wifi", false)

        val constraints = Constraints.Builder()
            .setRequiresBatteryNotLow(requiresBatteryNotLow)
            .setRequiresStorageNotLow(requiresStorageNotLow)
            .setRequiresCharging(requiresCharging)
            .apply {
                if (requiresWifi) {
                    setRequiredNetworkType(NetworkType.UNMETERED)
                } else {
                    setRequiredNetworkType(NetworkType.CONNECTED)
                }
            }
            .build()

        val request = PeriodicWorkRequestBuilder<WallpaperBackgroundWorker>(
            intervalMinutes.toLong(), TimeUnit.MINUTES
        )
            .setInitialDelay(1, TimeUnit.MINUTES)
            .setConstraints(constraints)
            .build()

        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            WallpaperBackgroundWorker.WORK_NAME,
            ExistingPeriodicWorkPolicy.CANCEL_AND_REENQUEUE,
            request
        )
    }

    fun cancelAutoChange(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(WallpaperBackgroundWorker.WORK_NAME)
    }
}
