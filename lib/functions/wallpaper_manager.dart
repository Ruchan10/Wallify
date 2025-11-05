import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

// Wallpaper Manager - Simplified to work with native Android workers
class WallpaperManager {
  static const platform = MethodChannel('wallpaper_channel');

  // Set wallpaper immediately from URL (downloads and sets)
  static Future<String> fetchAndSetWallpaper({
    required String imageUrl,
    required int wallpaperLocation,
    bool changeNow = false,
  }) async {
    try {
      debugPrint("Setting wallpaper from URL: $imageUrl, Location: $wallpaperLocation");

      final result = await platform.invokeMethod('downloadAndSetWallpaper', {
        'imageUrl': imageUrl,
        'wallpaperLocation': wallpaperLocation,
      });
      debugPrint("RESULT:- $result ==================================");
      return result.toString();
    } catch (e) {
      debugPrint("Error setting wallpaper from URL: $e");
      throw Exception("Failed to set wallpaper: $e");
    }
  }

  // Set wallpaper immediately from cached file
  static Future<String> setWallpaperFromCachedFile({
    required String filePath,
    required int wallpaperLocation,
  }) async {
    try {
      debugPrint("Setting wallpaper from cached file: $filePath");

      final result = await platform.invokeMethod('setWallpaperFromFile', {
        'filePath': filePath,
        'wallpaperLocation': wallpaperLocation,
      });

      return result.toString();
    } catch (e) {
      debugPrint("Error setting wallpaper from cached file: $e");
      throw Exception("Failed to set wallpaper: $e");
    }
  }

  // Set different wallpapers for home and lock screens
  static Future<String> setDualWallpapers({
    required String homeFilePath,
    required String lockFilePath,
  }) async {
    try {
      debugPrint("Setting dual wallpapers - Home: $homeFilePath, Lock: $lockFilePath");

      final result = await platform.invokeMethod('setDualWallpapers', {
        'homeFilePath': homeFilePath,
        'lockFilePath': lockFilePath,
      });

      return result.toString();
    } catch (e) {
      debugPrint("Error setting dual wallpapers: $e");
      throw Exception("Failed to set dual wallpapers: $e");
    }
  }

  // Trigger immediate wallpaper change using native worker
  static Future<String> triggerWallpaperChange() async {
    try {
      debugPrint("Triggering immediate wallpaper change");

      final result = await platform.invokeMethod('triggerWallpaperChange');
      return result.toString();
    } catch (e) {
      debugPrint("Error triggering wallpaper change: $e");
      throw Exception("Failed to trigger wallpaper change: $e");
    }
  }

  // Start caching process using native worker
  static Future<String> startCaching() async {
    try {
      debugPrint("Starting wallpaper caching process");

      final result = await platform.invokeMethod('startCaching');
      return result.toString();
    } catch (e) {
      debugPrint("Error starting caching: $e");
      throw Exception("Failed to start caching: $e");
    }
  }

  // Get current wallpaper location setting
  static Future<int> getWallpaperLocation() async {
    try {
      final result = await platform.invokeMethod('getWallpaperLocation');
      return result['wallpaperLocation'] as int? ?? 1;
    } catch (e) {
      debugPrint("Error getting wallpaper location: $e");
      return 1; // Default to lock screen
    }
  }

  // Sync image URLs (triggers caching)
  static Future<Map<String, dynamic>> syncImageUrls(List<String> imageUrls) async {
    try {
      debugPrint("Syncing ${imageUrls.length} image URLs");

      final result = await platform.invokeMethod('syncImageUrls', {
        'imageUrls': imageUrls,
      });

      // Trigger caching asynchronously - don't wait for it to complete
      // This prevents UI freezing if caching takes too long
      platform.invokeMethod('startCaching').catchError((e) {
        debugPrint("Error starting caching: $e");
      });

      return Map<String, dynamic>.from(result);
    } catch (e) {
      debugPrint("Error syncing image URLs: $e");
      throw Exception("Failed to sync image URLs: $e");
    }
  }

  // Cache single wallpaper (legacy method)
  static Future<String?> cacheWallpaper(String imageUrl) async {
    try {
      debugPrint("Caching wallpaper: $imageUrl");

      final result = await platform.invokeMethod('downloadAndCacheWallpaper', {
        'imageUrl': imageUrl,
      });

      return result.toString();
    } catch (e) {
      debugPrint("Error caching wallpaper: $e");
      return null;
    }
  }

  // Background wallpaper change is now handled by native Android workers
  // No need for Flutter background tasks anymore
  // Background wallpaper change is now handled by native Android workers
  // No need for Flutter background tasks anymore
}
