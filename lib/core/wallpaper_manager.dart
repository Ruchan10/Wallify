import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui show Rect;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:wallify/core/human_detector.dart' as humandetector;
import 'package:wallify/core/image_cropper.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallpaper_manager_flutter/wallpaper_manager_flutter.dart';

class WallpaperManager {
  static List<String> sources = ["wallhaven", "unsplash", "pixabay"];
  static int? interval = 1;
  static int deviceWidth = 360;
  static int deviceHeight = 800;

  static final usp = UserSharedPrefs();

  // Move your fetch and set wallpaper logic here
  static Future<String> fetchAndSetWallpaper({
    List<String>? savedTags,
    int wallpaperLocation = WallpaperManagerFlutter.bothScreens,
    bool changeNow = false,
  }) async {
    final lastChange = await UserSharedPrefs.getLastWallpaperChange();
    interval = await UserSharedPrefs.getInterval();

    if (lastChange != null) {
      final diff = DateTime.now().difference(lastChange);
      if (diff.inHours < interval! && !changeNow) {
        return "Wallpaper changed less than $interval hours ago";
      }
    }
    deviceWidth = await UserSharedPrefs.getDeviceWidth();
    deviceHeight = await UserSharedPrefs.getDeviceHeight();
    savedTags ??= await UserSharedPrefs.getTags();
    sources = await UserSharedPrefs.getSelectedSources();
    if (sources.isEmpty) {
      sources = ["wallhaven", "unsplash", "pixabay"];
    }

    final random = Random();
    final tag = savedTags.isNotEmpty
        ? savedTags[random.nextInt(savedTags.length)]
        : "nature";

    final selectedSource = sources[random.nextInt(sources.length)];

    String? imageUrl;

    try {
      if (selectedSource == "wallhaven") {
        final res = await http.get(
          Uri.parse(
            "https://wallhaven.cc/api/v1/search?q=$tag"
            "&categories=100&purity=100"
            "&ratios=portrait"
            "&atleast=${deviceWidth}x$deviceHeight"
            "&sorting=random",
          ),
        );
        final data = jsonDecode(res.body);
        if (data["data"].isNotEmpty) {
          imageUrl = data["data"][0]["path"];
        }
      } else if (selectedSource == "unsplash") {
        final res = await http.get(
          Uri.parse(
            "https://api.unsplash.com/photos/random"
            "?query=$tag"
            "&orientation=portrait"
            "&content_filter=high",
          ),
          headers: {
            "Authorization":
                "Client-ID yTBcYNAtnRHbrYMn2p4DrBiqzOAfdH9nyexQQtJWO-E",
          },
        );
        final data = jsonDecode(res.body);
        imageUrl = data["urls"]["regular"];
      } else if (selectedSource == "pixabay") {
        final res = await http.get(
          Uri.parse(
            "https://pixabay.com/api/"
            "?key=52028006-a7e910370a5d0158c371bb06a"
            "&q=$tag"
            "&image_type=photo"
            "&orientation=vertical"
            "&min_width=$deviceWidth&min_height=$deviceHeight"
            "&per_page=50&safesearch=true",
          ),
        );
        final data = jsonDecode(res.body);
        final filtered = data["hits"] as List;
        if (filtered.isNotEmpty) {
          final idx = random.nextInt(filtered.length);
          imageUrl = filtered.elementAt(idx)["largeImageURL"];
        }
      }

      if (imageUrl == null) {
        fetchAndSetWallpaper(changeNow: changeNow);
        return "No wallpaper found for $tag in $selectedSource. Trying again";
      }

      final response = await http.get(Uri.parse(imageUrl));
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

      await WallpaperManagerFlutter().setWallpaper(
        croppedPath!,
        wallpaperLocation,
      );

      return "Wallpaper set for ${wallpaperLocation == WallpaperManagerFlutter.homeScreen ? "Home" : "Lock"} from $selectedSource ($tag)";
    } catch (e) {
      debugPrint("Error setting wallpaper: $e");
      return "Error setting wallpaper: $e";
    }
  }
}
