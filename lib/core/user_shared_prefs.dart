import 'dart:convert';
import 'dart:math';

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

  static Future<void> saveWallpaperHistory(Wallpaper wallpaper) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_wallpaperHistoryKey) ?? "[]";

    final List<dynamic> history = jsonDecode(raw);

    final exists = history.any((item) => item["id"] == wallpaper.id);

    if (!exists) {
      history.add(wallpaper.toJson());
      await prefs.setString(_wallpaperHistoryKey, jsonEncode(history));
    }
  }

  static Future<List<Map<String, dynamic>>> getWallpaperHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_wallpaperHistoryKey) ?? "[]";

    final List<dynamic> list = jsonDecode(raw);

    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }
// ---- WALLPAPERS for background change ----
  static Future<void> saveWallpapers(List<Wallpaper> wallpapers) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = wallpapers.map((w) => jsonEncode(w.toJson())).toList();
    await prefs.setStringList(_imageUrlsKey, jsonList);
  }

  static Future<List<Wallpaper>> getImageUrls() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_imageUrlsKey) ?? [];
    return jsonList.map((e) => Wallpaper.fromJson(jsonDecode(e))).toList();
  }

  static Future<void> saveFavWallpaper(Wallpaper wallpaper) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_favWallpaperKey) ?? [];

    final entry = jsonEncode(wallpaper.toJson());

    if (!history.contains(entry)) {
      history.add(entry);
      await prefs.setStringList(_favWallpaperKey, history);
    }
  }

  static Future<void> removeFavWallpaper(Wallpaper wallpaper) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_favWallpaperKey) ?? [];

    history.removeWhere((item) {
      final decoded = jsonDecode(item);
      return decoded["id"] == wallpaper.id;
    });

    await prefs.setStringList(_favWallpaperKey, history);
  }

  static Future<List<Wallpaper>> getFavWallpapers() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_favWallpaperKey) ?? [];

    return history.map((e) => Wallpaper.fromJson(jsonDecode(e))).toList();
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
}
