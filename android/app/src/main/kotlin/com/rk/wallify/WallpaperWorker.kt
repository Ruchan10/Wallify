package com.rk.wallify

import android.app.WallpaperManager
import android.content.Context
import android.graphics.BitmapFactory
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.ListenableWorker.Result
import java.io.File
import java.util.*

class WallpaperWorker(context: Context, workerParams: WorkerParameters) : Worker(context, workerParams) {

    init {
        Log.d("WallpaperWorker", "WallpaperWorker instance created")
    }

    override fun doWork(): Result {
        return try {
            Log.d("WallpaperWorker", "Starting wallpaper change work")

            // Get cached wallpaper files
            val cachedFiles = getCachedWallpaperFiles()
            Log.d("WallpaperWorker", "Found ${cachedFiles.size} cached wallpaper files")

            if (cachedFiles.isEmpty()) {
                Log.w("WallpaperWorker", "No cached wallpaper files found")
                return Result.success()
            }

            // Debug: List all found files
            cachedFiles.forEach { file ->
                Log.d("WallpaperWorker", "Found cached file: ${file.name} (${file.length()} bytes)")
            }

            // Limit to prevent processing too many files
            val filesToProcess = cachedFiles.take(20)
            Log.d("WallpaperWorker", "Processing ${filesToProcess.size} files (limited for performance)")

            // Get wallpaper location preference
            val wallpaperLocation = getWallpaperLocation()
            Log.d("WallpaperWorker", "Wallpaper location: $wallpaperLocation")

            when (wallpaperLocation) {
                0 -> setRandomWallpaper(filesToProcess, WallpaperManager.FLAG_SYSTEM) // Home screen only
                1 -> setRandomWallpaper(filesToProcess, WallpaperManager.FLAG_LOCK) // Lock screen only
                2, 3 -> setDualWallpapers(filesToProcess) // Both screens with different wallpapers
                else -> setRandomWallpaper(filesToProcess, WallpaperManager.FLAG_SYSTEM)
            }

            Log.d("WallpaperWorker", "Wallpaper change completed successfully")
            Result.success()

        } catch (e: Exception) {
            Log.e("WallpaperWorker", "Error in wallpaper worker", e)
            Result.failure()
        }
    }

    private fun getCachedWallpaperFiles(): List<File> {
        val cacheDir = applicationContext.cacheDir
        return cacheDir.listFiles { file ->
            file.name.startsWith("wallpaper_cache_") && file.extension == "jpg"
        }?.sortedBy { it.lastModified() }?.toList() ?: emptyList()
    }

    private fun getWallpaperLocation(): Int {
        val prefs = applicationContext.getSharedPreferences("wallify_prefs", Context.MODE_PRIVATE)
        return prefs.getInt("wallpaperLocation", 1) // Default to lock screen
    }

    private fun setRandomWallpaper(cachedFiles: List<File>, flag: Int) {
        if (cachedFiles.isEmpty()) return

        val randomFile = cachedFiles.random()
        Log.d("WallpaperWorker", "Setting wallpaper from: ${randomFile.name}")

        try {
            val wallpaperManager = WallpaperManager.getInstance(applicationContext)
            val bitmap = BitmapFactory.decodeFile(randomFile.absolutePath)
            wallpaperManager.setBitmap(bitmap, null, true, flag)
            Log.d("WallpaperWorker", "Wallpaper set successfully for flag: $flag")
        } catch (e: Exception) {
            Log.e("WallpaperWorker", "Error setting wallpaper", e)
        }
    }

    private fun setDualWallpapers(cachedFiles: List<File>) {
        if (cachedFiles.size < 2) {
            Log.w("WallpaperWorker", "Not enough cached files for dual wallpapers, using single")
            setRandomWallpaper(cachedFiles, WallpaperManager.FLAG_LOCK) // Use lock screen as fallback
            return
        }

        val random = Random()
        val homeIndex = random.nextInt(cachedFiles.size)
        var lockIndex = random.nextInt(cachedFiles.size)

        // Ensure different files for home and lock screens
        while (lockIndex == homeIndex) {
            lockIndex = random.nextInt(cachedFiles.size)
        }

        val homeFile = cachedFiles[homeIndex]
        val lockFile = cachedFiles[lockIndex]

        Log.d("WallpaperWorker", "Setting dual wallpapers - Home: ${homeFile.name}, Lock: ${lockFile.name}")

        try {
            val wallpaperManager = WallpaperManager.getInstance(applicationContext)

            // Set home screen wallpaper
            val homeBitmap = BitmapFactory.decodeFile(homeFile.absolutePath)
            wallpaperManager.setBitmap(homeBitmap, null, true, WallpaperManager.FLAG_SYSTEM)

            // Set lock screen wallpaper
            val lockBitmap = BitmapFactory.decodeFile(lockFile.absolutePath)
            wallpaperManager.setBitmap(lockBitmap, null, true, WallpaperManager.FLAG_LOCK)

            Log.d("WallpaperWorker", "Dual wallpapers set successfully")
        } catch (e: Exception) {
            Log.e("WallpaperWorker", "Error setting dual wallpapers", e)
        }
    }

    companion object {
        const val WORK_NAME = "wallpaper_change_work"
    }
}
