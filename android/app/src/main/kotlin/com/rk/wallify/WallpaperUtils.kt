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
                urls
            } catch (e: Exception) {
                Log.e("Wallify", "Error parsing flutter.imageUrls JSON", e)
                emptyList()
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
                Log.w("Wallify", "No image URLs found in SharedPreferences")
                return
            }

            val wallpaperManager = WallpaperManager.getInstance(context)

            when (wallpaperLocation) {
                // 🔹 Case 1: Home screen only
                1 -> {
                    val homeUrl = imageUrls.random()
                    Log.d("Wallify", "Setting home wallpaper: $homeUrl")
                    setWallpaper(context, wallpaperManager, homeUrl, WallpaperManager.FLAG_SYSTEM)
                }

                // 🔹 Case 2: Lock screen only
                2 -> {
                    val lockUrl = imageUrls.random()
                    Log.d("Wallify", "Setting lock wallpaper: $lockUrl")
                    setWallpaper(context, wallpaperManager, lockUrl, WallpaperManager.FLAG_LOCK)
                }

                // 🔹 Case 3: Both — different wallpapers for home & lock
                3 -> {
                    if (imageUrls.size < 2) {
                        Log.w("Wallify", "Not enough wallpapers, using same image for both.")
                        val url = imageUrls.random()
                        setWallpaper(context, wallpaperManager, url, WallpaperManager.FLAG_SYSTEM)
                        setWallpaper(context, wallpaperManager, url, WallpaperManager.FLAG_LOCK)
                    } else {
                        var homeUrl = imageUrls.random()
                        var lockUrl = imageUrls.random()
                        // Ensure different images
                        while (homeUrl == lockUrl && imageUrls.size > 1) {
                            lockUrl = imageUrls.random()
                        }
                        Log.d("Wallify", "Setting home wallpaper: $homeUrl")
                        Log.d("Wallify", "Setting lock wallpaper: $lockUrl")

                        setWallpaper(context, wallpaperManager, homeUrl, WallpaperManager.FLAG_SYSTEM)
                        setWallpaper(context, wallpaperManager, lockUrl, WallpaperManager.FLAG_LOCK)
                    }
                }

                else -> {
                    val url = imageUrls.random()
                    Log.d("Wallify", "Setting default (home) wallpaper: $url")
                    setWallpaper(context, wallpaperManager, url, WallpaperManager.FLAG_SYSTEM)
                }
            }

            Log.d("Wallify", "✅ Wallpaper change completed (mode=$wallpaperLocation)")
            recordStatus(context, "✅ Wallpaper changed successfully in background.")
            updateLastChangeTime(context)
        } catch (e: Exception) {
            Log.e("Wallify", "Error setting wallpaper in background", e)
            recordStatus(context, "❌ Unable to change wallpaper: ${e.message}")
        }
    }

    // 🔹 Helper: download + apply one wallpaper
    private fun setWallpaper(context: Context, manager: WallpaperManager, imageUrl: String, flag: Int) {
        val tempFile = downloadImage(context, imageUrl)
        if (tempFile == null) {
            Log.e("Wallify", "Failed to download image: $imageUrl")
            return
        }

        try {
            val bitmap = BitmapFactory.decodeFile(tempFile.absolutePath)
            manager.setBitmap(bitmap, null, true, flag)
            Log.d("Wallify", "✅ Wallpaper set successfully for flag=$flag")
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

    // 🧾 Record a new entry in statusHistory
    private fun recordStatus(context: Context, message: String) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val existingJson = prefs.getString("flutter.statusHistory", "[]") ?: "[]"

        try {
            val jsonArray = JSONArray(existingJson)
            val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
            val timestampedMessage = "${dateFormat.format(Date())} - $message"

            jsonArray.put(timestampedMessage)
            prefs.edit().putString("flutter.statusHistory", jsonArray.toString()).apply()

            Log.d("Wallify", "📜 Added status: $timestampedMessage")
        } catch (e: Exception) {
            Log.e("Wallify", "Error updating statusHistory", e)
        }
    }
}
