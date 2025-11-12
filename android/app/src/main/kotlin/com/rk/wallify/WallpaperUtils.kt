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

object WallpaperUtils {
    fun downloadAndSetWallpaperBackground(context: Context) {
        try {
            Log.d("Wallify", "Starting background wallpaper change (no Activity)")

            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
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

            val wallpaperLocationValue = prefs.all["flutter.wallpaperLocation"]
            val wallpaperLocation = when (wallpaperLocationValue) {
                is Int -> wallpaperLocationValue
                is Long -> wallpaperLocationValue.toInt()
                is String -> wallpaperLocationValue.toIntOrNull() ?: 3
                else -> 3
            }
            Log.e("Wallify", wallpaperLocation.toString())

            if (imageUrls.isEmpty()) {
                Log.w("Wallify", "⚠️ No image URLs found, fetching new ones from APIs...")
                val fetched = fetchImagesFromAllSources(context)
                if (fetched.isEmpty()) {
                    Log.e("Wallify", "❌ Could not fetch any wallpapers, aborting.")
                    return
                } else {
                    imageUrls.addAll(fetched)
                    Log.d("Wallify", "🌄 Added ${fetched.size} new wallpapers from API")
                }
            }


            val wallpaperManager = WallpaperManager.getInstance(context)

            when (wallpaperLocation) {
                // 🔹 Case 1: Home screen only
                1 -> {
                    val nonFaceUrl = getNonFaceImageUrl(context, imageUrls)
                    if (nonFaceUrl == null) {
                        Log.e("Wallify", "❌ No suitable wallpapers found (all had faces).")
                        return
                    }
                    setWallpaper(context, wallpaperManager, nonFaceUrl, WallpaperManager.FLAG_SYSTEM)
                }

                // 🔹 Case 2: Lock screen only
                2 -> {
                    val nonFaceUrl = getNonFaceImageUrl(context, imageUrls)
                    if (nonFaceUrl == null) {
                        Log.e("Wallify", "❌ No suitable wallpapers found (all had faces).")
                        return
                    }
                    setWallpaper(context, wallpaperManager, nonFaceUrl, WallpaperManager.FLAG_LOCK)
                }

                // 🔹 Case 3: Both — different wallpapers for home & lock
                3 -> {
                    if (imageUrls.size < 2) {
                        Log.w("Wallify", "Not enough wallpapers, using same image for both.")
                        val nonFaceUrl = getNonFaceImageUrl(context, imageUrls)
                        if (nonFaceUrl == null) {
                            Log.e("Wallify", "❌ No suitable wallpapers found (all had faces).")
                            return
                        }
                        setWallpaper(context, wallpaperManager, nonFaceUrl, WallpaperManager.FLAG_SYSTEM)
                        setWallpaper(context, wallpaperManager, nonFaceUrl, WallpaperManager.FLAG_LOCK)
                    } else {
                        val nonFaceUrl = getNonFaceImageUrl(context, imageUrls)
                        if (nonFaceUrl == null) {
                            Log.e("Wallify", "❌ No suitable wallpapers found (all had faces).")
                            return
                        }
                        var lockUrl = getNonFaceImageUrl(context, imageUrls)
                        if (lockUrl == null) {
                            Log.e("Wallify", "❌ No suitable wallpapers found (all had faces).")
                            return
                        }
                        // Ensure different images
                        while (nonFaceUrl == lockUrl && imageUrls.size > 1) {
                            lockUrl = imageUrls.random()
                        }

                        setWallpaper(context, wallpaperManager, nonFaceUrl, WallpaperManager.FLAG_SYSTEM)
                        setWallpaper(context, wallpaperManager, lockUrl, WallpaperManager.FLAG_LOCK)
                    }
                }

                else -> {
                    val nonFaceUrl = getNonFaceImageUrl(context, imageUrls)
                    if (nonFaceUrl == null) {
                        Log.e("Wallify", "❌ No suitable wallpapers found (all had faces).")
                        return
                    }
                    Log.d("Wallify", "Setting default (home) wallpaper: $nonFaceUrl")
                    setWallpaper(context, wallpaperManager, nonFaceUrl, WallpaperManager.FLAG_SYSTEM)
                }
            }

            Log.d("Wallify", "✅ Wallpaper change completed (mode=$wallpaperLocation)")
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

    private fun getNonFaceImageUrl(context: Context, imageUrls: MutableList<String>): String? {
        val iterator = imageUrls.iterator()
        while (iterator.hasNext()) {
            val url = iterator.next()
            val tempFile = downloadImage(context, url)
            if (tempFile == null) {
                Log.w("Wallify", "⚠️ Skipping invalid image: $url")
                iterator.remove()
                continue
            }

            val bitmap = BitmapFactory.decodeFile(tempFile.absolutePath)
            tempFile.delete()

            if (bitmap == null) {
                iterator.remove()
                continue
            }

            if (!imageHasFace(context, bitmap)) {
                Log.d("Wallify", "✅ Selected wallpaper without faces: $url")
                return url
            } else {
                Log.d("Wallify", "🚫 Discarded face image: $url")
                iterator.remove()
                removeUsedUrl(context, url)
            }
        }

        return null // none found
    }

    private fun fetchImagesFromAllSources(context: Context): List<String> {
        val urls = mutableListOf<String>()
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val tag = prefs.getString("flutter.random_tag", "nature") ?: "nature"
            val deviceWidth = (prefs.all["flutter.deviceWidth"] as? Int) ?: 1080
            val deviceHeight = (prefs.all["flutter.deviceHeight"] as? Int) ?: 1920

            Log.d("Wallify", "🌐 Fetching wallpapers with tag=$tag, size=${deviceWidth}x$deviceHeight")

            // 1️⃣ Wallhaven
            val wallhavenUrl =
                "https://wallhaven.cc/api/v1/search?q=$tag&categories=100&purity=100&ratios=portrait&atleast=${deviceWidth}x$deviceHeight&sorting=random"
            urls.addAll(fetchFromWallhaven(wallhavenUrl))

            // 2️⃣ Unsplash
            val unsplashUrl =
                "https://api.unsplash.com/photos/random?query=$tag&orientation=portrait&content_filter=high&count=10"
            urls.addAll(fetchFromUnsplash(unsplashUrl))

            // 3️⃣ Pixabay
            val pixabayUrl =
                "https://pixabay.com/api/?key=52028006-a7e910370a5d0158c371bb06a&q=$tag&image_type=photo&orientation=vertical&min_width=$deviceWidth&min_height=$deviceHeight&safesearch=true"
            urls.addAll(fetchFromPixabay(pixabayUrl))

            if (urls.isEmpty()) {
                Log.w("Wallify", "⚠️ No wallpapers found from any source")
            } else {
                // Save to shared prefs
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

    private fun setWallpaper(context: Context, manager: WallpaperManager, imageUrl: String, flag: Int) {
        val tempFile = downloadImage(context, imageUrl)
        if (tempFile == null) {
            Log.e("Wallify", "Failed to download image: $imageUrl")
            return
        }

        try {
            var bitmap = BitmapFactory.decodeFile(tempFile.absolutePath)
            if (bitmap == null) {
                Log.e("Wallify", "Bitmap decode failed: $imageUrl")
                return
            }

            // 🔹 Read device size from SharedPreferences
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

            Log.d("Wallify", "📏 Device dimensions from prefs: $deviceWidth x $deviceHeight")

            // 🔹 Detect and crop object before setting wallpaper
            bitmap = detectAndCropMainObject(context, bitmap, deviceWidth, deviceHeight)

            manager.setBitmap(bitmap, null, true, flag)
            Log.d("Wallify", "✅ Wallpaper set successfully for flag=$flag")
            updateLastChangeTime(context)
            removeUsedUrl(context, imageUrl)

        } catch (e: Exception) {
            Log.e("Wallify", "Error setting wallpaper from $imageUrl", e)
        } finally {
            tempFile.delete()
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

            val jsonArray = JSONArray(imageJsonString)
            Log.d("Wallify", "🧹 Removed used wallpaper (STARTING: ${jsonArray.length()})")
            val newArray = JSONArray()

            for (i in 0 until jsonArray.length()) {
                val item = org.json.JSONObject(jsonArray.getString(i))
                val url = item.optString("url", "")
                if (url != usedUrl) {
                    newArray.put(item)
                }
            }

            prefs.edit().putString("flutter.imageUrls", newArray.toString()).apply()
            Log.d("Wallify", "🧹 Removed used wallpaper URL: $usedUrl (remaining: ${newArray.length()})")

        } catch (e: Exception) {
            Log.e("Wallify", "Error removing used URL: ${e.message}", e)
        }
    }


    private fun detectAndCropMainObject(
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
                .enableClassification() // optional
                .build()
            val detector = ObjectDetection.getClient(options)

            var resultBitmap = bitmap
            val task = detector.process(image)
                .addOnSuccessListener { detectedObjects ->
                    if (detectedObjects.isNotEmpty()) {
                        val obj = detectedObjects.first()
                        val box: Rect = obj.boundingBox
                        Log.d("Wallify", "🎯 Detected object bounds: $box")

                        // Crop within image bounds
                        val left = box.left.coerceAtLeast(0)
                        val top = box.top.coerceAtLeast(0)
                        val right = box.right.coerceAtMost(bitmap.width)
                        val bottom = box.bottom.coerceAtMost(bitmap.height)

                        val cropped = Bitmap.createBitmap(bitmap, left, top, right - left, bottom - top)

                        // Scale cropped image to device screen ratio
                        resultBitmap = cropped.scale(targetWidth, targetHeight, true)
                    } else {
                        Log.d("Wallify", "⚠️ No object detected, using full image.")
                        resultBitmap = bitmap.scale(targetWidth, targetHeight, true)
                    }
                }
                .addOnFailureListener { e ->
                    Log.e("Wallify", "❌ Object detection failed: $e")
                    resultBitmap = bitmap.scale(targetWidth, targetHeight, true)
                }

            // Wait for ML task (blocking)
            Tasks.await(task)
            resultBitmap
        } catch (e: Exception) {
            Log.e("Wallify", "Error during object detection: $e")
            bitmap.scale(targetWidth, targetHeight, true)
        }
    }

}
