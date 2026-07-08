import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/model/wallpaper_model.dart';

class WallpaperCacheManager {
  static const _maxCached = 50;

  static Future<Directory> _cacheDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/wallpapers');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static Future<String?> downloadAndCache(Wallpaper wallpaper) async {
    try {
      final dir = await _cacheDir();
      final ext = _extensionFromUrl(wallpaper.url);
      final file = File('${dir.path}/${wallpaper.id}$ext');

      if (file.existsSync()) return file.path;

      final response = await http.get(Uri.parse(wallpaper.url));
      if (response.statusCode != 200) return null;

      await file.writeAsBytes(response.bodyBytes);
      return file.path;
    } catch (e) {
      debugPrint("Failed to cache ${wallpaper.id}: $e");
      return null;
    }
  }

  static Future<void> cacheWallpapers(List<Wallpaper> wallpapers) async {
    final paths = <String>[];
    for (final w in wallpapers) {
      final path = await downloadAndCache(w);
      if (path != null) paths.add(path);
      if (paths.length >= _maxCached) break;
    }

    await UserSharedPrefs.saveCachedWallpaperPaths(paths);

    _evictIfNeeded();
  }

  static Future<void> _evictIfNeeded() async {
    final dir = await _cacheDir();
    final files = dir.listSync()..sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));

    while (files.length > _maxCached) {
      final oldest = files.removeAt(0);
      oldest.deleteSync();
    }
  }

  static Future<List<String>> getCachedPaths() async {
    return UserSharedPrefs.getCachedWallpaperPaths();
  }

  static Future<int> clearCache() async {
    final dir = await _cacheDir();
    int count = 0;
    if (dir.existsSync()) {
      for (final f in dir.listSync()) {
        await f.delete();
        count++;
      }
    }
    await UserSharedPrefs.clearCachedWallpaperPaths();
    return count;
  }

  static String _extensionFromUrl(String url) {
    try {
      final path = Uri.parse(url).path;
      final dot = path.lastIndexOf('.');
      if (dot >= 0) {
        final ext = path.substring(dot);
        if (ext.contains('/')) return '.jpg';
        return ext;
      }
    } catch (_) {}
    return '.jpg';
  }
}
