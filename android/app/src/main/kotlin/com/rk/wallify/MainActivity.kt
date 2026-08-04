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
import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.MediaStore
import android.provider.Settings
import androidx.work.*
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Constraints
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import java.util.concurrent.TimeUnit
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {
    private val CHANNEL = "wallpaper_channel"
    private var methodChannel: MethodChannel? = null
    private var pendingNavigation: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val shortcutAction = intent?.getStringExtra("shortcut_action")
        if (shortcutAction != null) {
            when (shortcutAction) {
                "change_now" -> {
                    Thread {
                        WallpaperUtils.downloadAndSetWallpaperBackground(applicationContext)
                    }.start()
                }
                "favorites" -> {
                    pendingNavigation = "favorites"
                    sendNavigationToFlutter()
                }
            }
        }
        val nav = intent?.getStringExtra("navigate_to")
        if (nav != null) {
            pendingNavigation = nav
            sendNavigationToFlutter()
        }
    }

    private fun sendNavigationToFlutter() {
        val nav = pendingNavigation ?: return
        val tab = when (nav) {
            "favorites" -> 1
            "history" -> 2
            "settings" -> 3
            else -> 0
        }
        methodChannel?.invokeMethod("navigateTo", tab)
        pendingNavigation = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "scheduleBackgroundWallpaperWorker" -> {
                        scheduleBackgroundWallpaperWorker()
                        result.success("Scheduled wallpaper background worker from Flutter")
                    }
                    "cancelBackgroundWallpaperWorker" -> {
                        WorkManagerExt.cancelAutoChange(this@MainActivity)
                        result.success("Cancelled wallpaper background worker")
                    }
                    "scheduleBackgroundWallpaperWorkerNow" -> {
                        lifecycleScope.launch(Dispatchers.IO) {
                            try {
                                WallpaperUtils.downloadAndSetWallpaperBackground(applicationContext)
                                result.success("✅ Wallpaper changed successfully")
                            } catch (e: Exception) {
                                result.error("ERROR", e.message, null)
                            }
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
                    "setDualWallpapers" -> {
                        val homeFilePath: String? = call.argument<String>("homeFilePath")
                        val lockFilePath: String? = call.argument<String>("lockFilePath")
                        if (homeFilePath != null && lockFilePath != null) {
                            setDualWallpapers(homeFilePath, lockFilePath, result)
                        } else {
                            result.error("INVALID_FILES", "Both home and lock file paths are required", null)
                        }
                    }
                    "extractWallpaperColors" -> {
                        val filePath: String? = call.argument<String>("filePath")
                        if (filePath != null) {
                            val colors = WallpaperUtils.extractColorsFromFile(applicationContext, filePath)
                            if (colors.isNotEmpty()) {
                                result.success(colors)
                            } else {
                                result.error("EXTRACT_FAILED", "Could not extract colors from image", null)
                            }
                        } else {
                            result.error("INVALID_PATH", "File path is required", null)
                        }
                    }
                    "checkImageHasFace" -> {
                        val filePath: String? = call.argument<String>("filePath")
                        if (filePath != null) {
                            val bitmap = BitmapFactory.decodeFile(filePath)
                            if (bitmap != null) {
                                val hasFace = WallpaperUtils.imageHasFace(applicationContext, bitmap)
                                result.success(hasFace)
                            } else {
                                result.success(false)
                            }
                        } else {
                            result.success(false)
                        }
                    }
                    "detectFocusPoint" -> {
                        val filePath: String? = call.argument<String>("filePath")
                        if (filePath != null) {
                            val bitmap = BitmapFactory.decodeFile(filePath)
                            if (bitmap != null) {
                                val focus = WallpaperUtils.detectFocusPoint(applicationContext, bitmap)
                                result.success(focus)
                            } else {
                                result.success(mapOf("x" to 0f, "y" to 0f, "source" to 0f))
                            }
                        } else {
                            result.success(mapOf("x" to 0f, "y" to 0f, "source" to 0f))
                        }
                    }
                    "saveToDownloads" -> {
                        val filePath: String? = call.argument<String>("filePath")
                        val fileName: String? = call.argument<String>("fileName")
                        val subDir: String? = call.argument<String>("subdirectory")
                        if (filePath != null && fileName != null) {
                            val savedUri = saveToPublicDownloads(filePath, fileName, subDir)
                            if (savedUri != null) {
                                result.success(savedUri)
                            } else {
                                result.error("SAVE_FAILED", "Could not save to public Downloads folder", null)
                            }
                        } else {
                            result.error("INVALID_ARGS", "filePath and fileName are required", null)
                        }
                    }
                    "getWorkerLogs" -> {
                        val logs = WorkerLogger.getLogs(this@MainActivity)
                        result.success(logs.map { mapOf(
                            "ts" to (it["ts"] ?: ""),
                            "level" to (it["level"] ?: ""),
                            "tag" to (it["tag"] ?: ""),
                            "msg" to (it["msg"] ?: "")
                        ) })
                    }
                    "clearWorkerLogs" -> {
                        WorkerLogger.clearLogs(this@MainActivity)
                        result.success("Logs cleared")
                    }
                    "updateWidget" -> {
                        StatsWidget.triggerUpdate(this@MainActivity)
                        QuickToggleWidget.triggerUpdate(this@MainActivity)
                        ScheduleWidget.triggerUpdate(this@MainActivity)
                        result.success("All widgets updated")
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                            try {
                                startActivity(
                                    Intent(
                                        Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                        Uri.parse("package:$packageName")
                                    )
                                )
                            } catch (e: Exception) {
                                result.error("REQUEST_FAILED", e.message, null)
                                return@setMethodCallHandler
                            }
                        }
                        result.success(true)
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
        }
        sendNavigationToFlutter()
    }

    private fun scheduleBackgroundWallpaperWorker() {
        WorkManagerExt.scheduleAutoChange(this)
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
        lifecycleScope.launch(Dispatchers.IO) {
            try {
                Log.d("Wallify", "Setting dual wallpapers - Home: $homeFilePath, Lock: $lockFilePath")

                val homeFile = File(homeFilePath)
                val lockFile = File(lockFilePath)

                if (!homeFile.exists()) {
                    Log.e("Wallify", "Home wallpaper file does not exist: $homeFilePath")
                    withContext(Dispatchers.Main) {
                        result.error("HOME_FILE_NOT_FOUND", "Home wallpaper file not found: $homeFilePath", null)
                    }
                    return@launch
                }

                if (!lockFile.exists()) {
                    Log.e("Wallify", "Lock wallpaper file does not exist: $lockFilePath")
                    withContext(Dispatchers.Main) {
                        result.error("LOCK_FILE_NOT_FOUND", "Lock wallpaper file not found: $lockFilePath", null)
                    }
                    return@launch
                }

                Log.d("Wallify", "Home file exists, size: ${homeFile.length()} bytes")
                Log.d("Wallify", "Lock file exists, size: ${lockFile.length()} bytes")

                val wallpaperManager = WallpaperManager.getInstance(this@MainActivity)

                val homeBitmap = BitmapFactory.decodeFile(homeFile.absolutePath)
                wallpaperManager.setBitmap(homeBitmap, null, true, WallpaperManager.FLAG_SYSTEM)

                val lockBitmap = BitmapFactory.decodeFile(lockFile.absolutePath)
                wallpaperManager.setBitmap(lockBitmap, null, true, WallpaperManager.FLAG_LOCK)

                Log.d("Wallify", "Dual wallpapers set successfully")

                withContext(Dispatchers.Main) {
                    result.success("Dual wallpapers set successfully")
                }
            } catch (e: Exception) {
                Log.e("Wallify", "Error setting dual wallpapers", e)
                withContext(Dispatchers.Main) {
                    result.error("SET_DUAL_WALLPAPERS_FAILED", e.message, null)
                }
            }
        }
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

    private fun saveToPublicDownloads(filePath: String, fileName: String, subdirectory: String? = null): String? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val contentValues = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                    put(MediaStore.Downloads.MIME_TYPE, getMimeType(fileName))
                    put(MediaStore.Downloads.IS_PENDING, 1)
                    if (subdirectory != null) {
                        put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/$subdirectory")
                    }
                }
                val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                if (uri != null) {
                    contentResolver.openOutputStream(uri)?.use { output ->
                        java.io.File(filePath).inputStream().use { input ->
                            input.copyTo(output)
                        }
                    }
                    contentValues.clear()
                    contentValues.put(MediaStore.Downloads.IS_PENDING, 0)
                    contentResolver.update(uri, contentValues, null, null)
                    uri.toString()
                } else null
            } else {
                val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                val targetDir = if (subdirectory != null) java.io.File(downloadsDir, subdirectory) else downloadsDir
                targetDir.mkdirs()
                val destFile = java.io.File(targetDir, fileName)
                java.io.File(filePath).copyTo(destFile, overwrite = true)
                destFile.absolutePath
            }
        } catch (e: Exception) {
            Log.e("Wallify", "Failed to save to public Downloads: ${e.message}", e)
            null
        }
    }

    private fun getMimeType(fileName: String): String {
        return when {
            fileName.endsWith(".jpg") || fileName.endsWith(".jpeg") -> "image/jpeg"
            fileName.endsWith(".png") -> "image/png"
            fileName.endsWith(".json") -> "application/json"
            fileName.endsWith(".webp") -> "image/webp"
            else -> "application/octet-stream"
        }
    }

fun downloadAndSetWallpaper(imageUrl: String, wallpaperLocation: Int, result: MethodChannel.Result) {
    lifecycleScope.launch(Dispatchers.IO) {
        try {
            val resolved = if (wallpaperLocation == 4) {
                val pick = (1..3).random()
                Log.d("Wallify", "Auto mode: randomly picked $pick")
                pick
            } else {
                wallpaperLocation
            }
            Log.d("Wallify", "Starting wallpaper download for location $wallpaperLocation (resolved: $resolved)")

            val wallpaperManager = WallpaperManager.getInstance(this@MainActivity)

            if (resolved == 3) {
                val urls = getImageUrlsFromPrefs()

                if (urls.size < 2) {
                    Log.e("Wallify", "Not enough cached URLs for dual wallpapers, using same one")
                    setWallpaperFromSingleUrl(imageUrl, wallpaperManager, WallpaperManager.FLAG_SYSTEM)
                    setWallpaperFromSingleUrl(imageUrl, wallpaperManager, WallpaperManager.FLAG_LOCK)
                } else {
                    val shuffled = urls.shuffled()
                    val homeUrl = shuffled[0]
                    val lockUrl = shuffled[1]

                    Log.d("Wallify", "Dual wallpaper mode: home=$homeUrl, lock=$lockUrl")

                    setWallpaperFromSingleUrl(homeUrl, wallpaperManager, WallpaperManager.FLAG_SYSTEM)
                    setWallpaperFromSingleUrl(lockUrl, wallpaperManager, WallpaperManager.FLAG_LOCK)
                }

                withContext(Dispatchers.Main) {
                    result.success("Dual wallpapers set successfully")
                }
                return@launch
            }

            setWallpaperFromSingleUrl(imageUrl, wallpaperManager, when (wallpaperLocation) {
                0 -> WallpaperManager.FLAG_SYSTEM
                1 -> WallpaperManager.FLAG_LOCK
                else -> WallpaperManager.FLAG_SYSTEM
            })

            withContext(Dispatchers.Main) {
                result.success("Wallpaper set successfully for location $wallpaperLocation")
            }

        } catch (e: Exception) {
            Log.e("Wallify", "Error setting wallpaper", e)
            withContext(Dispatchers.Main) {
                result.error("DOWNLOAD_FAILED", e.message, null)
            }
        }
    }
}
}
