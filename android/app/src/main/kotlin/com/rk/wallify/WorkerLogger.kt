package com.rk.wallify

import android.content.Context
import android.util.Log

/**
 * Background worker logging, sent to Logcat (`adb logcat -s Wallify`).
 *
 * Logs used to be persisted to SharedPreferences for an in-app viewer. That
 * viewer is gone, so nothing is stored any more and entries left behind by
 * older versions are deleted the first time anything is logged.
 */
object WorkerLogger {
    private const val LOG_TAG = "Wallify"
    private const val LEGACY_PREFS_NAME = "FlutterSharedPreferences"
    private const val LEGACY_LOG_KEY = "worker_logs"

    @Volatile
    private var legacyLogsCleared = false

    fun i(context: Context, tag: String, message: String) = log(context, Log.INFO, tag, message)
    fun w(context: Context, tag: String, message: String) = log(context, Log.WARN, tag, message)
    fun e(context: Context, tag: String, message: String) = log(context, Log.ERROR, tag, message)

    private fun log(context: Context, priority: Int, tag: String, message: String) {
        Log.println(priority, LOG_TAG, "[$tag] $message")
        clearLegacyLogs(context)
    }

    private fun clearLegacyLogs(context: Context) {
        if (legacyLogsCleared) return
        legacyLogsCleared = true
        try {
            val prefs = context.getSharedPreferences(LEGACY_PREFS_NAME, Context.MODE_PRIVATE)
            if (prefs.contains(LEGACY_LOG_KEY)) {
                prefs.edit().remove(LEGACY_LOG_KEY).apply()
            }
        } catch (_: Exception) {
        }
    }
}
