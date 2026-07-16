import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallify/model/wallpaper_model.dart';

class UserSharedPrefs {
  static const _tagsKey = "tags";
  static const _wallpaperLocationKey = "wallpaperLocation";
  static const _deviceHeightKey = "deviceHeight";
  static const _deviceWidthKey = "deviceWidth";
  static const _wallpaperHistoryKey = "wallpaperHistory";
  static const _autoWallpaperEnabledKey = "autoWallpaperEnabled";
  static const _lastWallpaperChangeKey = "lastWallpaperChange";
  static const _keyInterval = "wallpaper_interval";
  static const _favWallpaperKey = "favWallpaper";
  static const _imageUrlsKey = "imageUrls";
  static const _errorReportingKey = "errorReportingEnabled";
  static const _constraintChargingKey = "constraint_charging";
  static const _constraintBatteryNotLowKey = "constraint_battery_not_low";
  static const _constraintStorageNotLowKey = "constraint_storage_not_low";
  static const _constraintNoFacesKey = "constraint_no_faces";
  static const _constraintWifiKey = "constraint_wifi";
  static const _wallpaperSourceKey = "wallpaperSource";
  static const _folderPathKey = "folderPath";
  static const _cachedWallpaperPathsKey = "cachedWallpaperPaths";
  static const _useMonetThemeKey = "useMonetTheme";

  /// ---- TAGS ----
  static Future<List<String>> getTags() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_tagsKey) ?? [];
  }

  static Future<void> saveTags(List<String> tags) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_tagsKey, tags);
  }

  static Future<String> getRandomTag() async {
    final prefs = await SharedPreferences.getInstance();
    final tags = prefs.getStringList(_tagsKey) ?? [];

    if (tags.isEmpty) return "nature";

    final random = Random();
    return tags[random.nextInt(tags.length)];
  }

  /// ---- WALLPAPER LOCATION ----
  static Future<int> getWallpaperLocation() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_wallpaperLocationKey) ?? 3;
  }

  static Future<void> saveWallpaperLocation(int location) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_wallpaperLocationKey, location);
  }

  static Future<void> saveDeviceHeight(int height) async {
    if (height <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_deviceHeightKey, height);
  }

  static Future<int> getDeviceHeight() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_deviceHeightKey) ?? 800;
  }

  static Future<void> saveDeviceWidth(int width) async {
    if (width <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_deviceWidthKey, width);
  }

  static Future<int> getDeviceWidth() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_deviceWidthKey) ?? 360;
  }

  static const _maxHistory = 100;

  static Future<void> saveWallpaperHistory(Wallpaper wallpaper) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_wallpaperHistoryKey) ?? "[]";

    final List<dynamic> history = jsonDecode(raw);

    // Drop any previous entry for the same wallpaper so re-setting it
    // moves it to the top instead of leaving a duplicate.
    history.removeWhere((e) => e is Map && e["id"] == wallpaper.id);

    // Newest entries first.
    history.insert(0, wallpaper.toJson());

    // Keep history from growing without bound.
    if (history.length > _maxHistory) {
      history.removeRange(_maxHistory, history.length);
    }

    await prefs.setString(_wallpaperHistoryKey, jsonEncode(history));
  }

  static Future<void> removeWallpaperHistory(Wallpaper wallpaper) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_wallpaperHistoryKey) ?? "[]";

    final List<dynamic> history = jsonDecode(raw);
    history.removeWhere((e) => e is Map && e["id"] == wallpaper.id);

    await prefs.setString(_wallpaperHistoryKey, jsonEncode(history));
  }

  static Future<List<Wallpaper>> getWallpaperHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_wallpaperHistoryKey) ?? "[]";

    final List<dynamic> list = jsonDecode(raw);

    return list.map((e) => Wallpaper.fromJson(Map<String, dynamic>.from(e))).toList();
  }
// ---- WALLPAPERS for background change ----
  static Future<void> saveWallpapers(List<Wallpaper> wallpapers) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = wallpapers.map((w) => jsonEncode(w.toJson())).toList();
    await prefs.setStringList(_imageUrlsKey, jsonList);
  }

  static Future<List<Wallpaper>> getImageUrls() async {
    final prefs = await SharedPreferences.getInstance();

    List<String> jsonList;
    try {
      jsonList = prefs.getStringList(_imageUrlsKey) ?? [];
    } catch (_) {
      jsonList = [];
    }

    if (jsonList.isEmpty) {
      final raw = prefs.getString(_imageUrlsKey);
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            jsonList = decoded.map((e) {
              if (e is String) return e;
              if (e is Map) return jsonEncode(e);
              return null;
            }).whereType<String>().toList();
          }
        } catch (_) {}
      }
    }

    return jsonList.map((e) {
      try {
        return Wallpaper.fromJson(jsonDecode(e));
      } catch (_) {
        return Wallpaper(id: e.hashCode.toString(), url: e, timestamp: DateTime.now());
      }
    }).toList();
  }

  static Future<void> saveFavWallpaper(Wallpaper wallpaper) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      List<String> history;
      try {
        history = prefs.getStringList(_favWallpaperKey) ?? [];
      } catch (_) {
        history = [];
      }

      final entry = jsonEncode(wallpaper.toJson());

      if (!history.contains(entry)) {
        history.add(entry);
        await prefs.setStringList(_favWallpaperKey, history);
      }
    } catch (e) {
      debugPrint("saveFavWallpaper failed: $e");
    }
  }

  static Future<void> removeFavWallpaper(Wallpaper wallpaper) async {
    final prefs = await SharedPreferences.getInstance();

    List<String> history;
    try {
      history = prefs.getStringList(_favWallpaperKey) ?? [];
    } catch (_) {
      history = [];
    }

    history.removeWhere((item) {
      try {
        final decoded = jsonDecode(item);
        return decoded["id"] == wallpaper.id;
      } catch (_) {
        return false;
      }
    });

    await prefs.setStringList(_favWallpaperKey, history);
  }

  static Future<List<Wallpaper>> getFavWallpapers() async {
    final prefs = await SharedPreferences.getInstance();

    List<String> history;
    try {
      history = prefs.getStringList(_favWallpaperKey) ?? [];
    } catch (_) {
      history = [];
    }

    if (history.isEmpty) {
      final raw = prefs.getString(_favWallpaperKey);
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            history = decoded.map((e) {
              if (e is String) return e;
              if (e is Map) return jsonEncode(e);
              return null;
            }).whereType<String>().toList();
          }
        } catch (_) {}
      }
    }

    return history.map((e) {
      try {
        return Wallpaper.fromJson(jsonDecode(e));
      } catch (_) {
        return Wallpaper(id: e.hashCode.toString(), url: e, timestamp: DateTime.now());
      }
    }).toList();
  }

  static Future<void> saveLastWallpaperChange(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastWallpaperChangeKey, date.toString());
  }

  static Future<DateTime?> getLastWallpaperChange() async {
    final prefs = await SharedPreferences.getInstance();
    final dateStr = prefs.getString(_lastWallpaperChangeKey);
    if (dateStr == null) return null;
    return DateTime.parse(dateStr);
  }

  static Future<void> saveInterval(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyInterval, minutes);
  }

  static Future<int> getInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyInterval) ?? 60;
  }

  /// ---- ERROR REPORTING ----
  static Future<bool> getErrorReportingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_errorReportingKey) ?? true;
  }

  static Future<void> setErrorReportingEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_errorReportingKey, enabled);
  }

  static Future<bool> getAutoWallpaperEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoWallpaperEnabledKey) ?? false;
  }

  static Future<void> setAutoWallpaperEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoWallpaperEnabledKey, enabled);
  }

  static Future<void> setBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  static Future<bool> getBool(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  }

  static Future<void> setConstraintCharging(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_constraintChargingKey, enabled);
  }

  static Future<bool> getConstraintCharging() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_constraintChargingKey) ?? true;
  }

  static Future<void> setConstraintBatteryNotLow(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_constraintBatteryNotLowKey, enabled);
  }

  static Future<bool> getConstraintBatteryNotLow() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_constraintBatteryNotLowKey) ?? false;
  }

  static Future<void> setConstraintStorageNotLow(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_constraintStorageNotLowKey, enabled);
  }

  static Future<bool> getConstraintStorageNotLow() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_constraintStorageNotLowKey) ?? false;
  }

  static Future<void> setConstraintNoFaces(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_constraintNoFacesKey, enabled);
  }

  static Future<bool> getConstraintNoFaces() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_constraintNoFacesKey) ?? true;
  }

  static Future<void> setConstraintWifi(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_constraintWifiKey, enabled);
  }

  static Future<bool> getConstraintWifi() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_constraintWifiKey) ?? true;
  }

  /// ---- WALLPAPER SOURCE (multi-select) ----
  /// Sources are stored as a comma-separated string e.g. "internet,folder,favorites".
  static Future<List<String>> getWallpaperSources() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_wallpaperSourceKey) ?? "internet";
    final list = raw.split(",").map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    return list.isEmpty ? ["internet"] : list;
  }

  static Future<void> saveWallpaperSources(List<String> sources) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_wallpaperSourceKey, sources.join(","));
  }

  /// Legacy single-source accessor – returns the first source, or "internet".
  static Future<String> getWallpaperSource() async {
    final sources = await getWallpaperSources();
    return sources.first;
  }

  static Future<void> setWallpaperSource(String source) async {
    await saveWallpaperSources([source]);
  }

  /// ---- FOLDER PATH ----
  static Future<String?> getFolderPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_folderPathKey);
  }

  static Future<void> setFolderPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_folderPathKey, path);
  }

  /// ---- CACHED WALLPAPER PATHS ----
  static Future<void> saveCachedWallpaperPaths(List<String> paths) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachedWallpaperPathsKey, jsonEncode(paths));
  }

  static Future<List<String>> getCachedWallpaperPaths() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cachedWallpaperPathsKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.cast<String>();
    } catch (_) {}
    return [];
  }

  static Future<void> clearCachedWallpaperPaths() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cachedWallpaperPathsKey);
  }

  /// ---- INVALID TAGS ----
  static const _invalidTagsKey = "invalidTags";

  static Future<Set<String>> getInvalidTags() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_invalidTagsKey)?.toSet() ?? {};
  }

  static Future<void> saveInvalidTags(Set<String> tags) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_invalidTagsKey, tags.toList());
  }

  /// ---- DISCOVER FILTERS ----
  static const _keyFilterSorting = "discover_filter_sorting";
  static const _keyFilterPurity = "discover_filter_purity";
  static const _keyFilterOrientation = "discover_filter_orientation";
  static const _keyFilterCategory = "discover_filter_category";
  static const _keyFilterRange = "discover_filter_range";

  static Future<String?> getFilterSorting() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyFilterSorting);
  }
  static Future<void> setFilterSorting(String? val) async {
    final prefs = await SharedPreferences.getInstance();
    if (val == null) { await prefs.remove(_keyFilterSorting); } else { await prefs.setString(_keyFilterSorting, val); }
  }

  static Future<String?> getFilterPurity() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyFilterPurity);
  }
  static Future<void> setFilterPurity(String? val) async {
    final prefs = await SharedPreferences.getInstance();
    if (val == null) { await prefs.remove(_keyFilterPurity); } else { await prefs.setString(_keyFilterPurity, val); }
  }

  static Future<String?> getFilterOrientation() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyFilterOrientation);
  }
  static Future<void> setFilterOrientation(String? val) async {
    final prefs = await SharedPreferences.getInstance();
    if (val == null) { await prefs.remove(_keyFilterOrientation); } else { await prefs.setString(_keyFilterOrientation, val); }
  }

  static Future<String?> getFilterCategory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyFilterCategory);
  }
  static Future<void> setFilterCategory(String? val) async {
    final prefs = await SharedPreferences.getInstance();
    if (val == null) { await prefs.remove(_keyFilterCategory); } else { await prefs.setString(_keyFilterCategory, val); }
  }

  static Future<String?> getFilterRange() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyFilterRange);
  }
  static Future<void> setFilterRange(String? val) async {
    final prefs = await SharedPreferences.getInstance();
    if (val == null) { await prefs.remove(_keyFilterRange); } else { await prefs.setString(_keyFilterRange, val); }
  }

  /// ---- MONET THEME ----
  static Future<bool> getUseMonetTheme() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useMonetThemeKey) ?? false;
  }

  static Future<void> setUseMonetTheme(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useMonetThemeKey, enabled);
  }
}
