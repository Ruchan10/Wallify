package com.rk.wallify

import android.content.Context
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters

class WallpaperBackgroundWorker(context: Context, workerParams: WorkerParameters) : Worker(context, workerParams) {

    override fun doWork(): Result {
        return try {
            Log.d("Wallify", "🕒 WallpaperBackgroundWorker triggered")
            WallpaperUtils.downloadAndSetWallpaperBackground(applicationContext)
            Log.d("Wallify", "✅ WallpaperBackgroundWorker finished successfully")
            Result.success()
        } catch (e: Exception) {
            Log.e("Wallify", "❌ Error in WallpaperBackgroundWorker", e)
            Result.retry()
        }
    }

    companion object {
        const val WORK_NAME = "wallify_background_wallpaper_work"
    }
}
