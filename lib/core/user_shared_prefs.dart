import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserSharedPrefs {
  static const _tagsKey = "tags";
  static const _wallpaperLocationKey = "wallpaperLocation";
  static const _statusHistoryKey = "statusHistory";
  static const _pendingActionKey = "pendingAction";

  /// ---- TAGS ----
  static Future<List<String>> getTags() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_tagsKey) ?? [];
  }

  static Future<void> saveTags(List<String> tags) async {
    debugPrint("Saving tags: $tags ===================================");
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_tagsKey, tags);
  }

  /// ---- WALLPAPER LOCATION ----
  static Future<int?> getWallpaperLocation() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_wallpaperLocationKey);
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
    debugPrint(
      "Saving status history: $history ===================================",
    );
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(history);
    await prefs.setString(_statusHistoryKey, encoded);
  }

  /// ---- PENDING ACTION ----
  static Future<String?> getPendingAction() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pendingActionKey);
  }

  static Future<void> savePendingAction(String tag) async {
    debugPrint(
      "Saving pending action: $tag ===================================",
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingActionKey, tag);
  }

  static Future<void> clearPendingAction() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingActionKey);
  }
}
