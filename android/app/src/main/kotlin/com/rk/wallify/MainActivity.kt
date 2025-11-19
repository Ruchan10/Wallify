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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    private val CHANNEL = "wallpaper_channel"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Removed service startup - using WorkManager instead
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleBackgroundWallpaperWorker" -> {
                    scheduleBackgroundWallpaperWorker()
                    result.success("Scheduled wallpaper background worker from Flutter")
                }
                "scheduleBackgroundWallpaperWorkerNow" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            WallpaperUtils.downloadAndSetWallpaperBackground(applicationContext)
                            result.success("✅ Wallpaper changed successfully")
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                }
           
                "downloadAndCacheWallpaper" -> {
                    val imageUrl: String? = call.argument<String>("imageUrl")
                    if (imageUrl != null) {
                        result.success("Wallpaper caching scheduled")
                    } else {
                        result.error("INVALID_URL", "Image URL is required", null)
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
                "setDualWallpapers" -> {
                    val homeFilePath: String? = call.argument<String>("homeFilePath")
                    val lockFilePath: String? = call.argument<String>("lockFilePath")
                    if (homeFilePath != null && lockFilePath != null) {
                        setDualWallpapers(homeFilePath, lockFilePath, result)
                    } else {
                        result.error("INVALID_FILES", "Both home and lock file paths are required", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    fun downloadAndSetWallpaperBackground(context: Context) {
        try {
            Log.d("Wallify", "Starting background wallpaper change (no Flutter)")

            // 1️⃣ Get preferences
            val prefs = context.getSharedPreferences("wallify_prefs", Context.MODE_PRIVATE)
            val imageUrls = prefs.getStringSet("imageUrls", emptySet())?.toList() ?: emptyList()
            val wallpaperLocation = prefs.getInt("wallpaperLocation", 1)

            if (imageUrls.isEmpty()) {
                Log.w("Wallify", "No image URLs found in SharedPreferences")
                return
            }

            // 2️⃣ Pick a random image URL
            val randomUrl = imageUrls.random()
            Log.d("Wallify", "Selected random URL for wallpaper: $randomUrl, location: $wallpaperLocation")

            // 3️⃣ Call the existing wallpaper setter (reuse your current method)
            val mainActivity = MainActivity()
            mainActivity.attachBaseContext(context)
            mainActivity.downloadAndSetWallpaper(randomUrl, wallpaperLocation,
                object : io.flutter.plugin.common.MethodChannel.Result {
                    override fun success(result: Any?) {
                        Log.d("Wallify", "Wallpaper set successfully in background: $result")
                    }

                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        Log.e("Wallify", "Error setting wallpaper in background: $errorMessage")
                    }

                    override fun notImplemented() {
                        Log.w("Wallify", "Method not implemented")
                    }
                }
            )

        } catch (e: Exception) {
            Log.e("Wallify", "Error in background wallpaper change", e)
        }
    }

    private fun scheduleBackgroundWallpaperWorker() {
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val intervalValue = prefs.all["flutter.wallpaper_interval"]
            val requiresCharging = prefs.getBoolean("flutter.constraint_charging", true)
            val requiresBatteryNotLow = prefs.getBoolean("flutter.constraint_battery", false)
            val requiresStorageNotLow = prefs.getBoolean("flutter.constraint_storage", false)
            val requireIdle = prefs.getBoolean("flutter.constraint_idle", false)

            val intervalMinutes = when (intervalValue) {
                is Int -> intervalValue
                is Long -> intervalValue.toInt()
                is String -> intervalValue.toIntOrNull() ?: 60
                else -> 60
            }.coerceAtLeast(15) 

            Log.d("Wallify", "Scheduling background wallpaper change every $intervalMinutes minutes")
            Log.d("Wallify", "Scheduling background wallpaper change every $requiresCharging requiresCharging")
            Log.d("Wallify", "Scheduling background wallpaper change every $requiresBatteryNotLow requiresBatteryNotLow")
            Log.d("Wallify", "Scheduling background wallpaper change every $requiresStorageNotLow requiresStorageNotLow")
            Log.d("Wallify", "Scheduling background wallpaper change every $requireIdle requireIdle")

            val wallpaperBackgroundRequest =
                PeriodicWorkRequestBuilder<WallpaperBackgroundWorker>(
                    intervalMinutes.toLong(), TimeUnit.MINUTES 
                )
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .setRequiresBatteryNotLow(false)
                        .setRequiresStorageNotLow(false)
                        .setRequiresDeviceIdle(false)
                        .build()
                )
                .build()

            WorkManager.getInstance(this).enqueueUniquePeriodicWork(
                WallpaperBackgroundWorker.WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                wallpaperBackgroundRequest
            )

        } catch (e: Exception) {
            Log.e("Wallify", "Error scheduling background wallpaper worker", e)
        }
    }

    private fun setWallpaperFromSingleUrl(urlString: String, wallpaperManager: WallpaperManager, flag: Int) {
        try {
            Log.d("Wallify", "Downloading image for wallpaper ($flag): $urlString")

            val url = URL(urlString)
            val connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = "GET"
            connection.connectTimeout = 15000
            connection.readTimeout = 15000

            val inputStream = connection.inputStream
            val bytes = inputStream.readBytes()
            inputStream.close()

            val tempFile = File.createTempFile("wallpaper_temp_", ".jpg", cacheDir)
            tempFile.writeBytes(bytes)

            val bitmap = BitmapFactory.decodeFile(tempFile.absolutePath)
            wallpaperManager.setBitmap(bitmap, null, true, flag)

            Log.d("Wallify", "Wallpaper set from $urlString for flag $flag")

            tempFile.delete()
        } catch (e: Exception) {
            Log.e("Wallify", "Error setting wallpaper from $urlString", e)
        }
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



fun downloadAndSetWallpaper(imageUrl: String, wallpaperLocation: Int, result: MethodChannel.Result) {
    Thread {
        try {
            Log.d("Wallify", "Starting wallpaper download for location $wallpaperLocation")

            val wallpaperManager = WallpaperManager.getInstance(this)

            if (wallpaperLocation == 3) {
                val urls = getImageUrlsFromPrefs()

                if (urls.size < 2) {
                    Log.e("Wallify", "Not enough cached URLs for dual wallpapers, using same one")
                    // fallback to single wallpaper
                    setWallpaperFromSingleUrl(imageUrl, wallpaperManager, WallpaperManager.FLAG_SYSTEM)
                    setWallpaperFromSingleUrl(imageUrl, wallpaperManager, WallpaperManager.FLAG_LOCK)
                } else {
                    // pick two different random URLs
                    val shuffled = urls.shuffled()
                    val homeUrl = shuffled[0]
                    val lockUrl = shuffled[1]

                    Log.d("Wallify", "Dual wallpaper mode: home=$homeUrl, lock=$lockUrl")

                    // Set each wallpaper separately
                    setWallpaperFromSingleUrl(homeUrl, wallpaperManager, WallpaperManager.FLAG_SYSTEM)
                    setWallpaperFromSingleUrl(lockUrl, wallpaperManager, WallpaperManager.FLAG_LOCK)
                }

                runOnUiThread {
                    result.success("Dual wallpapers set successfully")
                }
                return@Thread
            }

            // 🧱 Otherwise, just download one wallpaper normally
            setWallpaperFromSingleUrl(imageUrl, wallpaperManager, when (wallpaperLocation) {
                0 -> WallpaperManager.FLAG_SYSTEM
                1 -> WallpaperManager.FLAG_LOCK
                else -> WallpaperManager.FLAG_SYSTEM
            })

            runOnUiThread {
                result.success("Wallpaper set successfully for location $wallpaperLocation")
            }

        } catch (e: Exception) {
            Log.e("Wallify", "Error setting wallpaper", e)
            runOnUiThread {
                result.error("DOWNLOAD_FAILED", e.message, null)
            }
        }
    }.start()
}
}
