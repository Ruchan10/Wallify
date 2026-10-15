import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/functions/wallpaper_cache_manager.dart';
import 'package:wallify/model/wallpaper_model.dart';
import 'package:wallify/services/wallpaper_api_service.dart';

class WallpaperManager {
  static Future<List<Wallpaper>> fetchImagesFromAllSources({List<String>? sources}) async {
    final selected = sources ?? ["internet", "favorites"];
    final urls = <Wallpaper>[];
    final seen = <String>{};

    try {
      if (selected.contains("favorites")) {
        for (final w in await UserSharedPrefs.getFavWallpapers()) {
          if (seen.add(w.url)) urls.add(w);
        }
      }

      if (selected.contains("internet")) {
        final tag = await UserSharedPrefs.getRandomTag();
        final internetSources = ["wallhaven", "unsplash", "pixabay"];
        final results = await WallpaperApiService.fetchAll(
          sources: internetSources,
          optionsFor: (source) => FetchOptions(
            query: tag,
            page: 1,
            perPage: 15,
            // Auto-change always uses the best-rated wallpapers, regardless
            // of the sort picked in Discover.
            sorting: "toplist",
            purity: "SFW",
            orientation: "portrait",
          ),
        );

        for (final w in results) {
          if (seen.add(w.url)) urls.add(w);
        }
      }

      if (selected.contains("toppicks")) {
        for (final w in await fetchTopPicks()) {
          if (seen.add(w.url)) urls.add(w);
        }
      }
    } catch (e) {
      debugPrint("Error fetching images: $e");
    }
    return urls;
  }

  /// Every source's best portrait wallpapers for the saved Top Picks period,
  /// alternating between sources. Ignores tags.
  static Future<List<Wallpaper>> fetchTopPicks() async {
    final range = await UserSharedPrefs.getTopPicksRange();
    final results = await WallpaperApiService.fetchEach(
      sources: WallpaperApiService.searchableSources,
      optionsFor: (source) => FetchOptions(
        perPage: 15,
        sorting: "toplist",
        range: range,
        purity: "SFW",
        orientation: "portrait",
        bestOf: true,
      ),
    );
    // Unsplash's popular and Pexels' curated feeds can't be limited to
    // portrait, so drop the landscape images here.
    bool portrait(Wallpaper w) => (w.aspectRatio ?? 0) <= 1;
    return WallpaperApiService.interleave([
      for (final list in results.values)
        if (list != null) list.where(portrait).toList(),
    ]);
  }

  static Future<bool?> validateTag(String tag) {
    return WallpaperApiService.validateTag(tag);
  }

  static Timer? _refreshTimer;
  static int _refreshGeneration = 0;

  /// Refreshes the pool the background worker picks from, after settings
  /// stop changing for a moment. Several quick edits (adding three tags,
  /// toggling sources) cost one fetch, and a run still in progress is
  /// abandoned when a newer one starts.
  static void scheduleRefresh({
    Duration delay = const Duration(milliseconds: 1200),
  }) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(delay, () => refreshPool());
  }

  /// Fetches a new pool now and saves it. Local caching continues in the
  /// background after this returns.
  static Future<void> refreshPool() async {
    _refreshTimer?.cancel();
    final generation = ++_refreshGeneration;
    bool stale() => generation != _refreshGeneration;

    try {
      final sources = await UserSharedPrefs.getWallpaperSources();
      if (!sources.any(const {"internet", "favorites", "toppicks"}.contains)) {
        return;
      }
      final fetched = await fetchImagesFromAllSources(sources: sources);
      // Offline or rate limited: keep the previous pool rather than emptying it.
      if (stale() || fetched.isEmpty) return;

      await UserSharedPrefs.saveWallpapers(fetched);
      unawaited(
        WallpaperCacheManager.cacheWallpapers(fetched, isCancelled: stale),
      );
    } catch (e) {
      debugPrint("Wallpaper pool refresh failed: $e");
    }
  }
}
