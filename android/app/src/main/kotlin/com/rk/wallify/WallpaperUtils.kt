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
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.objects.ObjectDetection
import com.google.mlkit.vision.objects.defaults.ObjectDetectorOptions
import android.graphics.Rect
import android.graphics.Bitmap
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import org.json.JSONObject
import androidx.palette.graphics.Palette

object WallpaperUtils {
    private val imageExtensions = setOf("jpg", "jpeg", "png", "webp", "bmp", "gif")

    fun downloadAndSetWallpaperBackground(context: Context) {
        try {
            Log.d("Wallify", "Starting background wallpaper change (no Activity)")

            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val wallpaperSource = prefs.getString("flutter.wallpaperSource", "internet") ?: "internet"

            val imageSources = mutableListOf<String>()

            if (wallpaperSource == "folder") {
                val folderPath = prefs.getString("flutter.folderPath", null)
                if (folderPath.isNullOrEmpty()) {
                    Log.e("Wallify", "Folder source selected but no folder path set")
                    return
                }
                val folder = File(folderPath)
                if (!folder.exists() || !folder.isDirectory()) {
                    Log.e("Wallify", "Folder does not exist: $folderPath")
                    return
                }
                folder.listFiles { f -> f.isFile && f.extension.lowercase() in imageExtensions }
                    ?.forEach { imageSources.add(it.absolutePath) }
                if (imageSources.isEmpty()) {
                    Log.e("Wallify", "No image files found in folder: $folderPath")
                    return
                }
                Log.d("Wallify", "📁 Found ${imageSources.size} images in folder: $folderPath")
            } else {
                // Try cached local paths first (offline cache downloaded by Flutter)
                val cachedPaths = getCachedLocalPaths(context)
                if (cachedPaths.isNotEmpty()) {
                    Log.d("Wallify", "Using ${cachedPaths.size} locally cached wallpapers")
                    imageSources.addAll(cachedPaths)
                } else {
                    // Fall back to URL-based fetching
                    var imageJsonString = prefs.getString("flutter.imageUrls", "[]") ?: "[]"
                    if (imageJsonString.contains("![")) {
                        imageJsonString = imageJsonString.substringAfter("!")
                    }
                    val imageUrls = try {
                        val jsonArray = org.json.JSONArray(imageJsonString)
                        val urls = mutableListOf<String>()
                        for (i in 0 until jsonArray.length()) {
                            val wallpaperObj = org.json.JSONObject(jsonArray.getString(i))
                            val url = wallpaperObj.optString("url", "")
                            if (url.isNotEmpty()) urls.add(url)
                        }
                        urls.toMutableList()
                    } catch (e: Exception) {
                        Log.e("Wallify", "Error parsing flutter.imageUrls JSON", e)
                        mutableListOf()
                    }

                    if (imageUrls.isEmpty()) {
                        Log.w("Wallify", "No image URLs found, fetching new ones from APIs...")
                        val fetched = fetchImagesFromAllSources(context)
                        if (fetched.isEmpty()) {
                            Log.e("Wallify", "Could not fetch any wallpapers, aborting.")
                            return
                        } else {
                            imageUrls.addAll(fetched)
                            Log.d("Wallify", "Added ${fetched.size} new wallpapers from API")
                        }
                    }
                    imageSources.addAll(imageUrls)
                }
            }

            val wallpaperLocationValue = prefs.all["flutter.wallpaperLocation"]
            val wallpaperLocation = when (wallpaperLocationValue) {
                is Int -> wallpaperLocationValue
                is Long -> wallpaperLocationValue.toInt()
                is String -> wallpaperLocationValue.toIntOrNull() ?: 3
                else -> 3
            }
            Log.e("Wallify", wallpaperLocation.toString())

            val wallpaperManager = WallpaperManager.getInstance(context)
            val isFolderMode = wallpaperSource == "folder"

            when (wallpaperLocation) {
                1 -> {
                    val nonFacePath = getNonFaceImagePath(context, imageSources, isFolderMode)
                    if (nonFacePath == null) {
                        Log.e("Wallify", "No suitable wallpapers found (all had faces).")
                        return
                    }
                    setWallpaper(context, wallpaperManager, nonFacePath, WallpaperManager.FLAG_SYSTEM, isFolderMode)
                }

                2 -> {
                    val nonFacePath = getNonFaceImagePath(context, imageSources, isFolderMode)
                    if (nonFacePath == null) {
                        Log.e("Wallify", "No suitable wallpapers found (all had faces).")
                        return
                    }
                    setWallpaper(context, wallpaperManager, nonFacePath, WallpaperManager.FLAG_LOCK, isFolderMode)
                }

                3 -> {
                    if (imageSources.size < 2) {
                        Log.w("Wallify", "Not enough wallpapers, using same image for both.")
                        val nonFacePath = getNonFaceImagePath(context, imageSources, isFolderMode)
                        if (nonFacePath == null) {
                            Log.e("Wallify", "No suitable wallpapers found (all had faces).")
                            return
                        }
                        setWallpaper(context, wallpaperManager, nonFacePath, WallpaperManager.FLAG_SYSTEM, isFolderMode)
                        setWallpaper(context, wallpaperManager, nonFacePath, WallpaperManager.FLAG_LOCK, isFolderMode)
                    } else {
                        val nonFacePath = getNonFaceImagePath(context, imageSources, isFolderMode)
                        if (nonFacePath == null) {
                            Log.e("Wallify", "No suitable wallpapers found (all had faces).")
                            return
                        }
                        var lockPath = getNonFaceImagePath(context, imageSources, isFolderMode)
                        if (lockPath == null) {
                            Log.e("Wallify", "No suitable wallpapers found (all had faces).")
                            return
                        }
                        while (nonFacePath == lockPath && imageSources.size > 1) {
                            lockPath = imageSources.random()
                        }
                        setWallpaper(context, wallpaperManager, nonFacePath, WallpaperManager.FLAG_SYSTEM, isFolderMode)
                        setWallpaper(context, wallpaperManager, lockPath, WallpaperManager.FLAG_LOCK, isFolderMode)
                    }
                }

                else -> {
                    val nonFacePath = getNonFaceImagePath(context, imageSources, isFolderMode)
                    if (nonFacePath == null) {
                        Log.e("Wallify", "No suitable wallpapers found (all had faces).")
                        return
                    }
                    Log.d("Wallify", "Setting default (home) wallpaper: $nonFacePath")
                    setWallpaper(context, wallpaperManager, nonFacePath, WallpaperManager.FLAG_SYSTEM, isFolderMode)
                }
            }

            Log.d("Wallify", "Wallpaper change completed (mode=$wallpaperLocation, source=$wallpaperSource)")
        } catch (e: Exception) {
            Log.e("Wallify", "Error setting wallpaper in background", e)
        }
    }

    private fun imageHasFace(context: Context, bitmap: Bitmap): Boolean {
        return try {
            val options = FaceDetectorOptions.Builder()
                .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE)
                .enableTracking()
                .build()

            val detector = FaceDetection.getClient(options)
            val image = InputImage.fromBitmap(bitmap, 0)

            val task = detector.process(image)
            val faces = Tasks.await(task)

            val hasFace = faces.isNotEmpty()
            if (hasFace) {
                Log.d("Wallify", "🚫 Face detected — skipping this wallpaper.")
            } else {
                Log.d("Wallify", "✅ No faces detected — safe to use.")
            }

            hasFace
        } catch (e: Exception) {
            Log.e("Wallify", "Error detecting faces: ${e.message}", e)
            false
        }
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
                    removeUsedUrl(context, path)
                }
            }
        }

        return null
    }

    private fun fetchImagesFromAllSources(context: Context): List<String> {
        val urls = mutableListOf<String>()
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val tag = prefs.getString("flutter.random_tag", "nature") ?: "nature"
            val deviceWidth = (prefs.all["flutter.deviceWidth"] as? Int) ?: 1080
            val deviceHeight = (prefs.all["flutter.deviceHeight"] as? Int) ?: 1920

            Log.d("Wallify", "🌐 Fetching wallpapers with tag=$tag, size=${deviceWidth}x$deviceHeight")

            val wallhavenUrl =
                "https://wallhaven.cc/api/v1/search?q=$tag&categories=100&purity=100&ratios=portrait&sorting=random"
            urls.addAll(fetchFromWallhaven(wallhavenUrl))
            val unsplashUrl =
                "https://api.unsplash.com/photos/random?query=$tag&orientation=portrait&content_filter=high&count=15"
            urls.addAll(fetchFromUnsplash(unsplashUrl))
            val pixabayUrl =
                "https://pixabay.com/api/?key=52028006-a7e910370a5d0158c371bb06a&q=$tag&image_type=photo&orientation=vertical&safesearch=true"
            urls.addAll(fetchFromPixabay(pixabayUrl))

            if (urls.isEmpty()) {
                Log.w("Wallify", "⚠️ No wallpapers found from any source")
            } else {
                val jsonArray = JSONArray()
                urls.forEach { url ->
                    val obj = org.json.JSONObject()
                    obj.put("url", url)
                    jsonArray.put(obj)
                }
                prefs.edit().putString("flutter.imageUrls", jsonArray.toString()).apply()
                Log.d("Wallify", "✅ Saved ${urls.size} image URLs to SharedPreferences")
            }
        } catch (e: Exception) {
            Log.e("Wallify", "❌ Error fetching images: ${e.message}", e)
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
        val bitmap = loadBitmapFromSource(context, imagePath)
        if (bitmap == null) {
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

        Log.d("Wallify", "🕒 Updated lastWallpaperChange = $now")
    }

    private fun removeUsedUrl(context: Context, usedUrl: String) {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

            var imageJsonString = prefs.getString("flutter.imageUrls", "[]") ?: "[]"
            if (imageJsonString.contains("![")) {
                imageJsonString = imageJsonString.substringAfter("!")
            }
            val imageList = JSONArray(imageJsonString)

            val historyJsonString = prefs.getString("flutter.wallpaperHistory", "[]") ?: "[]"
            val historyList = JSONArray(historyJsonString)

            Log.d("Wallify", "🧹 Removing used wallpaper URL: $usedUrl")

            // Pull the used wallpaper out of the pending imageUrls list and
            // keep a reference to it so it can be moved into history.
            val newImageList = JSONArray()
            var movedObject: JSONObject? = null

            for (i in 0 until imageList.length()) {
                val itemStr = imageList.getString(i)
                val item = JSONObject(itemStr)
                val url = item.optString("url", "")

                if (url == usedUrl && movedObject == null) {
                    movedObject = item
                    Log.d("Wallify", "➡️ Moved to history: $item")
                } else {
                    newImageList.put(itemStr)
                }
            }

            prefs.edit().putString("flutter.imageUrls", newImageList.toString()).apply()

            // The used wallpaper may not be in imageUrls anymore (e.g. it was
            // already consumed by a previous set in the same run). Still record
            // it in history using at least its url.
            val movedEntry = movedObject ?: JSONObject().put("url", usedUrl)
            val movedUrl = movedEntry.optString("url", usedUrl)

            // Rebuild history newest-first, dropping any previous entry for the
            // same wallpaper so it moves to the top instead of duplicating.
            val newHistory = JSONArray()
            newHistory.put(movedEntry)
            for (i in 0 until historyList.length()) {
                val existing = historyList.optJSONObject(i) ?: continue
                if (existing.optString("url", "") == movedUrl) continue
                newHistory.put(existing)
            }

            // Keep history from growing without bound.
            val maxHistory = 100
            val cappedHistory = if (newHistory.length() > maxHistory) {
                JSONArray().apply {
                    for (i in 0 until maxHistory) put(newHistory.get(i))
                }
            } else {
                newHistory
            }

            prefs.edit().putString("flutter.wallpaperHistory", cappedHistory.toString()).apply()

            Log.d("Wallify", "📌 History size: ${cappedHistory.length()}")
            Log.d("Wallify", "📌 Remaining imageUrls: ${newImageList.length()}")

        } catch (e: Exception) {
            Log.e("Wallify", "Error updating history: ${e.message}", e)
        }
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
            val image = InputImage.fromBitmap(bitmap, 0)
            val options = ObjectDetectorOptions.Builder()
                .setDetectorMode(ObjectDetectorOptions.SINGLE_IMAGE_MODE)
                .enableMultipleObjects()
                .enableClassification()
                .build()
            val detector = ObjectDetection.getClient(options)

            var resultBitmap = bitmap
            val task = detector.process(image)
                .addOnSuccessListener { detectedObjects ->
                    if (detectedObjects.isNotEmpty()) {
                        val obj = detectedObjects.first()
                        val box: Rect = obj.boundingBox
                        Log.d("Wallify", "🎯 Detected object bounds: $box")

                        // Center the crop viewport on the detected object
                        // while maintaining the target device aspect ratio
                        val targetAspect = targetWidth.toDouble() / targetHeight.toDouble()
                        val imgW = bitmap.width
                        val imgH = bitmap.height

                        // Object center point
                        val objCenterX = (box.left + box.right) / 2.0
                        val objCenterY = (box.top + box.bottom) / 2.0

                        // Determine crop dimensions that maintain device aspect ratio
                        // Start with the full image dimension and compute the other
                        var cropW: Int
                        var cropH: Int
                        val imgAspect = imgW.toDouble() / imgH.toDouble()

                        if (imgAspect > targetAspect) {
                            // Image is wider than target — use full height, compute width
                            cropH = imgH
                            cropW = (imgH * targetAspect).toInt()
                        } else {
                            // Image is taller than target — use full width, compute height
                            cropW = imgW
                            cropH = (imgW / targetAspect).toInt()
                        }

                        // Ensure crop doesn't exceed image bounds
                        cropW = cropW.coerceAtMost(imgW)
                        cropH = cropH.coerceAtMost(imgH)

                        // Position the crop rect centered on the detected object
                        var cropLeft = (objCenterX - cropW / 2.0).toInt()
                        var cropTop = (objCenterY - cropH / 2.0).toInt()

                        // Clamp to image boundaries
                        cropLeft = cropLeft.coerceIn(0, imgW - cropW)
                        cropTop = cropTop.coerceIn(0, imgH - cropH)

                        Log.d("Wallify", "📐 Smart crop: ${cropW}x${cropH} at ($cropLeft, $cropTop), object center: ($objCenterX, $objCenterY)")

                        val cropped = Bitmap.createBitmap(bitmap, cropLeft, cropTop, cropW, cropH)
                        resultBitmap = cropped.scale(targetWidth, targetHeight, true)
                    } else {
                        Log.d("Wallify", "⚠️ No object detected, center-cropping full image.")
                        resultBitmap = centerCropToAspect(bitmap, targetWidth, targetHeight)
                    }
                }
                .addOnFailureListener { e ->
                    Log.e("Wallify", "❌ Object detection failed: $e")
                    resultBitmap = centerCropToAspect(bitmap, targetWidth, targetHeight)
                }

            Tasks.await(task)
            resultBitmap
        } catch (e: Exception) {
            Log.e("Wallify", "Error during object detection: $e")
            centerCropToAspect(bitmap, targetWidth, targetHeight)
        }
    }

    /** Simple center-crop fallback that maintains target aspect ratio */
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
