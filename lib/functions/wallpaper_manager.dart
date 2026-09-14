import 'package:flutter/material.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/model/wallpaper_model.dart';
import 'package:wallify/services/wallpaper_api_service.dart';

class WallpaperManager {
  static int? interval = 1;
  static int deviceWidth = 360;
  static int deviceHeight = 800;
  static List<Wallpaper> urls = [];
  static String tag = "nature";
  static final usp = UserSharedPrefs();

  static Future<List<Wallpaper>> fetchImagesFromAllSources({List<String>? sources}) async {
    final selected = sources ?? ["internet", "favorites"];
    urls.clear();
    final seen = <String>{};

    try {
      if (selected.contains("favorites")) {
        for (final w in await UserSharedPrefs.getFavWallpapers()) {
          if (seen.add(w.url)) urls.add(w);
        }
      }

      tag = await UserSharedPrefs.getRandomTag();
      deviceWidth = await UserSharedPrefs.getDeviceWidth();
      deviceHeight = await UserSharedPrefs.getDeviceHeight();

      if (selected.contains("internet")) {
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
    } catch (e) {
      debugPrint("Error fetching images: $e");
    }
    return urls;
  }

  static Future<bool> validateTag(String tag) {
    return WallpaperApiService.validateTag(tag);
  }
}
