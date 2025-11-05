package com.rk.wallify

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log
import android.content.Intent
import android.os.Bundle
import android.graphics.BitmapFactory
import android.app.WallpaperManager
import java.io.File
import java.net.URL
import java.net.HttpURLConnection
import android.graphics.Bitmap
import android.content.Context
import androidx.work.*
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Constraints
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import java.util.concurrent.TimeUnit
import com.rk.wallify.WallpaperWorker

class MainActivity : FlutterActivity() {
    private val CHANNEL = "wallpaper_channel"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Removed service startup - using WorkManager instead
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Schedule recurring wallpaper change worker
        scheduleWallpaperChangeWorker()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "downloadAndCacheWallpaper" -> {
                    val imageUrl: String? = call.argument<String>("imageUrl")
                    if (imageUrl != null) {
                        // Use native worker for caching
                        scheduleWallpaperCacheWorker()
                        result.success("Wallpaper caching scheduled")
                    } else {
                        result.error("INVALID_URL", "Image URL is required", null)
                    }
                }
                "syncImageUrls" -> {
                    val imageUrls: List<String>? = call.argument<List<String>>("imageUrls")
                    if (imageUrls != null) {
                        saveImageUrlsToPrefs(imageUrls)
                        // Schedule immediate caching of new URLs
                        scheduleWallpaperCacheWorker()
                        val settings = getWallpaperSettings()
                        val resultMap = HashMap<String, Any?>()
                        resultMap["success"] = true
                        resultMap["wallpaperLocation"] = settings["wallpaperLocation"] ?: 1
                        resultMap["urlCount"] = imageUrls.size
                        result.success(resultMap)
                        Log.d("Wallify", "Synced ${imageUrls.size} image URLs from Flutter")
                    } else {
                        result.error("INVALID_DATA", "Image URLs list is required", null)
                    }
                }
                "downloadAndSetWallpaper" -> {
                    val imageUrl: String? = call.argument<String>("imageUrl")
                    val wallpaperLocation: Int = call.argument<Int>("wallpaperLocation") ?: 1
                    if (imageUrl != null) {
                        downloadAndSetWallpaper(imageUrl, wallpaperLocation, result)
                    } else {
                        result.error("INVALID_URL", "Image URL is required", null)
                    }
                }
                "getWallpaperLocation" -> {
                    val settings = getWallpaperSettings()
                    val resultMap = HashMap<String, Any?>()
                    resultMap["wallpaperLocation"] = settings["wallpaperLocation"] ?: 1
                    result.success(resultMap)
                }
                "setWallpaperFromFile" -> {
                    val filePath: String? = call.argument<String>("filePath")
                    val wallpaperLocation: Int = call.argument<Int>("wallpaperLocation") ?: 1
                    if (filePath != null) {
                        setWallpaperFromFile(filePath, wallpaperLocation, result)
                    } else {
                        result.error("INVALID_FILE", "File path is required", null)
                    }
                }
                "setDualWallpapers" -> {
                    val homeFilePath: String? = call.argument<String>("homeFilePath")
                    val lockFilePath: String? = call.argument<String>("lockFilePath")
                    if (homeFilePath != null && lockFilePath != null) {
                        setDualWallpapers(homeFilePath, lockFilePath, result)
                    } else {
                        result.error("INVALID_FILES", "Both home and lock file paths are required", null)
                    }
                }
                "triggerWallpaperChange" -> {
                    // Trigger immediate wallpaper change using native worker
                    triggerWallpaperChange(result)
                }
                "startCaching" -> {
                    // Start the wallpaper caching process
                    scheduleWallpaperCacheWorker()
                    result.success("Caching process started")
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun scheduleWallpaperChangeWorker() {
        try {
            Log.d("Wallify", "Scheduling wallpaper change worker...")

            // Create periodic work request for wallpaper changes (every hour when charging)
            val wallpaperWorkRequest = PeriodicWorkRequestBuilder<WallpaperWorker>(1, TimeUnit.HOURS)
                .setConstraints(
                    Constraints.Builder()
                        .setRequiresCharging(true)
                        .setRequiresBatteryNotLow(true)
                        .setRequiresStorageNotLow(true)
                        .build()
                )
                .build()

            WorkManager.getInstance(this).enqueueUniquePeriodicWork(
                WallpaperWorker.WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                wallpaperWorkRequest
            )

            Log.d("Wallify", "Scheduled wallpaper change worker for every 1 hour when charging")
        } catch (e: Exception) {
            Log.e("Wallify", "Error scheduling wallpaper worker", e)
        }
    }

    private fun scheduleWallpaperCacheWorker() {
        try {
            Log.d("Wallify", "Scheduling wallpaper cache worker...")

            // Create one-time work request for caching
            val cacheWorkRequest = OneTimeWorkRequestBuilder<WallpaperCacheWorker>()
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .setRequiresCharging(true)
                        .setRequiresBatteryNotLow(true)
                        .build()
                )
                .build()

            WorkManager.getInstance(this).enqueueUniqueWork(
                WallpaperCacheWorker.WORK_NAME,
                ExistingWorkPolicy.REPLACE,
                cacheWorkRequest
            )

            Log.d("Wallify", "Scheduled wallpaper cache worker")
        } catch (e: Exception) {
            Log.e("Wallify", "Error scheduling cache worker", e)
        }
    }

    private fun triggerWallpaperChange(result: MethodChannel.Result) {
        val workRequest = OneTimeWorkRequestBuilder<WallpaperWorker>().build()
        WorkManager.getInstance(this).enqueue(workRequest)

        workRequest.id
        result.success("Wallpaper change triggered")
        Log.d("Wallify", "Triggered immediate wallpaper change")
    }

    private fun downloadAndSetWallpaper(imageUrl: String, wallpaperLocation: Int, result: MethodChannel.Result) {
        Thread {
            try {
                Log.d("Wallify", "Starting wallpaper download: $imageUrl")

                val wallpaperManager = WallpaperManager.getInstance(this)

                fun downloadImage(url: String): File {
                    val connection = URL(url).openConnection() as HttpURLConnection
                    connection.requestMethod = "GET"
                    connection.connectTimeout = 15000
                    connection.readTimeout = 15000
                    val inputStream = connection.inputStream
                    val bytes = inputStream.readBytes()
                    inputStream.close()

                    val tempFile = File.createTempFile("wallpaper_bg_", ".jpg", cacheDir)
                    tempFile.writeBytes(bytes)
                    Log.d("Wallify", "Saved image to temp file: ${tempFile.absolutePath}")
                    return tempFile
                }

                when (wallpaperLocation) {
                    1 -> { // Lock only
                        val homeFile = downloadImage(imageUrl)
                        val homeBitmap = BitmapFactory.decodeFile(homeFile.absolutePath)
                        wallpaperManager.setBitmap(homeBitmap, null, true, WallpaperManager.FLAG_SYSTEM)
                        homeFile.delete()
                    }
                    2 -> { 
                        val lockFile = downloadImage(imageUrl)
                        val lockBitmap = BitmapFactory.decodeFile(lockFile.absolutePath)
                        wallpaperManager.setBitmap(lockBitmap, null, true, WallpaperManager.FLAG_LOCK)
                        lockFile.delete()
                    }
                    3 -> { 
                        Log.d("Wallify", "Downloading two different wallpapers for home and lock...")
                        val homeFile = downloadImage("https://source.unsplash.com/random/1080x2400/?nature")
                        val lockFile = downloadImage("https://source.unsplash.com/random/1080x2400/?abstract")

                        val homeBitmap = BitmapFactory.decodeFile(homeFile.absolutePath)
                        val lockBitmap = BitmapFactory.decodeFile(lockFile.absolutePath)

                        wallpaperManager.setBitmap(homeBitmap, null, true, WallpaperManager.FLAG_SYSTEM)
                        wallpaperManager.setBitmap(lockBitmap, null, true, WallpaperManager.FLAG_LOCK)

                        homeFile.delete()
                        lockFile.delete()

                        Log.d("Wallify", "Set different wallpapers for home and lock screens")
                    }
                }

                runOnUiThread {
                    result.success("Wallpaper(s) set successfully")
                }

            } catch (e: Exception) {
                Log.e("Wallify", "Error setting wallpaper", e)
                runOnUiThread {
                    result.error("DOWNLOAD_FAILED", e.message, null)
                }
            }
        }.start()
    }


    private fun setWallpaperFromFile(filePath: String, wallpaperLocation: Int, result: MethodChannel.Result) {
        Thread {
            try {
                Log.d("Wallify", "Setting wallpaper from cached file: $filePath")

                // Check if file exists
                val file = File(filePath)
                if (!file.exists()) {
                    Log.e("Wallify", "Cached file does not exist: $filePath")
                    runOnUiThread {
                        result.error("FILE_NOT_FOUND", "Cached file not found: $filePath", null)
                    }
                    return@Thread
                }

                Log.d("Wallify", "File exists, size: ${file.length()} bytes")

                // Set wallpaper using Android WallpaperManager
                val wallpaperManager = WallpaperManager.getInstance(this)
                val bitmap = BitmapFactory.decodeFile(file.absolutePath)

                when (wallpaperLocation) {
                    0 -> wallpaperManager.setBitmap(bitmap, null, true, WallpaperManager.FLAG_SYSTEM)
                    1 -> wallpaperManager.setBitmap(bitmap, null, true, WallpaperManager.FLAG_LOCK)
                    2 -> { // Both screens
                        wallpaperManager.setBitmap(bitmap, null, true, WallpaperManager.FLAG_SYSTEM)
                        wallpaperManager.setBitmap(bitmap, null, true, WallpaperManager.FLAG_LOCK)
                    }
                    3 -> { // Both screens (alternative value)
                        wallpaperManager.setBitmap(bitmap, null, true, WallpaperManager.FLAG_SYSTEM)
                        wallpaperManager.setBitmap(bitmap, null, true, WallpaperManager.FLAG_LOCK)
                    }
                }

                Log.d("Wallify", "Wallpaper set successfully from cached file: $filePath")

                runOnUiThread {
                    result.success("Wallpaper set successfully from cached file")
                }
            } catch (e: Exception) {
                Log.e("Wallify", "Error setting wallpaper from cached file", e)
                runOnUiThread {
                    result.error("SET_WALLPAPER_FAILED", e.message, null)
                }
            }
        }.start()
    }

    private fun setDualWallpapers(homeFilePath: String, lockFilePath: String, result: MethodChannel.Result) {
        Thread {
            try {
                Log.d("Wallify", "Setting dual wallpapers - Home: $homeFilePath, Lock: $lockFilePath")

                // Check if both files exist
                val homeFile = File(homeFilePath)
                val lockFile = File(lockFilePath)

                if (!homeFile.exists()) {
                    Log.e("Wallify", "Home wallpaper file does not exist: $homeFilePath")
                    runOnUiThread {
                        result.error("HOME_FILE_NOT_FOUND", "Home wallpaper file not found: $homeFilePath", null)
                    }
                    return@Thread
                }

                if (!lockFile.exists()) {
                    Log.e("Wallify", "Lock wallpaper file does not exist: $lockFilePath")
                    runOnUiThread {
                        result.error("LOCK_FILE_NOT_FOUND", "Lock wallpaper file not found: $lockFilePath", null)
                    }
                    return@Thread
                }

                Log.d("Wallify", "Home file exists, size: ${homeFile.length()} bytes")
                Log.d("Wallify", "Lock file exists, size: ${lockFile.length()} bytes")

                // Set wallpaper using Android WallpaperManager
                val wallpaperManager = WallpaperManager.getInstance(this)

                // Set home screen wallpaper
                val homeBitmap = BitmapFactory.decodeFile(homeFile.absolutePath)
                wallpaperManager.setBitmap(homeBitmap, null, true, WallpaperManager.FLAG_SYSTEM)

                // Set lock screen wallpaper
                val lockBitmap = BitmapFactory.decodeFile(lockFile.absolutePath)
                wallpaperManager.setBitmap(lockBitmap, null, true, WallpaperManager.FLAG_LOCK)

                Log.d("Wallify", "Dual wallpapers set successfully")

                runOnUiThread {
                    result.success("Dual wallpapers set successfully")
                }
            } catch (e: Exception) {
                Log.e("Wallify", "Error setting dual wallpapers", e)
                runOnUiThread {
                    result.error("SET_DUAL_WALLPAPERS_FAILED", e.message, null)
                }
            }
        }.start()
    }

    private fun downloadAndCacheWallpaper(imageUrl: String, result: MethodChannel.Result) {
        Thread {
            try {
                Log.d("Wallify", "Caching wallpaper: $imageUrl")
                
                // Download image
                val url = URL(imageUrl)
                val connection = url.openConnection() as HttpURLConnection
                connection.requestMethod = "GET"
                connection.connectTimeout = 15000
                connection.readTimeout = 15000
                
                val inputStream = connection.inputStream
                val bytes = inputStream.readBytes()
                inputStream.close()
                
                // Save to app's cache directory with unique name
                val cacheDir = cacheDir
                val fileName = "wallpaper_cache_${System.currentTimeMillis()}.jpg"
                val cachedFile = File(cacheDir, fileName)
                cachedFile.writeBytes(bytes)
                
                Log.d("Wallify", "Cached wallpaper to: ${cachedFile.absolutePath}")
                
                runOnUiThread {
                    result.success(cachedFile.absolutePath)
                }
            } catch (e: Exception) {
                Log.e("Wallify", "Error caching wallpaper", e)
                runOnUiThread {
                    result.error("CACHE_FAILED", e.message, null)
                }
            }
        }.start()
    }
    private fun getImageUrlsFromPrefs(): List<String> {
        val prefs = getSharedPreferences("wallify_prefs", Context.MODE_PRIVATE)
        val jsonStrings = prefs.getStringSet("imageUrls", emptySet()) ?: emptySet()
        
        // Convert JSON strings to URLs
        val urls = jsonStrings.mapNotNull { jsonString ->
            try {
                // The URLs are stored as plain strings, not JSON objects
                // So we don't need to parse JSON, just use the string directly
                jsonString.takeIf { it.isNotEmpty() && it.startsWith("http") }
            } catch (e: Exception) {
                Log.e("Wallify", "Error parsing URL: $jsonString", e)
                null
            }
        }
        
        Log.d("Wallify", "Retrieved ${urls.size} image URLs from preferences (parsed from ${jsonStrings.size} JSON objects)")
        return urls
    }

    private fun saveImageUrlsToPrefs(urls: List<String>) {
        val prefs = getSharedPreferences("wallify_prefs", Context.MODE_PRIVATE)
        prefs.edit().putStringSet("imageUrls", urls.toSet()).apply()
    }

    private fun getWallpaperSettings(): Map<String, Any?> {
        val prefs = getSharedPreferences("wallify_prefs", Context.MODE_PRIVATE)
        return mapOf(
            "wallpaperLocation" to prefs.getInt("wallpaperLocation", 1)
        )
    }
}