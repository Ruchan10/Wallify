package com.rk.wallify

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.WallpaperManager
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import android.util.Log
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import kotlin.random.Random
import org.json.JSONArray
import java.util.*
import java.text.SimpleDateFormat
import androidx.core.graphics.scale
import android.graphics.Bitmap
import org.json.JSONObject
import androidx.palette.graphics.Palette
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.objectdetector.ObjectDetector
import com.google.mediapipe.tasks.vision.objectdetector.ObjectDetector.ObjectDetectorOptions
import com.google.mediapipe.tasks.vision.facedetector.FaceDetector
import com.google.mediapipe.tasks.vision.facedetector.FaceDetector.FaceDetectorOptions
import android.graphics.RectF

object WallpaperUtils {
    private val imageExtensions = setOf("jpg", "jpeg", "png", "webp", "bmp", "gif")

    private var cachedObjectDetector: ObjectDetector? = null
    private var cachedFaceDetector: FaceDetector? = null
    private var objectDetectorFailed = false
    private var faceDetectorFailed = false

    private const val FOCUS_TAG = "FocusDetect"
    private const val DETECTION_MAX_DIM = 1280

    /** Logs to logcat and to the in-app worker log screen. */
    private fun focusLog(context: Context, message: String) {
        Log.d(FOCUS_TAG, message)
        WorkerLogger.i(context, FOCUS_TAG, message)
    }

    /**
     * Real screen size in physical pixels, portrait-oriented. Falls back to the
     * values stored by the Flutter side, then to 1080x1920.
     */
    internal fun getScreenSize(context: Context): Pair<Int, Int> {
        try {
            val dm = context.getSystemService(Context.DISPLAY_SERVICE) as android.hardware.display.DisplayManager
            val display = dm.getDisplay(android.view.Display.DEFAULT_DISPLAY)
            val metrics = android.util.DisplayMetrics()
            @Suppress("DEPRECATION")
            display.getRealMetrics(metrics)
            if (metrics.widthPixels > 0 && metrics.heightPixels > 0) {
                return Pair(
                    minOf(metrics.widthPixels, metrics.heightPixels),
                    maxOf(metrics.widthPixels, metrics.heightPixels)
                )
            }
        } catch (e: Exception) {
            WorkerLogger.w(context, FOCUS_TAG, "Could not read display metrics: ${e.message}")
        }

        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        fun readInt(key: String): Int? = when (val v = prefs.all[key]) {
            is Int -> v
            is Long -> v.toInt()
            is String -> v.toIntOrNull()
            else -> null
        }
        val w = readInt("flutter.deviceWidth")
        val h = readInt("flutter.deviceHeight")
        if (w != null && h != null && w > 0 && h > 0) {
            WorkerLogger.w(context, FOCUS_TAG, "Using saved screen size ${w}x$h")
            return Pair(minOf(w, h), maxOf(w, h))
        }
        WorkerLogger.w(context, FOCUS_TAG, "Screen size unknown, defaulting to 1080x1920")
        return Pair(1080, 1920)
    }

    private fun getObjectDetector(context: Context): ObjectDetector? {
        if (objectDetectorFailed) return null
        if (cachedObjectDetector == null) {
            try {
                val baseOptions = BaseOptions.builder()
                    .setModelAssetPath("efficientdet_lite0.tflite")
                    .build()
                val options = ObjectDetectorOptions.builder()
                    .setBaseOptions(baseOptions)
                    .setMaxResults(5)
                    .setScoreThreshold(0.3f)
                    .setRunningMode(RunningMode.IMAGE)
                    .build()
                cachedObjectDetector = ObjectDetector.createFromOptions(context, options)
                focusLog(context, "Object detector model loaded")
            } catch (e: Throwable) {
                WorkerLogger.e(context, FOCUS_TAG, "Object detector not available: ${e.message}")
                Log.w("Wallify", "Object detector not available: ${e.message}")
                objectDetectorFailed = true
                return null
            }
        }
        return cachedObjectDetector
    }

    private fun getFaceDetector(context: Context): FaceDetector? {
        if (faceDetectorFailed) return null
        if (cachedFaceDetector == null) {
            try {
                val baseOptions = BaseOptions.builder()
                    .setModelAssetPath("blaze_face_short_range.tflite")
                    .build()
                val options = FaceDetectorOptions.builder()
                    .setBaseOptions(baseOptions)
                    .setMinDetectionConfidence(0.5f)
                    .setRunningMode(RunningMode.IMAGE)
                    .build()
                cachedFaceDetector = FaceDetector.createFromOptions(context, options)
                focusLog(context, "Face detector model loaded")
            } catch (e: Throwable) {
                WorkerLogger.e(context, FOCUS_TAG, "Face detector not available: ${e.message}")
                Log.w("Wallify", "Face detector not available: ${e.message}")
                faceDetectorFailed = true
                return null
            }
        }
        return cachedFaceDetector
    }

    fun checkConstraints(context: Context): Pair<Boolean, String> {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        val autoEnabled = prefs.getBoolean("flutter.autoWallpaperEnabled", false)
        if (!autoEnabled) {
            return Pair(false, "Auto wallpaper is disabled")
        }

        val requiresCharging = prefs.getBoolean("flutter.constraint_charging", false)
        if (requiresCharging && !isDeviceCharging(context)) {
            return Pair(false, "Device is not charging")
        }

        val requiresBatteryNotLow = prefs.getBoolean("flutter.constraint_battery_not_low", false)
        if (requiresBatteryNotLow && !isBatteryNotLow(context)) {
            return Pair(false, "Battery level is low (<15%)")
        }

        val requiresStorageNotLow = prefs.getBoolean("flutter.constraint_storage_not_low", false)
        if (requiresStorageNotLow && !isStorageNotLow(context)) {
            return Pair(false, "Storage space is low (<100MB free)")
        }

        val requiresWifi = prefs.getBoolean("flutter.constraint_wifi", false)
        if (requiresWifi && !isWifiConnected(context)) {
            return Pair(false, "Not connected to Wi-Fi")
        }

        val scheduleEnabled = prefs.getBoolean("flutter.scheduleEnabled", false)
        if (scheduleEnabled) {
            val calendar = Calendar.getInstance()
            val today = calendar.get(Calendar.DAY_OF_WEEK)
            val dayMap = mapOf(
                Calendar.MONDAY to 1, Calendar.TUESDAY to 2, Calendar.WEDNESDAY to 3,
                Calendar.THURSDAY to 4, Calendar.FRIDAY to 5, Calendar.SATURDAY to 6,
                Calendar.SUNDAY to 7
            )
            val currentDayNum = dayMap[today] ?: 0
            val daysJson = prefs.getString("flutter.scheduleDays", null)
            if (daysJson != null) {
                val allowedDays = try {
                    JSONArray(daysJson).let { arr ->
                        (0 until arr.length()).map { arr.getInt(it) }.toSet()
                    }
                } catch (_: Exception) { emptySet() }
                if (allowedDays.isNotEmpty() && currentDayNum !in allowedDays) {
                    val dayNames = listOf("", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
                    return Pair(false, "Today (${dayNames.getOrElse(currentDayNum) { "?" }}) is not in schedule")
                }
            }

            val startHour = prefs.getInt("flutter.scheduleStartHour", 6)
            val endHour = prefs.getInt("flutter.scheduleEndHour", 22)
            val currentHour = calendar.get(Calendar.HOUR_OF_DAY)
            if (currentHour < startHour) {
                return Pair(false, "Too early (${currentHour}h) — schedule starts at ${startHour}h")
            }
            if (currentHour >= endHour) {
                return Pair(false, "Too late (${currentHour}h) — schedule ends at ${endHour}h")
            }
        }

        val allowedSsidsJson = prefs.getString("flutter.allowedSsids", null)
        if (!allowedSsidsJson.isNullOrBlank()) {
            val allowed = try {
                val arr = org.json.JSONArray(allowedSsidsJson)
                (0 until arr.length()).map { arr.getString(it).trim() }.toSet()
            } catch (_: Exception) { emptySet() }
            if (allowed.isNotEmpty()) {
                val wifiManager = context.getSystemService(Context.WIFI_SERVICE) as? android.net.wifi.WifiManager
                val currentSsid = wifiManager?.connectionInfo?.ssid?.trim('"') ?: ""
                if (currentSsid !in allowed) {
                    return Pair(false, "SSID '$currentSsid' not in allowed list")
                }
            }
        }

        return Pair(true, "All constraints met")
    }

    fun isDeviceCharging(context: Context): Boolean {
        return try {
            val intent = context.registerReceiver(null, android.content.IntentFilter(android.content.Intent.ACTION_BATTERY_CHANGED))
            val status = intent?.getIntExtra(android.os.BatteryManager.EXTRA_STATUS, -1) ?: -1
            status == android.os.BatteryManager.BATTERY_STATUS_CHARGING || status == android.os.BatteryManager.BATTERY_STATUS_FULL
        } catch (e: Exception) {
            true
        }
    }

    fun isBatteryNotLow(context: Context): Boolean {
        return try {
            val intent = context.registerReceiver(null, android.content.IntentFilter(android.content.Intent.ACTION_BATTERY_CHANGED))
            val level = intent?.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = intent?.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, -1) ?: -1
            if (level >= 0 && scale > 0) {
                val pct = (level * 100) / scale.toFloat()
                pct >= 15f
            } else {
                true
            }
        } catch (e: Exception) {
            true
        }
    }

    fun isStorageNotLow(context: Context): Boolean {
        return try {
            val stat = android.os.StatFs(context.filesDir.path)
            val availableBytes = stat.availableBlocksLong * stat.blockSizeLong
            availableBytes > 100 * 1024 * 1024
        } catch (e: Exception) {
            true
        }
    }

    fun isWifiConnected(context: Context): Boolean {
        return try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? android.net.ConnectivityManager
            val network = cm?.activeNetwork ?: return false
            val caps = cm.getNetworkCapabilities(network) ?: return false
            caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI) ||
            caps.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
        } catch (e: Exception) {
            true
        }
    }

    fun downloadAndSetWallpaperBackground(context: Context, isManual: Boolean = false): Boolean {
        try {
            WorkerLogger.i(context, "Wallify", "Starting background wallpaper change check")
            Log.d("Wallify", "Starting background wallpaper change (no Activity)")

            if (!isManual) {
                val (met, reason) = checkConstraints(context)
                if (!met) {
                    WorkerLogger.w(context, "Wallify", "Skipping wallpaper change: $reason")
                    Log.d("Wallify", "Skipping wallpaper change: $reason")
                    return false
                }
            }

            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val wallpaperSource = prefs.getString("flutter.wallpaperSource", "internet") ?: "internet"
            val sources = wallpaperSource.split(",").map { it.trim() }.filter { it.isNotEmpty() }.toSet()
            WorkerLogger.i(context, "Wallify", "Sources: $sources")

            val imageSources = mutableListOf<String>()

            if (sources.contains("folder")) {
                val folderPathsRaw = prefs.getString("flutter.folderPath", "[]") ?: "[]"
                val folderPaths = try {
                    JSONArray(folderPathsRaw).let { arr ->
                        (0 until arr.length()).map { arr.getString(it) }
                    }
                } catch (_: Exception) {
                    listOf(folderPathsRaw).filter { it.isNotEmpty() }
                }
                if (folderPaths.isNotEmpty()) {
                    var totalFound = 0
                    for (folderPath in folderPaths) {
                        val folder = File(folderPath)
                        if (folder.exists() && folder.isDirectory()) {
                            val count = imageSources.size
                            folder.listFiles { f -> f.isFile && f.extension.lowercase() in imageExtensions }
                                ?.forEach { imageSources.add(it.absolutePath) }
                            val found = imageSources.size - count
                            totalFound += found
                            WorkerLogger.i(context, "Wallify", "Found $found images in folder: $folderPath")
                            Log.d("Wallify", "Found $found images in folder: $folderPath")
                        } else {
                            WorkerLogger.e(context, "Wallify", "Folder does not exist: $folderPath")
                            Log.e("Wallify", "Folder does not exist: $folderPath")
                        }
                    }
                    WorkerLogger.i(context, "Wallify", "Total $totalFound images from all folders")
                    Log.d("Wallify", "Total $totalFound images from all folders")
                } else {
                    WorkerLogger.e(context, "Wallify", "Folder source selected but no folder paths set")
                    Log.e("Wallify", "Folder source selected but no folder paths set")
                }
            }

            if (sources.contains("internet") || sources.isEmpty() || sources.contains("folder").not()) {
                val cachedPaths = getCachedLocalPaths(context)
                if (cachedPaths.isNotEmpty()) {
                    WorkerLogger.i(context, "Wallify", "Using ${cachedPaths.size} locally cached wallpapers")
                    Log.d("Wallify", "Using ${cachedPaths.size} locally cached wallpapers")
                    imageSources.addAll(cachedPaths)
                } else {
                    val rawJson = prefs.getString("flutter.imageUrls", "[]") ?: "[]"
                    val imageUrls = parseImageUrlsJson(rawJson)

                    if (imageUrls.isEmpty()) {
                        WorkerLogger.w(context, "Wallify", "No image URLs found, fetching new ones from APIs...")
                        Log.w("Wallify", "No image URLs found, fetching new ones from APIs...")
                        val fetched = fetchImagesFromAllSources(context)
                        if (fetched.isEmpty()) {
                            WorkerLogger.e(context, "Wallify", "Could not fetch any wallpapers, aborting.")
                            Log.e("Wallify", "Could not fetch any wallpapers, aborting.")
                            return false
                        } else {
                            imageUrls.addAll(fetched)
                            WorkerLogger.i(context, "Wallify", "Added ${fetched.size} new wallpapers from API")
                            Log.d("Wallify", "Added ${fetched.size} new wallpapers from API")
                        }
                    } else {
                        WorkerLogger.i(context, "Wallify", "Loaded ${imageUrls.size} image URLs from storage")
                    }
                    imageSources.addAll(imageUrls)
                }
            }

            if (imageSources.isEmpty()) {
                WorkerLogger.e(context, "Wallify", "No wallpapers from any source, aborting.")
                Log.e("Wallify", "No wallpapers from any source, aborting.")
                return false
            }
            WorkerLogger.i(context, "Wallify", "Total image candidates: ${imageSources.size}")

            val wallpaperLocationValue = prefs.all["flutter.wallpaperLocation"]
            val wallpaperLocation = when (wallpaperLocationValue) {
                is Int -> wallpaperLocationValue
                is Long -> wallpaperLocationValue.toInt()
                is String -> wallpaperLocationValue.toIntOrNull() ?: 3
                else -> 3
            }
            val resolvedLocation = if (wallpaperLocation == 4) {
                val pick = (1..3).random()
                WorkerLogger.i(context, "Wallify", "Random mode: randomly picked $pick")
                pick
            } else {
                wallpaperLocation
            }
            WorkerLogger.i(context, "Wallify", "Wallpaper location mode: $wallpaperLocation (resolved: $resolvedLocation)")

            val wallpaperManager = WallpaperManager.getInstance(context)

            when (resolvedLocation) {
                1 -> {
                    WorkerLogger.i(context, "Wallify", "Setting HOME wallpaper")
                    val nonFacePath = getOrFetchNonFaceImagePath(context, imageSources)
                    if (nonFacePath == null) {
                        WorkerLogger.e(context, "Wallify", "No suitable wallpapers found (all had faces or invalid, fetch failed).")
                        Log.e("Wallify", "No suitable wallpapers found (all had faces or invalid, fetch failed).")
                        return false
                    }
                    WorkerLogger.i(context, "Wallify", "Selected: $nonFacePath")
                    setWallpaper(context, wallpaperManager, nonFacePath, WallpaperManager.FLAG_SYSTEM)
                }

                2 -> {
                    WorkerLogger.i(context, "Wallify", "Setting LOCK wallpaper")
                    val nonFacePath = getOrFetchNonFaceImagePath(context, imageSources)
                    if (nonFacePath == null) {
                        WorkerLogger.e(context, "Wallify", "No suitable wallpapers found (all had faces or invalid, fetch failed).")
                        Log.e("Wallify", "No suitable wallpapers found (all had faces or invalid, fetch failed).")
                        return false
                    }
                    WorkerLogger.i(context, "Wallify", "Selected: $nonFacePath")
                    setWallpaper(context, wallpaperManager, nonFacePath, WallpaperManager.FLAG_LOCK)
                }

                3 -> {
                    WorkerLogger.i(context, "Wallify", "Setting BOTH wallpapers")
                    val homePath = getOrFetchNonFaceImagePath(context, imageSources)
                    if (homePath == null) {
                        WorkerLogger.e(context, "Wallify", "No suitable wallpapers found for home (all had faces or invalid, fetch failed).")
                        Log.e("Wallify", "No suitable wallpapers found for home (all had faces or invalid, fetch failed).")
                        return false
                    }

                    imageSources.remove(homePath)
                    var lockPath = getOrFetchNonFaceImagePath(context, imageSources)
                    if (lockPath == null) {
                        lockPath = homePath
                    }
                    WorkerLogger.i(context, "Wallify", "Home: $homePath, Lock: $lockPath")
                    setWallpaper(context, wallpaperManager, homePath, WallpaperManager.FLAG_SYSTEM)
                    setWallpaper(context, wallpaperManager, lockPath, WallpaperManager.FLAG_LOCK)
                }

                else -> {
                    WorkerLogger.i(context, "Wallify", "Setting default (home) wallpaper")
                    val nonFacePath = getOrFetchNonFaceImagePath(context, imageSources)
                    if (nonFacePath == null) {
                        WorkerLogger.e(context, "Wallify", "No suitable wallpapers found (all had faces or invalid, fetch failed).")
                        Log.e("Wallify", "No suitable wallpapers found (all had faces or invalid, fetch failed).")
                        return false
                    }
                    WorkerLogger.i(context, "Wallify", "Selected: $nonFacePath")
                    Log.d("Wallify", "Setting default (home) wallpaper: $nonFacePath")
                    setWallpaper(context, wallpaperManager, nonFacePath, WallpaperManager.FLAG_SYSTEM)
                }
            }

            WorkerLogger.i(context, "Wallify", "Wallpaper change completed successfully (mode=$wallpaperLocation, source=$wallpaperSource)")
            Log.d("Wallify", "Wallpaper change completed (mode=$wallpaperLocation, source=$wallpaperSource)")
            showChangeNotification(context)
            return true
        } catch (e: Exception) {
            WorkerLogger.e(context, "Wallify", "Error: ${e.message}")
            Log.e("Wallify", "Error setting wallpaper in background", e)
            return false
        } catch (e: Error) {
            WorkerLogger.e(context, "Wallify", "Fatal error: ${e.message}")
            Log.e("Wallify", "Fatal error setting wallpaper in background: ${e.message}", e)
            return false
        }
    }

    private fun showChangeNotification(context: Context) {
        val channelId = "wallpaper_changes"
        val channelName = "Wallpaper Changes"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, channelName, NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Notifications when wallpaper changes automatically"
            }
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }

        val openIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val tryAnotherIntent = Intent(context, QuickToggleWidget::class.java).apply {
            action = QuickToggleWidget.ACTION_CHANGE_NOW
        }
        val tryAnotherPending = PendingIntent.getBroadcast(
            context, 0, tryAnotherIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )

        val openPending = openIntent?.let {
            PendingIntent.getActivity(
                context, 1, it,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            )
        }

        val notification = androidx.core.app.NotificationCompat.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_menu_gallery)
            .setContentTitle("Wallpaper Changed")
            .setContentText("Your wallpaper has been updated")
            .setContentIntent(openPending)
            .addAction(android.R.drawable.ic_menu_edit, "Try Another", tryAnotherPending)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Keep", null)
            .setAutoCancel(true)
            .build()

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(1001, notification)
    }

    // Shares the lock with detectFocusPoint: MediaPipe detectors aren't thread-safe.
    @Synchronized
    internal fun imageHasFace(context: Context, bitmap: Bitmap): Boolean {
        val detector = getFaceDetector(context) ?: return false
        return try {
            val mpImage = BitmapImageBuilder(bitmap).build()
            val results = detector.detect(mpImage)
            val hasFace = results.detections().isNotEmpty()
            if (hasFace) {
                WorkerLogger.i(context, "Wallify", "Face detected - skipping")
                Log.d("Wallify", "Face detected - skipping this wallpaper.")
            } else {
                WorkerLogger.i(context, "Wallify", "No faces detected - safe")
                Log.d("Wallify", "No faces detected - safe to use.")
            }
            hasFace
        } catch (e: Exception) {
            WorkerLogger.e(context, "Wallify", "Face detection error: ${e.message}")
            Log.e("Wallify", "Error detecting faces: ${e.message}", e)
            false
        }
    }

    /**
     * Finds the point the wallpaper should be centred on: the largest face,
     * otherwise the most prominent object, otherwise the image centre.
     * Coordinates are in the original bitmap's pixel space.
     */
    @Synchronized
    internal fun detectFocusPoint(context: Context, bitmap: Bitmap): Map<String, Float> {
        val imgW = bitmap.width
        val imgH = bitmap.height
        focusLog(context, "Detecting focus on ${imgW}x$imgH image (config=${bitmap.config})")

        // Detect on a downscaled copy (much faster, same result), then map back.
        val factor = maxOf(imgW, imgH).toFloat() / DETECTION_MAX_DIM
        val scaled = if (factor > 1f) {
            bitmap.scale((imgW / factor).toInt(), (imgH / factor).toInt(), true)
        } else bitmap
        val input = if (scaled.config != Bitmap.Config.ARGB_8888) {
            scaled.copy(Bitmap.Config.ARGB_8888, false)
        } else scaled
        val boxFactor = if (factor > 1f) factor else 1f
        if (input !== bitmap) {
            focusLog(context, "Detection input downscaled to ${input.width}x${input.height}")
        }

        try {
            val mpImage = BitmapImageBuilder(input).build()

            val faceDetector = getFaceDetector(context)
            if (faceDetector == null) {
                focusLog(context, "Face detector unavailable, skipping face step")
            } else {
                try {
                    val faces = faceDetector.detect(mpImage).detections()
                    focusLog(context, "Face detection found ${faces.size} face(s)")
                    faces.forEachIndexed { i, d ->
                        val score = d.categories().firstOrNull()?.score() ?: 0f
                        focusLog(context, "  face[$i] score=${"%.2f".format(score)} box=${scaleBox(d.boundingBox(), boxFactor).toShortString()}")
                    }
                    val best = faces.maxByOrNull { it.boundingBox().width() * it.boundingBox().height() }
                    if (best != null) {
                        return focusResult(context, best.boundingBox(), boxFactor, imgW, imgH, "face", 1f)
                    }
                } catch (e: Exception) {
                    WorkerLogger.e(context, FOCUS_TAG, "Face detection failed: ${e.message}")
                    Log.e(FOCUS_TAG, "Face detection failed", e)
                }
            }

            val objDetector = getObjectDetector(context)
            if (objDetector == null) {
                focusLog(context, "Object detector unavailable, skipping object step")
            } else {
                try {
                    val objects = objDetector.detect(mpImage).detections()
                    focusLog(context, "Object detection found ${objects.size} object(s)")
                    val inputArea = (input.width * input.height).toFloat()
                    // Favour confident detections, with a boost for larger subjects.
                    fun rank(d: com.google.mediapipe.tasks.components.containers.Detection): Float {
                        val score = d.categories().firstOrNull()?.score() ?: 0f
                        val box = d.boundingBox()
                        val areaFraction = (box.width() * box.height() / inputArea).coerceIn(0f, 1f)
                        return score * (0.5f + 0.5f * areaFraction)
                    }
                    objects.forEachIndexed { i, d ->
                        val cat = d.categories().firstOrNull()
                        focusLog(
                            context,
                            "  object[$i] ${cat?.categoryName() ?: "?"} score=${"%.2f".format(cat?.score() ?: 0f)} " +
                                "rank=${"%.2f".format(rank(d))} box=${scaleBox(d.boundingBox(), boxFactor).toShortString()}"
                        )
                    }
                    val best = objects.maxByOrNull { rank(it) }
                    if (best != null) {
                        val label = best.categories().firstOrNull()?.categoryName() ?: "object"
                        return focusResult(context, best.boundingBox(), boxFactor, imgW, imgH, "object '$label'", 2f)
                    }
                } catch (e: Exception) {
                    WorkerLogger.e(context, FOCUS_TAG, "Object detection failed: ${e.message}")
                    Log.e(FOCUS_TAG, "Object detection failed", e)
                }
            }
        } catch (e: Error) {
            WorkerLogger.e(context, FOCUS_TAG, "Native error during detection: ${e.message}")
            Log.e(FOCUS_TAG, "Native error during detection", e)
        } finally {
            if (input !== bitmap) input.recycle()
            if (scaled !== bitmap && scaled !== input) scaled.recycle()
        }

        focusLog(context, "No face or object found, using image centre (${imgW / 2}, ${imgH / 2})")
        return mapOf("x" to imgW / 2f, "y" to imgH / 2f, "source" to 0f)
    }

    private fun scaleBox(box: RectF, factor: Float): RectF =
        RectF(box.left * factor, box.top * factor, box.right * factor, box.bottom * factor)

    private fun focusResult(
        context: Context,
        box: RectF,
        factor: Float,
        imgW: Int,
        imgH: Int,
        source: String,
        code: Float
    ): Map<String, Float> {
        val x = ((box.left + box.right) / 2f * factor).coerceIn(0f, imgW.toFloat())
        val y = ((box.top + box.bottom) / 2f * factor).coerceIn(0f, imgH.toFloat())
        focusLog(
            context,
            "Focus from $source at (${x.toInt()}, ${y.toInt()}) = " +
                "${(x / imgW * 100).toInt()}% across, ${(y / imgH * 100).toInt()}% down"
        )
        return mapOf("x" to x, "y" to y, "source" to code)
    }

    private fun getConfiguredFolderPaths(context: Context): List<String> {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val folderPathsRaw = prefs.getString("flutter.folderPath", "[]") ?: "[]"
        return try {
            JSONArray(folderPathsRaw).let { arr ->
                (0 until arr.length()).map { arr.getString(it) }
            }
        } catch (_: Exception) {
            listOf(folderPathsRaw).filter { it.isNotEmpty() }
        }
    }

    private fun isFolderImagePath(context: Context, path: String): Boolean {
        if (path.startsWith("http://") || path.startsWith("https://")) return false
        if (!path.startsWith("/")) return false
        return getConfiguredFolderPaths(context).any { folder ->
            val normalized = if (folder.endsWith("/")) folder else "$folder/"
            path.startsWith(normalized)
        }
    }

    private fun loadUsedFolderPaths(context: Context): Set<String> {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val raw = prefs.getString("usedFolderPaths", null) ?: return emptySet()
        return try {
            JSONArray(raw).let { arr ->
                (0 until arr.length()).map { arr.getString(it) }.toSet()
            }
        } catch (_: Exception) {
            emptySet()
        }
    }

    private fun addUsedFolderPath(context: Context, path: String) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val used = loadUsedFolderPaths(context).toMutableSet()
        used.add(path)
        prefs.edit().putString("usedFolderPaths", JSONArray(used.toList()).toString()).apply()
    }

    private fun clearUsedFolderPaths(context: Context) {
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .edit().remove("usedFolderPaths").apply()
    }

    private fun loadUsedUrlSet(context: Context): Set<String> {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val raw = prefs.getString("usedWallpaperUrls", null) ?: return emptySet()
        return try {
            JSONArray(raw).let { arr ->
                (0 until arr.length()).map { arr.getString(it) }.toSet()
            }
        } catch (_: Exception) {
            emptySet()
        }
    }

    private fun addUsedUrl(context: Context, url: String) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val used = loadUsedUrlSet(context).toMutableSet()
        used.add(url)
        prefs.edit().putString("usedWallpaperUrls", JSONArray(used.toList()).toString()).apply()
    }

    private fun clearUsedUrls(context: Context) {
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .edit().remove("usedWallpaperUrls").apply()
    }

    private fun getNonFaceImagePath(context: Context, paths: MutableList<String>): String? {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val requiresNoFaces = prefs.getBoolean("flutter.constraint_no_faces", true)
        Log.d("Wallify", "getNonFaceImagePath: requiresNoFaces=$requiresNoFaces, poolSize=${paths.size}")

        val usedFolderPaths = loadUsedFolderPaths(context)
        val usedUrls = loadUsedUrlSet(context)

        fun isAlreadyUsed(path: String): Boolean {
            return if (isFolderImagePath(context, path)) {
                usedFolderPaths.contains(path)
            } else {
                usedUrls.contains(path)
            }
        }

        val seen = mutableSetOf<String>()
        val duplicates = mutableListOf<String>()
        for (entry in paths) {
            if (!seen.add(entry)) duplicates.add(entry)
        }
        if (duplicates.isNotEmpty()) {
            Log.w("Wallify", "POOL CONTAINS DUPLICATES (${duplicates.size}): ${duplicates.take(10)}")
        }
        Log.d("Wallify", "First 10 pool candidates: ${paths.take(10).joinToString()}")
        if (usedUrls.isNotEmpty()) {
            Log.d("Wallify", "Skipping ${usedUrls.size} previously used wallpapers: ${usedUrls.take(10)}")
        }

        val iterator = paths.iterator()
        while (iterator.hasNext()) {
            val path = iterator.next()

            if (isAlreadyUsed(path)) {
                Log.d("Wallify", "Skipping already-used wallpaper: $path")
                iterator.remove()
                continue
            }

            val bitmap = loadBitmapFromSource(context, path)
            if (bitmap == null) {
                Log.w("Wallify", "Skipping invalid image: $path")
                iterator.remove()
                if (!isFolderImagePath(context, path)) {
                    removeUsedUrl(context, path, addToHistory = false)
                    removeUsedCachedPath(context, path)
                }
                continue
            }

            if (!requiresNoFaces) {
                if (isFolderImagePath(context, path)) addUsedFolderPath(context, path)
                else addUsedUrl(context, path)
                return path
            }

            if (!imageHasFace(context, bitmap)) {
                Log.d("Wallify", "Selected wallpaper without faces: $path")
                if (isFolderImagePath(context, path)) addUsedFolderPath(context, path)
                else addUsedUrl(context, path)
                return path
            } else {
                Log.d("Wallify", "Discarded face image: $path")
                iterator.remove()
                if (!isFolderImagePath(context, path)) {
                    removeUsedUrl(context, path, addToHistory = false)
                }
            }
        }

        return null
    }

    private fun getOrFetchNonFaceImagePath(
        context: Context,
        imageSources: MutableList<String>,
        maxFetchRetries: Int = 2
    ): String? {
        var retriesLeft = maxFetchRetries
        imageSources.shuffle()
        while (true) {
            val path = getNonFaceImagePath(context, imageSources)
            if (path != null) {
                return path
            }

            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val wallpaperSource = prefs.getString("flutter.wallpaperSource", "internet") ?: "internet"
            val sources = wallpaperSource.split(",").map { it.trim() }.filter { it.isNotEmpty() }.toSet()
            val isOnlyFolder = sources.size == 1 && sources.contains("folder")
            val hasInternet = !isOnlyFolder

            if (isOnlyFolder) {
                if (loadUsedFolderPaths(context).isNotEmpty()) {
                    WorkerLogger.i(context, "Wallify", "All folder images used this cycle, resetting rotation")
                    clearUsedFolderPaths(context)
                    continue
                }
                WorkerLogger.w(context, "Wallify", "No folder images available")
                return null
            }

            if (!hasInternet) {
                WorkerLogger.w(context, "Wallify", "No suitable wallpaper found (hasInternet=$hasInternet, retriesLeft=$retriesLeft)")
                Log.w("Wallify", "No suitable wallpaper found (hasInternet=$hasInternet, retriesLeft=$retriesLeft)")
                return null
            }

            if (loadUsedUrlSet(context).isNotEmpty()) {
                WorkerLogger.i(context, "Wallify", "All cached candidates already used, resetting usage tracking")
                Log.i("Wallify", "All cached candidates already used, resetting usage tracking")
                clearUsedUrls(context)
                continue
            }

            if (retriesLeft <= 0) {
                WorkerLogger.w(context, "Wallify", "No suitable wallpaper found (hasInternet=$hasInternet, retriesLeft=$retriesLeft)")
                Log.w("Wallify", "No suitable wallpaper found (hasInternet=$hasInternet, retriesLeft=$retriesLeft)")
                return null
            }

            retriesLeft--
            WorkerLogger.i(context, "Wallify", "Candidate wallpaper pool exhausted. Fetching fresh wallpapers from APIs...")
            Log.i("Wallify", "Candidate wallpaper pool exhausted. Fetching fresh wallpapers from APIs...")

            val freshUrls = fetchImagesFromAllSources(context)
            if (freshUrls.isEmpty()) {
                WorkerLogger.e(context, "Wallify", "Could not fetch any new wallpapers from APIs.")
                Log.e("Wallify", "Could not fetch any new wallpapers from APIs.")
                return null
            }

            imageSources.addAll(freshUrls)
            imageSources.shuffle()
        }
    }

    private fun fetchImagesFromAllSources(context: Context): List<String> {
        val urls = mutableListOf<String>()
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val tagsJson = prefs.getString("flutter.tags", null)
            val savedTags = if (!tagsJson.isNullOrEmpty()) {
                try {
                    val arr = org.json.JSONArray(tagsJson)
                    (0 until arr.length()).map { arr.getString(it) }.filter { it.isNotBlank() }
                } catch (_: Exception) { emptyList() }
            } else emptyList()

            val tag = if (savedTags.isNotEmpty()) {
                savedTags.random()
            } else {
                prefs.getString("flutter.random_tag", "nature") ?: "nature"
            }

            val (deviceWidth, deviceHeight) = getScreenSize(context)

            WorkerLogger.i(context, "Wallify", "Fetching wallpapers tag=$tag, size=${deviceWidth}x$deviceHeight")
            Log.d("Wallify", "Fetching wallpapers with tag=$tag, size=${deviceWidth}x$deviceHeight")

            // Always pull the best-rated wallpapers. A random page adds variety
            // between runs; page 1 is the fallback when that page is empty.
            val q = java.net.URLEncoder.encode(tag, "UTF-8")
            val page = (1..3).random()
            fun <T> withPageFallback(fetch: (Int) -> List<T>): List<T> {
                val first = fetch(page)
                return if (first.isEmpty() && page != 1) fetch(1) else first
            }

            var wallhaven = withPageFallback { p ->
                fetchFromWallhaven("https://wallhaven.cc/api/v1/search?q=$q&categories=100&purity=100&ratios=portrait&sorting=toplist&topRange=1M&order=desc&page=$p")
            }
            if (wallhaven.isEmpty()) {
                // Niche tags may have nothing in the last month's toplist.
                wallhaven = fetchFromWallhaven("https://wallhaven.cc/api/v1/search?q=$q&categories=100&purity=100&ratios=portrait&sorting=toplist&topRange=1y&order=desc")
            }
            WorkerLogger.i(context, "Wallify", "Wallhaven toplist: ${wallhaven.size} wallpapers")
            urls.addAll(wallhaven)

            val unsplash = withPageFallback { p ->
                fetchFromUnsplash(context, "https://api.unsplash.com/search/photos?query=$q&orientation=portrait&content_filter=high&order_by=relevant&per_page=30&page=$p")
            }
            WorkerLogger.i(context, "Wallify", "Unsplash: ${unsplash.size} wallpapers")
            urls.addAll(unsplash)

            val pixabayApiKey = prefs.getString("flutter.pixabay_api_key", null)
            if (!pixabayApiKey.isNullOrEmpty()) {
                val pixabay = withPageFallback { p ->
                    fetchFromPixabay("https://pixabay.com/api/?key=$pixabayApiKey&q=$q&image_type=photo&orientation=vertical&safesearch=true&order=popular&per_page=30&page=$p")
                }
                WorkerLogger.i(context, "Wallify", "Pixabay popular: ${pixabay.size} wallpapers")
                urls.addAll(pixabay)
            }

            if (urls.isEmpty()) {
                Log.w("Wallify", "No wallpapers found from any source")
            } else {
                val jsonArray = JSONArray()
                urls.forEach { url ->
                    val obj = org.json.JSONObject()
                    obj.put("url", url)
                    jsonArray.put(obj)
                }
                prefs.edit().putString("flutter.imageUrls", jsonArray.toString()).apply()
                Log.d("Wallify", "Saved ${urls.size} image URLs to SharedPreferences")
                Log.d("Wallify", "Fetched URLs (${urls.size}): ${urls.take(30).joinToString()}")
            }
        } catch (e: Exception) {
            Log.e("Wallify", "Error fetching images: ${e.message}", e)
        }

        return urls
    }

    private fun fetchFromWallhaven(apiUrl: String): List<String> {
        val urls = mutableListOf<String>()
        try {
            val connection = URL(apiUrl).openConnection() as HttpURLConnection
            connection.connectTimeout = 15000
            connection.readTimeout = 15000
            val response = connection.inputStream.bufferedReader().readText()
            val data = org.json.JSONObject(response).getJSONArray("data")
            for (i in 0 until data.length()) {
                val item = data.getJSONObject(i)
                urls.add(item.getString("path"))
            }
            connection.disconnect()
        } catch (e: Exception) {
            Log.e("Wallify", "Wallhaven fetch failed: ${e.message}")
        }
        return urls
    }

    private fun fetchFromUnsplash(context: Context, apiUrl: String): List<String> {
        val urls = mutableListOf<String>()
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val key = prefs.getString("flutter.unsplash_api_key", null)
                ?: prefs.getString("unsplash_api_key", null)
            if (key.isNullOrEmpty()) return urls
            val connection = URL(apiUrl).openConnection() as HttpURLConnection
            connection.setRequestProperty("Authorization", "Client-ID $key")
            connection.connectTimeout = 15000
            connection.readTimeout = 15000
            val response = connection.inputStream.bufferedReader().readText()
            // Search returns {"results": [...]}; list endpoints return a bare array.
            val data = when (val json = org.json.JSONTokener(response).nextValue()) {
                is JSONObject -> json.optJSONArray("results") ?: JSONArray()
                is JSONArray -> json
                else -> JSONArray()
            }
            for (i in 0 until data.length()) {
                val item = data.getJSONObject(i)
                val urlsObj = item.getJSONObject("urls")
                urls.add(urlsObj.getString("regular"))
            }
            connection.disconnect()
        } catch (e: Exception) {
            Log.e("Wallify", "Unsplash fetch failed: ${e.message}")
        }
        return urls
    }

    private fun fetchFromPixabay(apiUrl: String): List<String> {
        val urls = mutableListOf<String>()
        try {
            val connection = URL(apiUrl).openConnection() as HttpURLConnection
            connection.connectTimeout = 15000
            connection.readTimeout = 15000
            val response = connection.inputStream.bufferedReader().readText()
            val data = org.json.JSONObject(response).getJSONArray("hits")
            for (i in 0 until data.length()) {
                val item = data.getJSONObject(i)
                urls.add(item.getString("largeImageURL"))
            }
            connection.disconnect()
        } catch (e: Exception) {
            Log.e("Wallify", "Pixabay fetch failed: ${e.message}")
        }
        return urls
    }

    private fun setWallpaper(context: Context, manager: WallpaperManager, imagePath: String, flag: Int) {
        WorkerLogger.i(context, "Wallify", "Loading image: $imagePath (flag=$flag)")
        val bitmap = loadBitmapFromSource(context, imagePath)
        if (bitmap == null) {
            WorkerLogger.e(context, "Wallify", "Failed to load image bitmap: $imagePath")
            Log.e("Wallify", "Failed to load image: $imagePath")
            return
        }

        try {
            val (deviceWidth, deviceHeight) = getScreenSize(context)
            focusLog(context, "Target screen ${deviceWidth}x$deviceHeight, source image ${bitmap.width}x${bitmap.height} (flag=$flag)")

            val resultBitmap = detectAndCropMainObject(context, bitmap, deviceWidth, deviceHeight)
            focusLog(context, "Final wallpaper bitmap ${resultBitmap.width}x${resultBitmap.height}")

            manager.setBitmap(resultBitmap, null, true, flag)
            Log.d("Wallify", "Wallpaper set successfully for flag=$flag")
            extractAndSaveWallpaperColors(context, resultBitmap)
            updateLastChangeTime(context)
            StatsWidget.triggerUpdate(context)
            QuickToggleWidget.triggerUpdate(context)
            ScheduleWidget.triggerUpdate(context)
            saveCurrentWallpaper(context, resultBitmap)
            trackWallpaperChange(context, imagePath)
            if (!isFolderImagePath(context, imagePath)) {
                removeUsedUrl(context, imagePath)
                removeUsedCachedPath(context, imagePath)
            }

        } catch (e: Exception) {
            WorkerLogger.e(context, "Wallify", "Error setting wallpaper from $imagePath: ${e.message}")
            Log.e("Wallify", "Error setting wallpaper from $imagePath", e)
        }
    }

    private fun loadBitmapFromSource(context: Context, path: String): Bitmap? {
        return if (path.startsWith("http://") || path.startsWith("https://")) {
            val tempFile = downloadImage(context, path)
            if (tempFile == null) return null
            val bitmap = BitmapFactory.decodeFile(tempFile.absolutePath)
            tempFile.delete()
            bitmap
        } else {
            BitmapFactory.decodeFile(path)
        }
    }

    private fun downloadImage(context: Context, imageUrl: String): File? {
        return try {
            val url = URL(imageUrl)
            val connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = "GET"
            connection.connectTimeout = 10000
            connection.readTimeout = 10000
            connection.setRequestProperty("User-Agent", "Wallify-App")

            val responseCode = connection.responseCode
            if (responseCode != HttpURLConnection.HTTP_OK) {
                Log.e("Wallify", "Failed to download image: HTTP $responseCode for $imageUrl")
                return null
            }

            val input = connection.inputStream
            val bytes = input.readBytes()
            input.close()

            val file = File(context.cacheDir, "wallpaper_bg_${Random.nextInt()}.jpg")
            file.writeBytes(bytes)
            file
        } catch (e: Exception) {
            Log.e("Wallify", "Failed to download image: $e")
            null
        }
    }

    private fun getCachedLocalPaths(context: Context): MutableList<String> {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val cachedRaw = prefs.getString("cachedWallpaperPaths", null) ?: return mutableListOf()
        return try {
            val arr = org.json.JSONArray(cachedRaw)
            val paths = (0 until arr.length()).map { arr.getString(it) }.toMutableList()
            paths.removeAll { path -> !File(path).exists() }
            paths
        } catch (e: Exception) {
            Log.e("Wallify", "Error parsing cachedWallpaperPaths JSON", e)
            mutableListOf()
        }
    }

    fun extractAndSaveWallpaperColors(context: Context, bitmap: Bitmap) {
        try {
            val palette = Palette.from(bitmap).generate()
            val dominantColor = palette?.dominantSwatch?.rgb
            val lightVibrant = palette?.lightVibrantSwatch?.rgb
            val darkVibrant = palette?.darkVibrantSwatch?.rgb

            if (dominantColor != null) {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val editor = prefs.edit()
                editor.putInt("wallpaperSeedColor", dominantColor)
                // Flutter's SharedPreferences only sees "flutter."-prefixed keys (ints stored as Long).
                editor.putLong("flutter.wallpaperSeedColor", dominantColor.toLong())
                if (lightVibrant != null) editor.putInt("wallpaperLightVibrant", lightVibrant)
                if (darkVibrant != null) editor.putInt("wallpaperDarkVibrant", darkVibrant)
                editor.apply()
                Log.d("Wallify", "Wallpaper dominant color: #${dominantColor.toString(16)}")
            }
        } catch (e: Exception) {
            Log.e("Wallify", "Failed to extract wallpaper colors: ${e.message}")
        }
    }

    fun extractColorsFromFile(context: Context, filePath: String): Map<String, Int> {
        val bitmap = BitmapFactory.decodeFile(filePath) ?: return emptyMap()
        extractAndSaveWallpaperColors(context, bitmap)
        val palette = Palette.from(bitmap).generate()
        val result = mutableMapOf<String, Int>()
        palette?.dominantSwatch?.rgb?.let { result["dominant"] = it }
        palette?.lightVibrantSwatch?.rgb?.let { result["lightVibrant"] = it }
        palette?.darkVibrantSwatch?.rgb?.let { result["darkVibrant"] = it }
        palette?.lightMutedSwatch?.rgb?.let { result["lightMuted"] = it }
        palette?.darkMutedSwatch?.rgb?.let { result["darkMuted"] = it }
        return result
    }

    private fun updateLastChangeTime(context: Context) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val editor = prefs.edit()

        val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
        val now = dateFormat.format(Date())

        editor.putString("flutter.lastWallpaperChange", now)
        editor.apply()

        Log.d("Wallify", "Updated lastWallpaperChange = $now")
    }

    private fun removeUsedUrl(context: Context, usedUrl: String, addToHistory: Boolean = true) {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

            var imageJsonString = prefs.getString("flutter.imageUrls", "[]") ?: "[]"
            if (imageJsonString.contains("![")) {
                imageJsonString = imageJsonString.substringAfter("!")
            }
            val imageList = JSONArray(imageJsonString)

            Log.d("Wallify", "Removing wallpaper URL (addToHistory=$addToHistory): $usedUrl")

            val newImageList = JSONArray()
            var movedObject: JSONObject? = null

            for (i in 0 until imageList.length()) {
                val rawItem = imageList.get(i)
                val item = when (rawItem) {
                    is JSONObject -> rawItem
                    is String -> try { JSONObject(rawItem) } catch (_: Exception) { JSONObject().put("url", rawItem) }
                    else -> JSONObject()
                }
                val url = item.optString("url", "")

                if (url == usedUrl && movedObject == null) {
                    movedObject = item
                    Log.d("Wallify", "Removed from imageUrls: $usedUrl")
                } else {
                    newImageList.put(item)
                }
            }

            prefs.edit().putString("flutter.imageUrls", newImageList.toString()).apply()

            if (addToHistory) {
                val historyJsonString = prefs.getString("flutter.wallpaperHistory", "[]") ?: "[]"
                val historyList = JSONArray(historyJsonString)

                val movedEntry = movedObject ?: JSONObject().put("url", usedUrl)
                val movedUrl = movedEntry.optString("url", usedUrl)

                val newHistory = JSONArray()
                newHistory.put(movedEntry)
                for (i in 0 until historyList.length()) {
                    val existing = historyList.optJSONObject(i) ?: continue
                    if (existing.optString("url", "") == movedUrl) continue
                    newHistory.put(existing)
                }

                val maxHistory = 100
                val cappedHistory = if (newHistory.length() > maxHistory) {
                    JSONArray().apply {
                        for (i in 0 until maxHistory) put(newHistory.get(i))
                    }
                } else {
                    newHistory
                }

                prefs.edit().putString("flutter.wallpaperHistory", cappedHistory.toString()).apply()
                Log.d("Wallify", "History size: ${cappedHistory.length()}")
            }

            Log.d("Wallify", "Remaining imageUrls: ${newImageList.length()}")
            val remainingUrls = (0 until newImageList.length()).map { i ->
                val item = newImageList.get(i)
                when (item) {
                    is JSONObject -> item.optString("url", item.toString())
                    is String -> item
                    else -> ""
                }
            }
            Log.d("Wallify", "Remaining imageUrls contents (${remainingUrls.size}): ${remainingUrls.joinToString()}")

        } catch (e: Exception) {
            Log.e("Wallify", "Error updating history: ${e.message}", e)
        }
    }

    private fun parseImageUrlsJson(jsonStr: String): MutableList<String> {
        var imageJsonString = jsonStr
        if (imageJsonString.contains("![")) {
            imageJsonString = imageJsonString.substringAfter("!")
        }
        val urls = mutableListOf<String>()
        try {
            val jsonArray = org.json.JSONArray(imageJsonString)
            for (i in 0 until jsonArray.length()) {
                val rawObj = jsonArray.get(i)
                val url = when (rawObj) {
                    is JSONObject -> rawObj.optString("url", "")
                    is String -> try { JSONObject(rawObj).optString("url", rawObj) } catch (_: Exception) { rawObj }
                    else -> ""
                }
                if (url.isNotEmpty()) urls.add(url)
            }
        } catch (e: Exception) {
            Log.e("Wallify", "Error parsing imageUrls JSON: ${e.message}")
        }
        return urls
    }

    private fun removeUsedCachedPath(context: Context, usedPath: String) {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val cachedRaw = prefs.getString("cachedWallpaperPaths", null) ?: return
            val arr = org.json.JSONArray(cachedRaw)
            val newArr = org.json.JSONArray()
            for (i in 0 until arr.length()) {
                val path = arr.optString(i, "")
                if (path != usedPath) newArr.put(path)
            }
            if (newArr.length() < arr.length()) {
                prefs.edit().putString("cachedWallpaperPaths", newArr.toString()).apply()
                Log.d("Wallify", "Removed used cached path, ${newArr.length()} remaining")
            }
        } catch (e: Exception) {
            Log.e("Wallify", "Error removing used cached path: ${e.message}", e)
        }
    }

    internal fun detectAndCropMainObject(
        context: Context,
        bitmap: Bitmap,
        targetWidth: Int,
        targetHeight: Int
    ): Bitmap {
        return try {
            val focus = detectFocusPoint(context, bitmap)
            cropAroundPoint(
                context, bitmap,
                focus["x"] ?: (bitmap.width / 2f),
                focus["y"] ?: (bitmap.height / 2f),
                targetWidth, targetHeight
            )
        } catch (e: Exception) {
            WorkerLogger.e(context, FOCUS_TAG, "Smart crop failed, centre-cropping: ${e.message}")
            Log.e(FOCUS_TAG, "Smart crop failed", e)
            cropAroundPoint(context, bitmap, bitmap.width / 2f, bitmap.height / 2f, targetWidth, targetHeight)
        } catch (e: Error) {
            WorkerLogger.e(context, FOCUS_TAG, "Native error in smart crop, centre-cropping: ${e.message}")
            Log.e(FOCUS_TAG, "Native error in smart crop", e)
            cropAroundPoint(context, bitmap, bitmap.width / 2f, bitmap.height / 2f, targetWidth, targetHeight)
        }
    }

    private fun saveCurrentWallpaper(context: Context, bitmap: android.graphics.Bitmap) {
        try {
            val dir = context.filesDir
            val target = java.io.File(dir, "live_wallpaper.jpg")
            val temp = java.io.File(dir, "live_wallpaper.jpg.tmp")
            val stream = java.io.FileOutputStream(temp)
            bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 95, stream)
            stream.close()
            if (target.exists()) target.delete()
            if (!temp.renameTo(target)) {
                temp.copyTo(target, overwrite = true)
                temp.delete()
            }
            Log.d("Wallify", "Saved wallpaper to ${target.absolutePath}")
            val intent = android.content.Intent("com.rk.wallify.LIVE_WALLPAPER_UPDATED")
            intent.setPackage(context.packageName)
            context.sendBroadcast(intent)
        } catch (e: Exception) {
            Log.e("Wallify", "Failed to save wallpaper bitmap", e)
        }
    }

    /** Crops the largest screen-aspect region centred as close to (focusX, focusY) as the image allows. */
    private fun cropAroundPoint(
        context: Context,
        bitmap: Bitmap,
        focusX: Float,
        focusY: Float,
        targetWidth: Int,
        targetHeight: Int
    ): Bitmap {
        val targetAspect = targetWidth.toDouble() / targetHeight.toDouble()
        val imgW = bitmap.width
        val imgH = bitmap.height
        val imgAspect = imgW.toDouble() / imgH.toDouble()

        val cropW: Int
        val cropH: Int
        if (imgAspect > targetAspect) {
            cropH = imgH
            cropW = (imgH * targetAspect).toInt().coerceIn(1, imgW)
        } else {
            cropW = imgW
            cropH = (imgW / targetAspect).toInt().coerceIn(1, imgH)
        }

        val cropLeft = (focusX - cropW / 2f).toInt().coerceIn(0, imgW - cropW)
        val cropTop = (focusY - cropH / 2f).toInt().coerceIn(0, imgH - cropH)

        val panRoom = when {
            imgW - cropW > 0 -> "horizontal pan room ${imgW - cropW}px"
            imgH - cropH > 0 -> "vertical pan room ${imgH - cropH}px"
            else -> "image already matches screen aspect, no pan room"
        }
        focusLog(
            context,
            "Crop ${cropW}x$cropH at ($cropLeft, $cropTop) from ${imgW}x$imgH " +
                "(image aspect ${"%.3f".format(imgAspect)}, screen aspect ${"%.3f".format(targetAspect)}, $panRoom) " +
                "-> scaled to ${targetWidth}x$targetHeight"
        )

        val cropped = Bitmap.createBitmap(bitmap, cropLeft, cropTop, cropW, cropH)
        return cropped.scale(targetWidth, targetHeight, true)
    }

    private fun trackWallpaperChange(context: Context, imagePath: String) {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

            val count = prefs.getInt("flutter.totalWallpaperChanges", 0) + 1
            prefs.edit().putInt("flutter.totalWallpaperChanges", count).apply()

            val recentRaw = prefs.getString("flutter.recentWallpaperInfo", "[]") ?: "[]"
            val recentArr = JSONArray(recentRaw)
            val entry = JSONObject().apply {
                put("path", imagePath)
                put("time", SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date()))
            }
            recentArr.put(entry)
            while (recentArr.length() > 10) {
                recentArr.remove(0)
            }
            prefs.edit().putString("flutter.recentWallpaperInfo", recentArr.toString()).apply()
        } catch (_: Exception) { }
    }
}
