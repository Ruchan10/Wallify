import 'package:flutter/foundation.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/functions/wallpaper_cache_manager.dart';
import 'package:wallify/functions/wallpaper_manager.dart';

class WallpaperPrefetcher {
  static const int prefetchCount = 3;

  static Future<void> prefetchNext() async {
    try {
      final sources = await UserSharedPrefs.getWallpaperSources();
      if (!sources.contains("internet") && !sources.contains("favorites")) {
        return;
      }
      final fetched = await WallpaperManager.fetchImagesFromAllSources(
        sources: sources,
      );
      if (fetched.isEmpty) return;
      await WallpaperCacheManager.cacheWallpapers(
        fetched.take(prefetchCount).toList(),
      );
      debugPrint("WallpaperPrefetcher: cached ${fetched.length} wallpapers");
    } catch (e) {
      debugPrint("WallpaperPrefetcher failed: $e");
    }
  }
}
