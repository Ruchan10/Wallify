package com.rk.wallify

import android.content.Context
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.ListenableWorker.Result
import androidx.work.NetworkType
import androidx.work.Constraints
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.ExistingWorkPolicy
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

class WallpaperCacheWorker(context: Context, workerParams: WorkerParameters) : Worker(context, workerParams) {

    override fun doWork(): Result {
        return try {
            Log.d("WallpaperCacheWorker", "Starting wallpaper cache work")

            // Get image URLs from preferences
            val imageUrls = getImageUrlsFromPrefs()
            Log.d("WallpaperCacheWorker", "Found ${imageUrls.size} image URLs to cache")

            if (imageUrls.isEmpty()) {
                Log.w("WallpaperCacheWorker", "No image URLs found in preferences")
                return Result.success()
            }

            // Limit to maximum 10 downloads to prevent hanging
            val urlsToProcess = imageUrls.take(10)
            Log.d("WallpaperCacheWorker", "Processing ${urlsToProcess.size} URLs (limited to prevent timeout)")

            // Download and cache wallpapers with timeout protection
            val cachedFiles = mutableListOf<String>()
            for (url in urlsToProcess) {
                try {
                    Log.d("WallpaperCacheWorker", "Attempting to cache: $url")
                    val cachedPath = downloadAndCacheWallpaper(url)
                    if (cachedPath != null) {
                        cachedFiles.add(cachedPath)
                        Log.d("WallpaperCacheWorker", "Successfully cached: $cachedPath")
                    } else {
                        Log.w("WallpaperCacheWorker", "Failed to cache: $url")
                    }
                } catch (e: Exception) {
                    Log.e("WallpaperCacheWorker", "Error caching wallpaper: $url", e)
                    // Continue with next URL instead of failing completely
                }
            }

            Log.d("WallpaperCacheWorker", "Successfully cached ${cachedFiles.size}/${urlsToProcess.size} wallpapers")
            Result.success()

        } catch (e: Exception) {
            Log.e("WallpaperCacheWorker", "Error in wallpaper cache worker", e)
            Result.failure()
        }
    }

    private fun getImageUrlsFromPrefs(): List<String> {
        val prefs = applicationContext.getSharedPreferences("wallify_prefs", Context.MODE_PRIVATE)
        val jsonStrings = prefs.getStringSet("imageUrls", emptySet()) ?: emptySet()

        return jsonStrings.mapNotNull { jsonString ->
            try {
                // The URLs are stored as plain strings, not JSON objects
                // So we don't need to parse JSON, just use the string directly
                jsonString.takeIf { it.isNotEmpty() && it.startsWith("http") }
            } catch (e: Exception) {
                Log.e("WallpaperCacheWorker", "Error parsing URL: $jsonString", e)
                null
            }
        }
    }

    private fun downloadAndCacheWallpaper(imageUrl: String): String? {
        return try {
            Log.d("WallpaperCacheWorker", "Downloading wallpaper: $imageUrl")

            val url = URL(imageUrl)
            val connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = "GET"
            connection.connectTimeout = 10000 // 10 seconds
            connection.readTimeout = 10000   // 10 seconds
            connection.setRequestProperty("User-Agent", "Wallify-App")

            val inputStream = connection.inputStream
            val bytes = inputStream.readBytes()
            inputStream.close()

            if (bytes.size < 1000) { // Skip very small files
                Log.w("WallpaperCacheWorker", "Downloaded file too small (${bytes.size} bytes), skipping")
                return null
            }

            Log.d("WallpaperCacheWorker", "Downloaded ${bytes.size} bytes")

            // Save to cache directory with unique name
            val cacheDir = applicationContext.cacheDir
            val fileName = "wallpaper_cache_${System.currentTimeMillis()}.jpg"
            val cachedFile = File(cacheDir, fileName)
            cachedFile.writeBytes(bytes)

            Log.d("WallpaperCacheWorker", "Cached to: ${cachedFile.absolutePath}")
            cachedFile.absolutePath

        } catch (e: Exception) {
            Log.e("WallpaperCacheWorker", "Error downloading wallpaper: $imageUrl", e)
            null
        }
    }

    companion object {
        const val WORK_NAME = "wallpaper_cache_work"
    }
}
