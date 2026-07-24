package com.rk.wallify

import android.app.WallpaperManager
import android.content.Context
import android.graphics.BitmapFactory
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

    private fun getObjectDetector(context: Context): ObjectDetector? {
        if (objectDetectorFailed) return null
        if (cachedObjectDetector == null) {
            try {
                val baseOptions = BaseOptions.builder()
                    .setModelAssetPath("efficientdet_lite0.tflite")
                    .build()
                val options = ObjectDetectorOptions.builder()
                    .setBaseOptions(baseOptions)
                    .setMaxResults(1)
                    .setScoreThreshold(0.5f)
                    .setRunningMode(RunningMode.IMAGE)
                    .build()
                cachedObjectDetector = ObjectDetector.createFromOptions(context, options)
            } catch (e: Throwable) {
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
            } catch (e: Throwable) {
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

    fun downloadAndSetWallpaperBackground(context: Context) {
        try {
            WorkerLogger.i(context, "Wallify", "Starting background wallpaper change check")
            Log.d("Wallify", "Starting background wallpaper change (no Activity)")

            val (met, reason) = checkConstraints(context)
            if (!met) {
                WorkerLogger.w(context, "Wallify", "Skipping wallpaper change: $reason")
                Log.d("Wallify", "Skipping wallpaper change: $reason")
                return
            }

            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val wallpaperSource = prefs.getString("flutter.wallpaperSource", "internet") ?: "internet"
            val sources = wallpaperSource.split(",").map { it.trim() }.filter { it.isNotEmpty() }.toSet()
            WorkerLogger.i(context, "Wallify", "Sources: $sources")

            val imageSources = mutableListOf<String>()

            if (sources.contains("folder")) {
                val folderPath = prefs.getString("flutter.folderPath", null)
                if (!folderPath.isNullOrEmpty()) {
                    val folder = File(folderPath)
                    if (folder.exists() && folder.isDirectory()) {
                        folder.listFiles { f -> f.isFile && f.extension.lowercase() in imageExtensions }
                            ?.forEach { imageSources.add(it.absolutePath) }
                        WorkerLogger.i(context, "Wallify", "Found ${imageSources.size} images in folder: $folderPath")
                        Log.d("Wallify", "Found ${imageSources.size} images in folder: $folderPath")
                    } else {
                        WorkerLogger.e(context, "Wallify", "Folder does not exist: $folderPath")
                        Log.e("Wallify", "Folder does not exist: $folderPath")
                    }
                } else {
                    WorkerLogger.e(context, "Wallify", "Folder source selected but no folder path set")
                    Log.e("Wallify", "Folder source selected but no folder path set")
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
                            return
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
                return
            }
            WorkerLogger.i(context, "Wallify", "Total image candidates: ${imageSources.size}")

            val wallpaperLocationValue = prefs.all["flutter.wallpaperLocation"]
            val wallpaperLocation = when (wallpaperLocationValue) {
                is Int -> wallpaperLocationValue
                is Long -> wallpaperLocationValue.toInt()
                is String -> wallpaperLocationValue.toIntOrNull() ?: 3
                else -> 3
            }
            WorkerLogger.i(context, "Wallify", "Wallpaper location mode: $wallpaperLocation")

            val wallpaperManager = WallpaperManager.getInstance(context)
            val isFolderMode = sources.contains("folder")

            when (wallpaperLocation) {
                1 -> {
                    WorkerLogger.i(context, "Wallify", "Setting HOME wallpaper")
                    val nonFacePath = getOrFetchNonFaceImagePath(context, imageSources, isFolderMode)
                    if (nonFacePath == null) {
                        WorkerLogger.e(context, "Wallify", "No suitable wallpapers found (all had faces or invalid, fetch failed).")
                        Log.e("Wallify", "No suitable wallpapers found (all had faces or invalid, fetch failed).")
                        return
                    }
                    WorkerLogger.i(context, "Wallify", "Selected: $nonFacePath")
                    setWallpaper(context, wallpaperManager, nonFacePath, WallpaperManager.FLAG_SYSTEM, isFolderMode)
                }

                2 -> {
                    WorkerLogger.i(context, "Wallify", "Setting LOCK wallpaper")
                    val nonFacePath = getOrFetchNonFaceImagePath(context, imageSources, isFolderMode)
                    if (nonFacePath == null) {
                        WorkerLogger.e(context, "Wallify", "No suitable wallpapers found (all had faces or invalid, fetch failed).")
                        Log.e("Wallify", "No suitable wallpapers found (all had faces or invalid, fetch failed).")
                        return
                    }
                    WorkerLogger.i(context, "Wallify", "Selected: $nonFacePath")
                    setWallpaper(context, wallpaperManager, nonFacePath, WallpaperManager.FLAG_LOCK, isFolderMode)
                }

                3 -> {
                    WorkerLogger.i(context, "Wallify", "Setting BOTH wallpapers")
                    val homePath = getOrFetchNonFaceImagePath(context, imageSources, isFolderMode)
                    if (homePath == null) {
                        WorkerLogger.e(context, "Wallify", "No suitable wallpapers found for home (all had faces or invalid, fetch failed).")
                        Log.e("Wallify", "No suitable wallpapers found for home (all had faces or invalid, fetch failed).")
                        return
                    }

                    imageSources.remove(homePath)
                    var lockPath = getOrFetchNonFaceImagePath(context, imageSources, isFolderMode)
                    if (lockPath == null) {
                        lockPath = homePath
                    }
                    WorkerLogger.i(context, "Wallify", "Home: $homePath, Lock: $lockPath")
                    setWallpaper(context, wallpaperManager, homePath, WallpaperManager.FLAG_SYSTEM, isFolderMode)
                    setWallpaper(context, wallpaperManager, lockPath, WallpaperManager.FLAG_LOCK, isFolderMode)
                }

                else -> {
                    WorkerLogger.i(context, "Wallify", "Setting default (home) wallpaper")
                    val nonFacePath = getOrFetchNonFaceImagePath(context, imageSources, isFolderMode)
                    if (nonFacePath == null) {
                        WorkerLogger.e(context, "Wallify", "No suitable wallpapers found (all had faces or invalid, fetch failed).")
                        Log.e("Wallify", "No suitable wallpapers found (all had faces or invalid, fetch failed).")
                        return
                    }
                    WorkerLogger.i(context, "Wallify", "Selected: $nonFacePath")
                    Log.d("Wallify", "Setting default (home) wallpaper: $nonFacePath")
                    setWallpaper(context, wallpaperManager, nonFacePath, WallpaperManager.FLAG_SYSTEM, isFolderMode)
                }
            }

            WorkerLogger.i(context, "Wallify", "Wallpaper change completed successfully (mode=$wallpaperLocation, source=$wallpaperSource)")
            Log.d("Wallify", "Wallpaper change completed (mode=$wallpaperLocation, source=$wallpaperSource)")
        } catch (e: Exception) {
            WorkerLogger.e(context, "Wallify", "Error: ${e.message}")
            Log.e("Wallify", "Error setting wallpaper in background", e)
        } catch (e: Error) {
            WorkerLogger.e(context, "Wallify", "Fatal error: ${e.message}")
            Log.e("Wallify", "Fatal error setting wallpaper in background: ${e.message}", e)
        }
    }

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

    internal fun detectFocusPoint(context: Context, bitmap: Bitmap): Map<String, Float> {
        val centerX = bitmap.width / 2f
        val centerY = bitmap.height / 2f

        val faceDetector = getFaceDetector(context)
        if (faceDetector != null) {
            try {
                val mpImage = BitmapImageBuilder(bitmap).build()
                val results = faceDetector.detect(mpImage)
                val detections = results.detections()
                if (detections.isNotEmpty()) {
                    val box = detections.first().boundingBox()
                    val focusX = (box.left + box.right) / 2f
                    val focusY = (box.top + box.bottom) / 2f
                    Log.d("Wallify", "Focus point from face detection: ($focusX, $focusY)")
                    return mapOf("x" to focusX, "y" to focusY, "source" to 1f)
                }
            } catch (e: Exception) {
                Log.e("Wallify", "Face detection for focus failed: ${e.message}")
            }
        }

        val objDetector = getObjectDetector(context)
        if (objDetector != null) {
            try {
                val mpImage = BitmapImageBuilder(bitmap).build()
                val results = objDetector.detect(mpImage)
                val detections = results.detections()
                if (detections.isNotEmpty()) {
                    val box = detections.first().boundingBox()
                    val focusX = (box.left + box.right) / 2f
                    val focusY = (box.top + box.bottom) / 2f
                    Log.d("Wallify", "Focus point from object detection: ($focusX, $focusY)")
                    return mapOf("x" to focusX, "y" to focusY, "source" to 2f)
                }
            } catch (e: Exception) {
                Log.e("Wallify", "Object detection for focus failed: ${e.message}")
            }
        }

        Log.d("Wallify", "No face or object detected, using image center: ($centerX, $centerY)")
        return mapOf("x" to centerX, "y" to centerY, "source" to 0f)
    }

    private fun getNonFaceImagePath(context: Context, paths: MutableList<String>, isFolderMode: Boolean): String? {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val requiresNoFaces = prefs.getBoolean("flutter.constraint_no_faces", true)
        Log.d("Wallify", "getNonFaceImagePath: requiresNoFaces=$requiresNoFaces, isFolderMode=$isFolderMode")

        val iterator = paths.iterator()
        while (iterator.hasNext()) {
            val path = iterator.next()
            val bitmap = loadBitmapFromSource(context, path)
            if (bitmap == null) {
                Log.w("Wallify", "Skipping invalid image: $path")
                iterator.remove()
                if (!isFolderMode) {
                    removeUsedUrl(context, path, addToHistory = false)
                    removeUsedCachedPath(context, path)
                }
                continue
            }

            if (!requiresNoFaces) {
                return path
            }

            if (!imageHasFace(context, bitmap)) {
                Log.d("Wallify", "Selected wallpaper without faces: $path")
                return path
            } else {
                Log.d("Wallify", "Discarded face image: $path")
                iterator.remove()
                if (!isFolderMode) {
                    removeUsedUrl(context, path, addToHistory = false)
                }
            }
        }

        return null
    }

    private fun getOrFetchNonFaceImagePath(
        context: Context,
        imageSources: MutableList<String>,
        isFolderMode: Boolean,
        maxFetchRetries: Int = 2
    ): String? {
        var retriesLeft = maxFetchRetries
        while (true) {
            val path = getNonFaceImagePath(context, imageSources, isFolderMode)
            if (path != null) {
                return path
            }

            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val wallpaperSource = prefs.getString("flutter.wallpaperSource", "internet") ?: "internet"
            val sources = wallpaperSource.split(",").map { it.trim() }.filter { it.isNotEmpty() }.toSet()
            val isOnlyFolder = sources.size == 1 && sources.contains("folder")
            val hasInternet = !isOnlyFolder

            if (!hasInternet || retriesLeft <= 0) {
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

            val deviceWidth = (prefs.all["flutter.deviceWidth"] as? Int) ?: 1080
            val deviceHeight = (prefs.all["flutter.deviceHeight"] as? Int) ?: 1920

            WorkerLogger.i(context, "Wallify", "Fetching wallpapers tag=$tag, size=${deviceWidth}x$deviceHeight")
            Log.d("Wallify", "Fetching wallpapers with tag=$tag, size=${deviceWidth}x$deviceHeight")

            val wallhavenUrl =
                "https://wallhaven.cc/api/v1/search?q=$tag&categories=100&purity=100&ratios=portrait&sorting=random"
            urls.addAll(fetchFromWallhaven(wallhavenUrl))
            val unsplashUrl =
                "https://api.unsplash.com/photos/random?query=$tag&orientation=portrait&content_filter=high&count=15"
            urls.addAll(fetchFromUnsplash(unsplashUrl))
            val pixabayApiKey = prefs.getString("flutter.pixabay_api_key", null)
            if (!pixabayApiKey.isNullOrEmpty()) {
                val pixabayUrl =
                    "https://pixabay.com/api/?key=$pixabayApiKey&q=$tag&image_type=photo&orientation=vertical&safesearch=true"
                urls.addAll(fetchFromPixabay(pixabayUrl))
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

    private fun fetchFromUnsplash(apiUrl: String): List<String> {
        val urls = mutableListOf<String>()
        try {
            val connection = URL(apiUrl).openConnection() as HttpURLConnection
            connection.setRequestProperty("Authorization", "Client-ID yTBcYNAtnRHbrYMn2p4DrBiqzOAfdH9nyexQQtJWO-E")
            connection.connectTimeout = 15000
            connection.readTimeout = 15000
            val response = connection.inputStream.bufferedReader().readText()
            val data = org.json.JSONArray(response)
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

    private fun setWallpaper(context: Context, manager: WallpaperManager, imagePath: String, flag: Int, isFolderMode: Boolean = false) {
        WorkerLogger.i(context, "Wallify", "Loading image: $imagePath (flag=$flag)")
        val bitmap = loadBitmapFromSource(context, imagePath)
        if (bitmap == null) {
            WorkerLogger.e(context, "Wallify", "Failed to load image bitmap: $imagePath")
            Log.e("Wallify", "Failed to load image: $imagePath")
            return
        }

        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val widthValue = prefs.all["flutter.deviceWidth"]
            val heightValue = prefs.all["flutter.deviceHeight"]

            val deviceWidth = when (widthValue) {
                is Int -> widthValue
                is Long -> widthValue.toInt()
                is String -> widthValue.toIntOrNull() ?: bitmap.width
                else -> bitmap.width
            }
            val deviceHeight = when (heightValue) {
                is Int -> heightValue
                is Long -> heightValue.toInt()
                is String -> heightValue.toIntOrNull() ?: bitmap.height
                else -> bitmap.height
            }

            Log.d("Wallify", "Device dimensions from prefs: $deviceWidth x $deviceHeight")

            var resultBitmap = detectAndCropMainObject(context, bitmap, deviceWidth, deviceHeight)

            manager.setBitmap(resultBitmap, null, true, flag)
            Log.d("Wallify", "Wallpaper set successfully for flag=$flag")
            extractAndSaveWallpaperColors(context, resultBitmap)
            updateLastChangeTime(context)
            WallifyWidgetProvider.triggerUpdate(context)
            saveCurrentWallpaper(context, resultBitmap)
            if (!isFolderMode) {
                removeUsedUrl(context, imagePath)
                removeUsedCachedPath(context, imagePath)
            }

        } catch (e: Exception) {
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
        val detector = getObjectDetector(context)
        if (detector == null) {
            Log.d("Wallify", "Object detector unavailable, center-cropping.")
            return centerCropToAspect(bitmap, targetWidth, targetHeight)
        }
        return try {
            val mpImage = BitmapImageBuilder(bitmap).build()
            val results = detector.detect(mpImage)

            var resultBitmap = bitmap
            val detectedObjects = results.detections()

            if (detectedObjects.isNotEmpty()) {
                val obj = detectedObjects.first()
                val box: RectF = obj.boundingBox()
                Log.d("Wallify", "Detected object bounds: $box")

                val targetAspect = targetWidth.toDouble() / targetHeight.toDouble()
                val imgW = bitmap.width
                val imgH = bitmap.height

                val objCenterX = (box.left + box.right) / 2.0
                val objCenterY = (box.top + box.bottom) / 2.0

                var cropW: Int
                var cropH: Int
                val imgAspect = imgW.toDouble() / imgH.toDouble()

                if (imgAspect > targetAspect) {
                    cropH = imgH
                    cropW = (imgH * targetAspect).toInt()
                } else {
                    cropW = imgW
                    cropH = (imgW / targetAspect).toInt()
                }

                cropW = cropW.coerceAtMost(imgW)
                cropH = cropH.coerceAtMost(imgH)

                var cropLeft = (objCenterX - cropW / 2.0).toInt()
                var cropTop = (objCenterY - cropH / 2.0).toInt()

                cropLeft = cropLeft.coerceIn(0, imgW - cropW)
                cropTop = cropTop.coerceIn(0, imgH - cropH)

                Log.d("Wallify", "Smart crop: ${cropW}x${cropH} at ($cropLeft, $cropTop), object center: ($objCenterX, $objCenterY)")

                val cropped = Bitmap.createBitmap(bitmap, cropLeft, cropTop, cropW, cropH)
                resultBitmap = cropped.scale(targetWidth, targetHeight, true)
            } else {
                Log.d("Wallify", "No object detected, center-cropping full image.")
                resultBitmap = centerCropToAspect(bitmap, targetWidth, targetHeight)
            }

            resultBitmap
        } catch (e: Exception) {
            Log.e("Wallify", "Error during object detection: $e")
            centerCropToAspect(bitmap, targetWidth, targetHeight)
        } catch (e: Error) {
            Log.e("Wallify", "Native library error during object detection: ${e.message}", e)
            centerCropToAspect(bitmap, targetWidth, targetHeight)
        }
    }

    private fun saveCurrentWallpaper(context: Context, bitmap: android.graphics.Bitmap) {
        try {
            val file = java.io.File(context.filesDir, "live_wallpaper.jpg")
            val stream = java.io.FileOutputStream(file)
            bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 95, stream)
            stream.close()
            Log.d("Wallify", "Saved live wallpaper bitmap to ${file.absolutePath}")
        } catch (e: Exception) {
            Log.e("Wallify", "Failed to save live wallpaper bitmap", e)
        }
    }

    private fun centerCropToAspect(bitmap: Bitmap, targetWidth: Int, targetHeight: Int): Bitmap {
        val targetAspect = targetWidth.toDouble() / targetHeight.toDouble()
        val imgW = bitmap.width
        val imgH = bitmap.height
        val imgAspect = imgW.toDouble() / imgH.toDouble()

        val cropW: Int
        val cropH: Int
        if (imgAspect > targetAspect) {
            cropH = imgH
            cropW = (imgH * targetAspect).toInt().coerceAtMost(imgW)
        } else {
            cropW = imgW
            cropH = (imgW / targetAspect).toInt().coerceAtMost(imgH)
        }

        val cropLeft = (imgW - cropW) / 2
        val cropTop = (imgH - cropH) / 2

        val cropped = Bitmap.createBitmap(bitmap, cropLeft, cropTop, cropW, cropH)
        return cropped.scale(targetWidth, targetHeight, true)
    }

}
