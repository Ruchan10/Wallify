package com.rk.wallify

import android.content.Context
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.workDataOf

class WallpaperBackgroundWorker(context: Context, workerParams: WorkerParameters) : Worker(context, workerParams) {

    override fun doWork(): Result {
        val ctx = applicationContext
        val manual = inputData.getBoolean(KEY_MANUAL, false)
        WorkerLogger.i(ctx, "Worker", "Worker triggered by WorkManager (manual=$manual, attempt=$runAttemptCount)")
        return try {
            Log.d("Wallify", "WallpaperBackgroundWorker triggered")
            // When the system stops this run (a constraint went away, time ran out),
            // WorkManager runs the work again later, so this run must not apply a
            // wallpaper too. doWork keeps running after a stop unless it checks.
            val result = WallpaperUtils.downloadAndSetWallpaperBackground(ctx, isManual = manual) { isStopped }
            WorkerLogger.i(ctx, "Worker", "Wallpaper change finished: $result")
            Log.d("Wallify", "WallpaperBackgroundWorker finished: $result")
            Result.success(workDataOf(KEY_RESULT to result.name))
        } catch (e: Exception) {
            WorkerLogger.e(ctx, "Worker", "Error: ${e.message}")
            Log.e("Wallify", "Error in WallpaperBackgroundWorker", e)
            Result.retry()
        }
    }

    override fun onStopped() {
        WorkerLogger.w(applicationContext, "Worker", "Stopped by the system (reason=$stopReason)")
    }

    companion object {
        const val WORK_NAME = "wallify_background_wallpaper_work"
        const val KEY_MANUAL = "manual"
        const val KEY_RESULT = "result"
    }
}
