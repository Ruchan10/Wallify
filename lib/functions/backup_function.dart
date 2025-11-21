import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsBackup {
  static Future<File> exportSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final data = {
      "tags": prefs.getStringList("tags") ?? [],
      "wallpaperLocation": prefs.getInt("wallpaperLocation") ?? 3,
      "deviceWidth": prefs.getInt("deviceWidth") ?? 360,
      "deviceHeight": prefs.getInt("deviceHeight") ?? 800,
      "wallpaperHistory": prefs.getString("wallpaperHistory") ?? "[]",
      "autoWallpaperEnabled": prefs.getBool("autoWallpaperEnabled") ?? false,
      "lastWallpaperChange": prefs.getString("lastWallpaperChange"),
      "interval": prefs.getInt("wallpaper_interval") ?? 60,
      "favWallpapers": prefs.getStringList("favWallpaper") ?? [],
      "imageUrls": prefs.getStringList("imageUrls") ?? [],
      "errorReportingEnabled": prefs.getBool("errorReportingEnabled") ?? true,

      // Constraints
      "constraint_charging": prefs.getBool("constraint_charging") ?? true,
      "constraint_battery_not_low":
          prefs.getBool("constraint_battery_not_low") ?? false,
      "constraint_storage_not_low":
          prefs.getBool("constraint_storage_not_low") ?? false,
      "constraint_no_faces": prefs.getBool("constraint_no_faces") ?? true,
      "constraint_wifi": prefs.getBool("constraint_wifi") ?? true,
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(data);

    final dir = Directory('/storage/emulated/0/Download');
    final file = File("${dir.path}/wallify_settings_backup.json");
    await file.writeAsString(jsonString, flush: true);

    return file;
  }

  static Future<void> importSettings(File file) async {
    final prefs = await SharedPreferences.getInstance();
    final content = await file.readAsString();
    final data = jsonDecode(content);

    if (data is! Map<String, dynamic>) return;

    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value is String) {
        await prefs.setString(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is List) {
        await prefs.setStringList(key, value.cast<String>());
      }
    }
  }
}
