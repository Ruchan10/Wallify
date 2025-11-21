import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/model/wallpaper_model.dart';

class WallpaperManager {
  static int? interval = 1;
  static int deviceWidth = 360;
  static int deviceHeight = 800;
  static List<Wallpaper> urls = [];
  static String tag = "nature";
  static final usp = UserSharedPrefs();

  

  static Future<List<Wallpaper>> fetchImagesFromAllSources() async {
    try {
      // Load from favorites first
      urls.addAll(await UserSharedPrefs.getFavWallpapers());
      tag = await UserSharedPrefs.getRandomTag();
      deviceWidth = await UserSharedPrefs.getDeviceWidth();
      deviceHeight = await UserSharedPrefs.getDeviceHeight();

      // 🔹 Wallhaven
      final wallRes = await http.get(
        Uri.parse(
          "https://wallhaven.cc/api/v1/search?q=$tag"
          "&categories=100&purity=100"
          "&ratios=portrait"
          "&atleast=${deviceWidth}x$deviceHeight"
          "&sorting=random",
        ),
      );
      final wallData = jsonDecode(wallRes.body);
      for (var item in wallData["data"]) {
        urls.add(Wallpaper(id: item["id"].toString(), url: item["path"]));
      }

      // 🔹 Unsplash
      final unsplashRes = await http.get(
        Uri.parse(
          "https://api.unsplash.com/photos/random"
          "?query=$tag&orientation=portrait&content_filter=high&count=10",
        ),
        headers: {
          "Authorization":
              "Client-ID yTBcYNAtnRHbrYMn2p4DrBiqzOAfdH9nyexQQtJWO-E",
        },
      );
      final unsplashData = jsonDecode(unsplashRes.body);
      for (var item in unsplashData) {
        urls.add(
          Wallpaper(id: item["id"].toString(), url: item["urls"]["regular"]),
        );
      }

      // 🔹 Pixabay
      final pixabayRes = await http.get(
        Uri.parse(
          "https://pixabay.com/api/"
          "?key=52028006-a7e910370a5d0158c371bb06a"
          "&q=$tag"
          "&image_type=photo"
          "&orientation=vertical"
          "&min_width=$deviceWidth&min_height=$deviceHeight"
          "&safesearch=true",
        ),
      );
      final pixabayData = jsonDecode(pixabayRes.body);
      for (var item in pixabayData["hits"]) {
        urls.add(
          Wallpaper(id: item["id"].toString(), url: item["largeImageURL"]),
        );
      }
    } catch (e) {
      debugPrint("❌ Error fetching images: $e");
    }
    return urls;
  }
}
