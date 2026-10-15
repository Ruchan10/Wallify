import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallify/core/config.dart';
import 'package:wallify/core/user_shared_prefs.dart';

enum _PrefType { string, integer, boolean, stringList }

/// A backup file that has been read and checked, ready to be restored.
class BackupPreview {
  /// Settings that passed validation, already cleaned up.
  final Map<String, Object> settings;

  /// Keys in the file that are unknown or had a value that made no sense.
  final List<String> rejected;
  final DateTime? exportedAt;
  final String? appVersion;

  const BackupPreview._({
    required this.settings,
    required this.rejected,
    this.exportedAt,
    this.appVersion,
  });

  int get tagCount => (settings["tags"] as List?)?.length ?? 0;
  int get favoriteCount => (settings["favWallpaper"] as List?)?.length ?? 0;
  int get historyCount {
    final raw = settings["wallpaperHistory"];
    return raw is String ? (jsonDecode(raw) as List).length : 0;
  }

  /// Display names of the API keys the backup carries.
  List<String> get apiKeyNames => [
        for (final e in SettingsBackup.apiKeys.entries)
          if (settings.containsKey(e.key)) e.value,
      ];
}

class SettingsBackup {
  static const _format = "wallify-backup";
  static const _version = 3;
  static const _maxFileBytes = 20 * 1024 * 1024;
  static const _maxHistory = 100;

  /// API key prefs and their display names.
  static const apiKeys = {
    "pexels_api_key": "Pexels",
    "pixabay_api_key": "Pixabay",
    "unsplash_api_key": "Unsplash",
    "gemini_api_key": "Gemini",
  };

  /// Everything a backup carries. Device-specific state (screen size, cached
  /// file paths, the fetched wallpaper pool, worker logs) is deliberately left
  /// out so a backup can be restored on another phone.
  static const Map<String, _PrefType> _keys = {
    // Wallpapers
    "tags": _PrefType.stringList,
    "invalidTags": _PrefType.stringList,
    "favWallpaper": _PrefType.stringList,
    "wallpaperHistory": _PrefType.string,
    "wallpaperLocation": _PrefType.integer,
    "wallpaperSource": _PrefType.string,
    "folderPath": _PrefType.string,
    "customApis": _PrefType.stringList,
    "recentSearches": _PrefType.stringList,
    "topPicksRange": _PrefType.string,

    // Automation
    "autoWallpaperEnabled": _PrefType.boolean,
    "wallpaper_interval": _PrefType.integer,
    "lastWallpaperChange": _PrefType.string,
    "scheduleEnabled": _PrefType.boolean,
    "scheduleDays": _PrefType.string,
    "scheduleStartHour": _PrefType.integer,
    "scheduleEndHour": _PrefType.integer,
    "constraint_charging": _PrefType.boolean,
    "constraint_battery_not_low": _PrefType.boolean,
    "constraint_storage_not_low": _PrefType.boolean,
    "constraint_no_faces": _PrefType.boolean,
    "constraint_wifi": _PrefType.boolean,
    "allowedSsids": _PrefType.stringList,

    // Discover filters
    "discover_filter_sorting": _PrefType.string,
    "discover_filter_purity": _PrefType.string,
    "discover_filter_orientation": _PrefType.string,
    "discover_filter_category": _PrefType.string,
    "discover_filter_range": _PrefType.string,

    // Appearance & app
    "themeMode": _PrefType.integer,
    "useMonetTheme": _PrefType.boolean,
    "errorReportingEnabled": _PrefType.boolean,

    // API keys
    "pexels_api_key": _PrefType.string,
    "pixabay_api_key": _PrefType.string,
    "unsplash_api_key": _PrefType.string,
    "gemini_api_key": _PrefType.string,
  };

  /// Found in older backups but rebuilt on the device, so silently dropped.
  static const _ignoredKeys = {
    "imageUrls",
    "cachedWallpaperPaths",
    "deviceWidth",
    "deviceHeight",
  };

  /// Merged with what is already on the device instead of replacing it, so
  /// importing never loses favorites, history or tags.
  static const _mergedKeys = {
    "tags",
    "invalidTags",
    "favWallpaper",
    "wallpaperHistory",
    "recentSearches",
  };

  // ---------------------------------------------------------------- export

  /// Writes a backup to Downloads and returns a human-readable location.
  static Future<String> exportSettings({bool includeApiKeys = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // pick up values the native worker wrote

    final settings = <String, Object>{};
    for (final key in _keys.keys) {
      if (!includeApiKeys && apiKeys.containsKey(key)) continue;
      final value = prefs.get(key);
      if (value == null) continue;
      // The built-in demo key isn't the user's; leave it out.
      if (key == "unsplash_api_key" &&
          value == UserSharedPrefs.defaultUnsplashKey) {
        continue;
      }
      settings[key] = value;
    }

    final data = {
      "format": _format,
      "version": _version,
      "appVersion": Config.getAppVersion(),
      "exportedAt": DateTime.now().toIso8601String(),
      "includesApiKeys": includeApiKeys,
      "settings": settings,
    };
    final jsonString = const JsonEncoder.withIndent('  ').convert(data);

    // Round-trip check: never hand the user a backup we couldn't restore.
    parse(utf8.encode(jsonString));

    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = "Wallify_backup_$stamp.json";

    final tempFile = File("${(await getTemporaryDirectory()).path}/$fileName");
    await tempFile.writeAsString(jsonString, flush: true);

    try {
      try {
        const channel = MethodChannel('wallpaper_channel');
        final result = await channel.invokeMethod<String>(
          'saveToDownloads',
          {
            'filePath': tempFile.path,
            'fileName': fileName,
            'subdirectory': 'Wallify',
          },
        );
        if (result != null) return "Downloads/Wallify/$fileName";
      } catch (_) {
        // Fall back to app-accessible directories below.
      }

      final dir = await getDownloadsDirectory() ??
          await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      await dir.create(recursive: true);
      final file = File("${dir.path}/$fileName");
      await tempFile.copy(file.path);
      return file.path;
    } finally {
      try {
        await tempFile.delete();
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------- import

  /// Reads and validates a backup without changing anything. Throws a
  /// [FormatException] with a user-facing message if it can't be used.
  static BackupPreview parse(List<int> bytes) {
    if (bytes.isEmpty) throw const FormatException("The file is empty");
    if (bytes.length > _maxFileBytes) {
      throw const FormatException("The file is too large to be a Wallify backup");
    }

    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const FormatException("Not a Wallify backup file");
    }
    if (text.startsWith('﻿')) text = text.substring(1);

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const FormatException("The backup file is damaged (invalid JSON)");
    }
    if (decoded is! Map) throw const FormatException("Not a Wallify backup file");

    final Map raw;
    DateTime? exportedAt;
    String? appVersion;
    if (decoded.containsKey("format")) {
      if (decoded["format"] != _format || decoded["settings"] is! Map) {
        throw const FormatException("Not a Wallify backup file");
      }
      raw = decoded["settings"] as Map;
      exportedAt = DateTime.tryParse("${decoded["exportedAt"]}");
      final v = decoded["appVersion"];
      appVersion = v is String ? v : null;
    } else {
      raw = decoded; // v1: settings at the top level
    }

    final settings = <String, Object>{};
    final rejected = <String>[];
    for (final entry in raw.entries) {
      final key = "${entry.key}";
      if (_ignoredKeys.contains(key)) continue;
      final type = _keys[key];
      final value = type == null ? null : _sanitize(key, type, entry.value);
      if (value == null) {
        rejected.add(key);
      } else {
        settings[key] = value;
      }
    }

    if (settings.isEmpty) {
      throw const FormatException("No Wallify settings found in this file");
    }

    return BackupPreview._(
      settings: settings,
      rejected: rejected,
      exportedAt: exportedAt,
      appVersion: appVersion,
    );
  }

  /// Restores [preview]. All values are written or, if any write fails, the
  /// previous values are put back, so a failed import changes nothing.
  static Future<({int imported, int skipped})> importSettings(
    BackupPreview preview, {
    bool includeApiKeys = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final toWrite = <String, Object>{};
    for (final entry in preview.settings.entries) {
      if (!includeApiKeys && apiKeys.containsKey(entry.key)) continue;
      toWrite[entry.key] = _mergedKeys.contains(entry.key)
          ? _merge(entry.key, prefs.get(entry.key), entry.value)
          : entry.value;
    }

    final previous = {for (final key in toWrite.keys) key: prefs.get(key)};
    try {
      for (final entry in toWrite.entries) {
        if (!await _write(prefs, entry.key, entry.value)) {
          throw StateError("Could not save ${entry.key}");
        }
      }
    } catch (_) {
      for (final entry in previous.entries) {
        try {
          final old = entry.value;
          old == null
              ? await prefs.remove(entry.key)
              : await _write(prefs, entry.key, old);
        } catch (_) {}
      }
      rethrow;
    }

    return (imported: toWrite.length, skipped: preview.rejected.length);
  }

  static Future<bool> _write(SharedPreferences prefs, String key, Object value) {
    return switch (value) {
      String v => prefs.setString(key, v),
      int v => prefs.setInt(key, v),
      bool v => prefs.setBool(key, v),
      List v => prefs.setStringList(key, v.cast<String>()),
      _ => Future.value(false),
    };
  }

  // ------------------------------------------------------------ validation

  /// Returns a clean value for [key], or null if [value] isn't usable.
  static Object? _sanitize(String key, _PrefType type, Object? value) {
    switch (type) {
      case _PrefType.boolean:
        return value is bool ? value : null;

      case _PrefType.integer:
        if (value is! num) return null;
        final v = value.toInt();
        return switch (key) {
          // 4 was the removed "random" mode.
          "wallpaperLocation" => v == 4 ? 3 : (v >= 1 && v <= 3 ? v : null),
          "wallpaper_interval" => v < 15 ? 15 : v,
          "scheduleStartHour" || "scheduleEndHour" => v.clamp(0, 23),
          "themeMode" => v >= 0 && v <= 2 ? v : null,
          _ => v,
        };

      case _PrefType.stringList:
        // Older installs stored some lists as a JSON string.
        Object? list = value;
        if (list is String) {
          try {
            list = jsonDecode(list);
          } catch (_) {
            return null;
          }
        }
        if (list is! List) return null;
        final strings = <String>[];
        for (final e in list) {
          if (e is String) {
            strings.add(e);
          } else if (e is Map && key == "favWallpaper") {
            strings.add(jsonEncode(e));
          }
        }
        return switch (key) {
          "favWallpaper" => _cleanFavorites(strings),
          "tags" || "invalidTags" || "recentSearches" => _cleanTags(strings),
          _ => strings,
        };

      case _PrefType.string:
        if (value is! String) return null;
        return switch (key) {
          "wallpaperHistory" => _cleanHistory(value),
          "scheduleDays" => _cleanScheduleDays(value),
          "folderPath" => _cleanFolderPaths(value),
          "wallpaperSource" => _cleanSources(value),
          "lastWallpaperChange" => DateTime.tryParse(value) == null ? null : value,
          "topPicksRange" =>
            UserSharedPrefs.topPicksRanges.contains(value) ? value : null,
          _ when apiKeys.containsKey(key) =>
            value.trim().isEmpty ? null : value.trim(),
          _ => value,
        };
    }
  }

  static List<String> _cleanTags(List<String> tags) {
    final seen = <String>{};
    return [
      for (final t in tags.map((t) => t.trim()))
        if (t.isNotEmpty && seen.add(t.toLowerCase())) t,
    ];
  }

  /// Keeps entries that decode to a wallpaper with a url, one per id.
  static List<String> _cleanFavorites(List<String> entries) {
    final seen = <String>{};
    final out = <String>[];
    for (final e in entries) {
      try {
        final m = jsonDecode(e);
        if (m is! Map || m["url"] is! String || (m["url"] as String).isEmpty) {
          continue;
        }
        if (seen.add("${m["id"] ?? m["url"]}")) out.add(e);
      } catch (_) {}
    }
    return out;
  }

  static String? _cleanHistory(String raw) {
    try {
      final list = jsonDecode(raw);
      if (list is! List) return null;
      return jsonEncode([
        for (final e in list)
          if (e is Map && e["url"] is String) e,
      ]);
    } catch (_) {
      return null;
    }
  }

  static String? _cleanScheduleDays(String raw) {
    try {
      final list = jsonDecode(raw);
      if (list is! List) return null;
      final days = {
        for (final d in list)
          if (d is int && d >= 1 && d <= 7) d,
      }.toList()
        ..sort();
      return days.isEmpty ? null : jsonEncode(days);
    } catch (_) {
      return null;
    }
  }

  static String? _cleanFolderPaths(String raw) {
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        return jsonEncode([
          for (final p in list)
            if (p is String && p.isNotEmpty) p,
        ]);
      }
    } catch (_) {}
    // Legacy: a single path.
    return raw.isEmpty ? null : jsonEncode([raw]);
  }

  static String? _cleanSources(String raw) {
    const valid = {"internet", "folder", "favorites", "toppicks"};
    final sources = raw
        .split(",")
        .map((s) => s.trim())
        .where(valid.contains)
        .toSet();
    return sources.isEmpty ? null : sources.join(",");
  }

  // --------------------------------------------------------------- merging

  /// Combines what's on the device ([current]) with the backup ([incoming]).
  static Object _merge(String key, Object? current, Object incoming) {
    if (current == null) return incoming;

    if (key == "wallpaperHistory") {
      final existing = _sanitize(key, _PrefType.string, current);
      if (existing is! String) return incoming;
      final byId = <String, Map>{};
      for (final e in [
        ...jsonDecode(existing) as List,
        ...jsonDecode(incoming as String) as List,
      ]) {
        byId.putIfAbsent("${e["id"] ?? e["url"]}", () => e as Map);
      }
      final merged = byId.values.toList()
        ..sort((a, b) => "${b["timestamp"] ?? ""}"
            .compareTo("${a["timestamp"] ?? ""}"));
      return jsonEncode(merged.take(_maxHistory).toList());
    }

    final existing = _sanitize(key, _PrefType.stringList, current);
    if (existing is! List<String>) return incoming;
    final combined = [...existing, ...(incoming as List).cast<String>()];
    return switch (key) {
      "favWallpaper" => _cleanFavorites(combined),
      "recentSearches" => _cleanTags(combined).take(10).toList(),
      _ => _cleanTags(combined),
    };
  }
}
