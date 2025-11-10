package com.rk.wallify

import android.app.WallpaperManager
import android.content.Context
import android.graphics.BitmapFactory
import android.util.Log
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import kotlin.random.Random

object WallpaperUtils {

    fun downloadAndSetWallpaperBackground(context: Context) {
        try {
            Log.d("Wallify", "Starting background wallpaper change (no Activity)")

            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val imageUrls = prefs.getStringSet("flutter.imageUrls", emptySet())?.toList() ?: emptyList()
            val wallpaperLocation = prefs.getInt("flutter.wallpaperLocation", 2)

            if (imageUrls.isEmpty()) {
                Log.w("Wallify", "No image URLs found in SharedPreferences")
                return
            }

            // Pick a random image URL
            val randomUrl = imageUrls.random()
            Log.d("Wallify", "Selected random wallpaper URL: $randomUrl")

            // Download and set wallpaper directly
            val wallpaperManager = WallpaperManager.getInstance(context)
            val tempFile = downloadImage(context, randomUrl)
            if (tempFile == null) {
                Log.e("Wallify", "Failed to download image: $randomUrl")
                return
            }

            val bitmap = BitmapFactory.decodeFile(tempFile.absolutePath)

            when (wallpaperLocation) {
                0 -> wallpaperManager.setBitmap(bitmap, null, true, WallpaperManager.FLAG_SYSTEM)
                1 -> wallpaperManager.setBitmap(bitmap, null, true, WallpaperManager.FLAG_LOCK)
                2, 3 -> {
                    wallpaperManager.setBitmap(bitmap, null, true, WallpaperManager.FLAG_SYSTEM)
                    wallpaperManager.setBitmap(bitmap, null, true, WallpaperManager.FLAG_LOCK)
                }
                else -> wallpaperManager.setBitmap(bitmap, null, true, WallpaperManager.FLAG_SYSTEM)
            }

            Log.d("Wallify", "✅ Wallpaper set successfully (location=$wallpaperLocation)")
            tempFile.delete()

        } catch (e: Exception) {
            Log.e("Wallify", "Error setting wallpaper in background", e)
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
}
