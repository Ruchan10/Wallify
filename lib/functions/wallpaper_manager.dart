import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/functions/wallpaper_cache_manager.dart';
import 'package:wallify/model/wallpaper_model.dart';

class WallpaperManager {
  static int? interval = 1;
  static int deviceWidth = 360;
  static int deviceHeight = 800;
  static List<Wallpaper> urls = [];
  static String tag = "nature";
  static final usp = UserSharedPrefs();

  static Future<List<Wallpaper>> fetchImagesFromAllSources({List<String>? sources}) async {
    final selected = sources ?? ["internet", "favorites"];
    try {
      if (selected.contains("favorites")) {
        urls.addAll(await UserSharedPrefs.getFavWallpapers());
      }
      tag = await UserSharedPrefs.getRandomTag();
      deviceWidth = await UserSharedPrefs.getDeviceWidth();
      deviceHeight = await UserSharedPrefs.getDeviceHeight();

      if (selected.contains("internet")) {
        // Wallhaven
        final wallRes = await http.get(
          Uri.parse(
            "https://wallhaven.cc/api/v1/search?q=$tag"
            "&categories=100&purity=100"
            "&ratios=portrait"
            "&sorting=relevance",
          ),
        );
        final wallData = jsonDecode(wallRes.body);
        if (wallData["data"] is List) for (var item in wallData["data"]) {
          urls.add(Wallpaper(id: item["id"].toString(), url: item["path"], timestamp: DateTime.now()));
        }

        // Unsplash
        final unsplashRes = await http.get(
          Uri.parse(
            "https://api.unsplash.com/search/photos?page=1"
            "&query=$tag&orientation=portrait&content_filter=high",
          ),
          headers: {
            "Authorization":
                "Client-ID yTBcYNAtnRHbrYMn2p4DrBiqzOAfdH9nyexQQtJWO-E",
          },
        );
        final unsplashData = jsonDecode(unsplashRes.body);
        final unsplashResults = unsplashData["results"];
        if (unsplashResults is List) for (var item in unsplashResults) {
          urls.add(
            Wallpaper(id: item["id"].toString(), url: item["urls"]["regular"], timestamp: DateTime.now()),
          );
        }

        // Pixabay
        final pixabayRes = await http.get(
          Uri.parse(
            "https://pixabay.com/api/"
            "?key=52028006-a7e910370a5d0158c371bb06a"
            "&q=$tag"
            "&image_type=photo"
            "&orientation=vertical"
            "&safesearch=true",
          ),
        );
        final pixabayData = jsonDecode(pixabayRes.body);
        if (pixabayData["hits"] is List) for (var item in pixabayData["hits"]) {
          urls.add(
            Wallpaper(id: item["id"].toString(), url: item["largeImageURL"], timestamp: DateTime.now()),
          );
        }
      }
    } catch (e) {
      debugPrint("Error fetching images: $e");
    }
    return urls;
  }

  static Future<bool> validateTag(String tag) async {
    try {
      final res = await http.get(
        Uri.parse(
          "https://pixabay.com/api/"
          "?key=52028006-a7e910370a5d0158c371bb06a"
          "&q=$tag"
          "&image_type=photo"
          "&orientation=vertical"
          "&safesearch=true",
        ),
      );
      final data = jsonDecode(res.body);
      final hits = data["hits"];
      if (hits is List && hits.isNotEmpty) return true;
    } catch (e) {
      debugPrint("Tag validation error: $e");
    }
    return false;
  }
}
