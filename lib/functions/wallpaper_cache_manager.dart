import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/model/wallpaper_model.dart';

/// Keeps a local copy of upcoming wallpapers so the background worker can
/// change wallpaper without waiting on (or having) a network connection.
///
/// Everything here runs alongside the UI: image decoding happens in the engine
/// and JPEG encoding in a separate isolate, so caching never blocks a frame.
class WallpaperCacheManager {
  static const _maxCached = 50;
  static const _concurrency = 3;
  static const _maxDimension = 2160;
  static const _timeout = Duration(seconds: 30);

  static Future<Directory> _cacheDir() async {
    final dir = Directory(await cacheDirPath());
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<String> cacheDirPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/wallpapers';
  }

  static String _safeName(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static Future<String?> downloadAndCache(Wallpaper wallpaper) async {
    try {
      final dir = await _cacheDir();
      final file = File('${dir.path}/${_safeName(wallpaper.id)}.jpg');

      if (await file.exists()) return file.path;

      final response = await http.get(Uri.parse(wallpaper.url)).timeout(_timeout);
      if (response.statusCode != 200) return null;

      final bytes = await _shrinkIfNeeded(response.bodyBytes);
      if (bytes == null) return null;

      // Write to a temp name first so the worker never picks up half a file.
      final tmp = File('${file.path}.part');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);
      return file.path;
    } catch (e) {
      debugPrint("Failed to cache ${wallpaper.id}: $e");
      return null;
    }
  }

  /// Returns [bytes] unchanged when the image is already small enough (most
  /// API results are), otherwise a JPEG scaled down to [_maxDimension] on its
  /// long side with the aspect ratio kept. Null if the bytes aren't an image.
  static Future<Uint8List?> _shrinkIfNeeded(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final w = descriptor.width;
      final h = descriptor.height;
      if (w <= 0 || h <= 0) return null;
      if (max(w, h) <= _maxDimension) return bytes;

      final scale = _maxDimension / max(w, h);
      final codec = await descriptor.instantiateCodec(
        targetWidth: (w * scale).round(),
        targetHeight: (h * scale).round(),
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final width = image.width;
      final height = image.height;
      image.dispose();
      codec.dispose();
      if (data == null) return null;

      // Pure-Dart JPEG encoding of a 4K image takes long enough to freeze the
      // UI, so it runs in its own isolate. The pixels move there without a copy.
      final pixels = TransferableTypedData.fromList([data.buffer.asUint8List()]);
      return await Isolate.run(() {
        final raw = pixels.materialize();
        final decoded = img.Image.fromBytes(
          width: width,
          height: height,
          bytes: raw,
          numChannels: 4,
        );
        return img.encodeJpg(decoded, quality: 85);
      });
    } catch (e) {
      debugPrint("Failed to resize cached image: $e");
      return null;
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  /// Downloads [wallpapers] into the cache. Stops early (without touching the
  /// saved list) once [isCancelled] returns true, so a newer refresh wins.
  static Future<void> cacheWallpapers(
    List<Wallpaper> wallpapers, {
    bool Function()? isCancelled,
  }) async {
    final paths = <String>[];
    final snapshot = wallpapers.toList();
    for (var i = 0;
        i < snapshot.length && paths.length < _maxCached;
        i += _concurrency) {
      if (isCancelled?.call() ?? false) return;
      final batch = snapshot.sublist(i, min(i + _concurrency, snapshot.length));
      final results = await Future.wait(batch.map(downloadAndCache));
      for (final path in results) {
        if (path != null) {
          paths.add(path);
          if (paths.length >= _maxCached) break;
        }
      }
    }
    if (isCancelled?.call() ?? false) return;

    await _evictIfNeeded(keepFirst: paths);
  }

  /// Trims the cache to [_maxCached] files, keeping [keepFirst] (the current
  /// pool) and then the most recent other files. Only the current pool is
  /// offered to the worker, so wallpapers from removed tags stop appearing.
  static Future<void> _evictIfNeeded({List<String> keepFirst = const []}) async {
    final dir = await _cacheDir();
    final files = <File, DateTime>{};
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.jpg')) {
        files[entity] = (await entity.stat()).modified;
      }
    }

    final preferred = keepFirst.toSet();
    final ordered = files.keys.toList()
      ..sort((a, b) {
        final pa = preferred.contains(a.path) ? 0 : 1;
        final pb = preferred.contains(b.path) ? 0 : 1;
        if (pa != pb) return pa - pb;
        return files[b]!.compareTo(files[a]!); // newest first
      });

    for (final stale in ordered.skip(_maxCached)) {
      try {
        await stale.delete();
      } catch (_) {}
    }

    final kept = ordered.take(_maxCached).map((f) => f.path).toSet();
    await UserSharedPrefs.saveCachedWallpaperPaths(
      keepFirst.where(kept.contains).toList(),
    );
  }

  static Future<List<String>> getCachedPaths() async {
    return UserSharedPrefs.getCachedWallpaperPaths();
  }

  static Future<int> clearCache() async {
    final dir = await _cacheDir();
    int count = 0;
    await for (final f in dir.list()) {
      try {
        await f.delete();
        count++;
      } catch (_) {}
    }
    await UserSharedPrefs.clearCachedWallpaperPaths();
    return count;
  }

  static Future<int> getCacheSizeBytes() async {
    final dir = await _cacheDir();
    int total = 0;
    await for (final f in dir.list()) {
      if (f is File) total += await f.length();
    }
    return total;
  }
}
