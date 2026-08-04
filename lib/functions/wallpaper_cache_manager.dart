import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/model/wallpaper_model.dart';

class WallpaperCacheManager {
  static const _maxCached = 50;
  static const _concurrency = 4;
  static const _maxDimension = 2160;

  static Future<Directory> _cacheDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/wallpapers');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static Future<String?> downloadAndCache(Wallpaper wallpaper) async {
    try {
      final dir = await _cacheDir();
      final file = File('${dir.path}/${wallpaper.id}.jpg');

      if (file.existsSync()) return file.path;

      final response = await http.get(Uri.parse(wallpaper.url));
      if (response.statusCode != 200) return null;

      final bytes = response.bodyBytes;
      final resized = await _resizeImage(bytes);
      if (resized == null) return null;

      await file.writeAsBytes(resized);
      return file.path;
    } catch (e) {
      debugPrint("Failed to cache ${wallpaper.id}: $e");
      return null;
    }
  }

  static Future<Uint8List?> _resizeImage(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: _maxDimension,
        targetHeight: _maxDimension,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      final resized = frame.image;
      final data = await resized.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      final processed = img.Image.fromBytes(
        width: resized.width,
        height: resized.height,
        bytes: data.buffer,
        numChannels: 4,
      );
      return Uint8List.fromList(img.encodeJpg(processed, quality: 85));
    } catch (e) {
      debugPrint("Failed to resize cached image: $e");
      return null;
    }
  }

  static Future<void> cacheWallpapers(List<Wallpaper> wallpapers) async {
    final paths = <String>[];
    final snapshot = wallpapers.toList();
    for (var i = 0;
        i < snapshot.length && paths.length < _maxCached;
        i += _concurrency) {
      final end = (i + _concurrency < snapshot.length)
          ? i + _concurrency
          : snapshot.length;
      final batch = snapshot.sublist(i, end);
      final results = await Future.wait(batch.map((w) => downloadAndCache(w)));
      for (final path in results) {
        if (path != null) {
          paths.add(path);
          if (paths.length >= _maxCached) break;
        }
      }
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

    final kept = files.map((f) => f.path).toList();
    await UserSharedPrefs.saveCachedWallpaperPaths(kept);
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

  static Future<int> getCacheSizeBytes() async {
    final dir = await _cacheDir();
    if (!dir.existsSync()) return 0;
    int total = 0;
    for (final f in dir.listSync()) {
      total += f.statSync().size;
    }
    return total;
  }
}
