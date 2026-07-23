package com.rk.wallify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class PowerConnectionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        Log.d("Wallify", "PowerConnectionReceiver received action: $action")

        when (action) {
            Intent.ACTION_POWER_CONNECTED -> {
                WorkerLogger.i(context, "PowerReceiver", "Device plugged in detected")
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val autoEnabled = prefs.getBoolean("flutter.autoWallpaperEnabled", false)

                if (!autoEnabled) {
                    WorkerLogger.i(context, "PowerReceiver", "Auto wallpaper is disabled, ignoring plug-in event")
                    return
                }

                CoroutineScope(Dispatchers.IO).launch {
                    val (met, reason) = WallpaperUtils.checkConstraints(context)
                    if (met) {
                        WorkerLogger.i(context, "PowerReceiver", "Device plugged in & all constraints met. Triggering wallpaper change!")
                        val workRequest = OneTimeWorkRequestBuilder<WallpaperBackgroundWorker>().build()
                        WorkManager.getInstance(context).enqueueUniqueWork(
                            "wallify_power_connected_work",
                            ExistingWorkPolicy.REPLACE,
                            workRequest
                        )
                    } else {
                        WorkerLogger.w(context, "PowerReceiver", "Device plugged in, but constraints not met: $reason")
                    }
                }
            }

            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                WorkerLogger.i(context, "PowerReceiver", "System boot or package update completed")
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val autoEnabled = prefs.getBoolean("flutter.autoWallpaperEnabled", false)
                if (autoEnabled) {
                    WorkManagerExt.scheduleAutoChange(context)
                }
            }
        }
    }
}
