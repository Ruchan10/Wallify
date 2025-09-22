import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui show Rect;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/functions/background_service.dart' as BackgroundService;
import 'package:wallify/functions/human_detector.dart' as humandetector;
import 'package:wallify/functions/image_cropper.dart';
import 'package:wallpaper_manager_flutter/wallpaper_manager_flutter.dart';

class WallpaperManager {
  static int? interval = 1;
  static int deviceWidth = 360;
  static int deviceHeight = 800;
  static List<String> urls = [];
  static String tag = "nature";
  static final usp = UserSharedPrefs();

  static Future<String> fetchAndSetWallpaper({
    List<String>? savedTags,
    int wallpaperLocation = WallpaperManagerFlutter.homeScreen,
    bool changeNow = false,
    String? imageUrl,
  }) async {
    final lastChange = await UserSharedPrefs.getLastWallpaperChange();
    interval = await UserSharedPrefs.getInterval();
    imageUrl ??= await UserSharedPrefs.getImageUrl();

    bool hasInternet = await BackgroundService.hasInternet();

    if (!hasInternet) {
      final offlineFile = await BackgroundService.getRandomCachedWallpaper();
      if (offlineFile == null) {
        return "No internet and no cached wallpapers available.";
      }

      await WallpaperManagerFlutter().setWallpaper(
        offlineFile.path,
        wallpaperLocation,
      );
      return "Offline wallpaper set from cache 🖼️";
    }

    try {
      if (imageUrl == null) {
        if (lastChange != null) {
          final diff = DateTime.now().difference(lastChange);
          if (diff.inHours < interval! && !changeNow) {
            return "Wallpaper changed less than $interval hours ago";
          }
        }
        deviceWidth = await UserSharedPrefs.getDeviceWidth();
        deviceHeight = await UserSharedPrefs.getDeviceHeight();
        savedTags ??= await UserSharedPrefs.getTags();

        final random = Random();
        tag = savedTags.isNotEmpty
            ? savedTags[random.nextInt(savedTags.length)]
            : "nature";

        urls = await _fetchImagesFromAllSources();
        await UserSharedPrefs.saveImageUrls(urls);
        imageUrl = await UserSharedPrefs.getImageUrl();
      }
      final response = await http.get(Uri.parse(imageUrl!));
      final bytes = response.bodyBytes;

      final dir = await getTemporaryDirectory();
      final filePath =
          "${dir.path}/wallpaper_${DateTime.now().millisecondsSinceEpoch}_$wallpaperLocation.jpg";
      await File(filePath).writeAsBytes(bytes);

      if (await humandetector.containsHuman(filePath)) {
        fetchAndSetWallpaper(changeNow: changeNow);

        return "Wallpaper contains human. Trying again";
      }
      final obj = await detectMainObject(filePath);

      if (obj == null) {
        fetchAndSetWallpaper(changeNow: changeNow);
        return "No object found or human detected, skipping...";
      }

      final croppedPath = await cropAroundObject(
        filePath: filePath,
        boundingBox: ui.Rect.fromLTWH(
          obj.boundingBox.left.toDouble(),
          obj.boundingBox.top.toDouble(),
          obj.boundingBox.width.toDouble(),
          obj.boundingBox.height.toDouble(),
        ),
        deviceWidth: deviceWidth,
        deviceHeight: deviceHeight,
      );

      UserSharedPrefs.saveLastWallpaperChange(DateTime.now());
      UserSharedPrefs.saveWallpaperHistory(imageUrl);

      await WallpaperManagerFlutter().setWallpaper(
        croppedPath!,
        wallpaperLocation,
      );

      return "Wallpaper set for ${wallpaperLocation == WallpaperManagerFlutter.homeScreen ? "Home" : "Lock"} from ($tag)";
    } catch (e) {
      debugPrint("Error setting wallpaper: $e");
      return "Error setting wallpaper: $e";
    }
  }

  static Future<List<String>> _fetchImagesFromAllSources() async {
    try {
      urls.addAll(await UserSharedPrefs.getFavWallpaper());
      // Wallhaven
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
        urls.add(item["path"]);
      }

      // Unsplash
      final unsplashRes = await http.get(
        Uri.parse(
          "https://api.unsplash.com/photos/random?query=$tag&orientation=portrait&content_filter=high",
        ),
        headers: {
          "Authorization":
              "Client-ID yTBcYNAtnRHbrYMn2p4DrBiqzOAfdH9nyexQQtJWO-E",
        },
      );
      final unsplashData = jsonDecode(unsplashRes.body);
      for (var item in unsplashData) {
        urls.add(item["urls"]["regular"]);
      }

      // Pixabay
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
        urls.add(item["largeImageURL"]);
      }
    } catch (e) {
      debugPrint("❌ Error fetching images: $e");
    }
    return urls;
  }
}
