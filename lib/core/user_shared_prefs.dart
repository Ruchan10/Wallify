import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallify/model/wallpaper_model.dart';

class UserSharedPrefs {
  static const _tagsKey = "tags";
  static const _wallpaperLocationKey = "wallpaperLocation";
  static const _statusHistoryKey = "statusHistory";
  static const _pendingActionKey = "pendingAction";
  static const _deviceHeightKey = "deviceHeight";
  static const _deviceWidthKey = "deviceWidth";
  static const _selectedSourcesKey = "selectedSources";
  static const _wallpaperHistoryKey = "wallpaperHistory";
  static const _lastWallpaperChangeKey = "lastWallpaperChange";
  static const _keyInterval = "wallpaper_interval";
  static const _favWallpaperKey = "favWallpaper";
  static const _imageUrlsKey = "imageUrls";

  /// ---- TAGS ----
  static Future<List<String>> getTags() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_tagsKey) ?? [];
  }

  static Future<void> saveTags(List<String> tags) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_tagsKey, tags);
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

  /// ---- STATUS HISTORY ----
  static Future<List<Map<String, String>>> getStatusHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_statusHistoryKey);
    if (data == null) return [];
    final decoded = jsonDecode(data) as List;
    return decoded.map((e) => Map<String, String>.from(e)).toList();
  }

  static Future<void> saveStatusHistory(
    List<Map<String, String>> history,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(history);
    await prefs.setString(_statusHistoryKey, encoded);
  }

  /// ---- PENDING ACTION ----
  static Future<bool> getPendingAction() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_pendingActionKey) ?? false;
  }

  static Future<void> savePendingAction(bool pending) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pendingActionKey, pending);
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

  static Future<void> saveSelectedSources(List<String> sources) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_selectedSourcesKey, sources);
  }

  static Future<List<String>> getSelectedSources() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_selectedSourcesKey) ??
        ["wallhaven", "unsplash", "pixabay"];
  }
static Future<void> saveWallpaperHistory(Wallpaper wallpaper) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_wallpaperHistoryKey) ?? [];

    final entry = jsonEncode(wallpaper.toJson());

    // Avoid duplicates by checking `id`
    final exists = history.any((item) {
      final decoded = jsonDecode(item);
      return decoded["id"] == wallpaper.id;
    });

    if (!exists) {
      history.add(entry);
      await prefs.setStringList(_wallpaperHistoryKey, history);
    }
  }

  /// Get full wallpaper history
  static Future<List<Wallpaper>> getWallpaperHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_wallpaperHistoryKey) ?? [];

    return history.map((e) => Wallpaper.fromJson(jsonDecode(e))).toList();
  }
static Future<void> saveWallpapers(List<Wallpaper> wallpapers) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = wallpapers.map((w) => jsonEncode(w.toJson())).toList();
    await prefs.setStringList(_imageUrlsKey, jsonList);
  }

  /// Get one random wallpaper (and remove it from the list)
  static Future<Wallpaper?> getRandomWallpaper() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_imageUrlsKey) ?? [];

    if (jsonList.isEmpty) return null;

    final wallpapers =
        jsonList.map((e) => Wallpaper.fromJson(jsonDecode(e))).toList();

    final random = Random();
    final index = random.nextInt(wallpapers.length);
    final selected = wallpapers[index];

    wallpapers.removeAt(index);

    // Save back the reduced list
    final updatedJsonList =
        wallpapers.map((w) => jsonEncode(w.toJson())).toList();
    await prefs.setStringList(_imageUrlsKey, updatedJsonList);

    return selected;
  }

  static Future<void> saveFavWallpaper(Wallpaper wallpaper) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_favWallpaperKey) ?? [];

    // Encode new wallpaper as JSON
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
      return decoded["id"] == wallpaper.id; // remove by id
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

  static Future<int?> getInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyInterval);
  }
}
