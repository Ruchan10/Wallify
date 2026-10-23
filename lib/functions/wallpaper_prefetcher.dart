import 'package:flutter/foundation.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/functions/wallpaper_cache_manager.dart';
import 'package:wallify/functions/wallpaper_manager.dart';

class WallpaperPrefetcher {
  /// Refreshes the background worker's pool on app start once its cached
  /// wallpapers are used up, so automatic changes don't depend on the network.
  /// Caching a few new wallpapers on their own would replace the worker's
  /// whole cached list with them.
  static Future<void> prefetchNext() async {
    try {
      if (!await UserSharedPrefs.getAutoWallpaperEnabled()) return;
      if ((await WallpaperCacheManager.getCachedPaths()).isNotEmpty) return;
      await WallpaperManager.refreshPool();
    } catch (e) {
      debugPrint("WallpaperPrefetcher failed: $e");
    }
  }
}
