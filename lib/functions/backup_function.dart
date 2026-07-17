import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallify/core/user_shared_prefs.dart';

class SettingsBackup {
  static Future<File> exportSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final imageWallpapers = await UserSharedPrefs.getImageUrls();
    final favWallpapers = await UserSharedPrefs.getFavWallpapers();

    final data = {
      "tags": await UserSharedPrefs.getTags(),
      "invalidTags": (await UserSharedPrefs.getInvalidTags()).toList(),
      "wallpaperLocation": await UserSharedPrefs.getWallpaperLocation(),
      "deviceWidth": await UserSharedPrefs.getDeviceWidth(),
      "deviceHeight": await UserSharedPrefs.getDeviceHeight(),
      "wallpaperHistory": prefs.getString("wallpaperHistory") ?? "[]",
      "autoWallpaperEnabled": await UserSharedPrefs.getAutoWallpaperEnabled(),
      "lastWallpaperChange": prefs.getString("lastWallpaperChange"),
      "wallpaper_interval": await UserSharedPrefs.getInterval(),
      "favWallpaper": favWallpapers.map((w) => jsonEncode(w.toJson())).toList(),
      "imageUrls": imageWallpapers.map((w) => jsonEncode(w.toJson())).toList(),
      "errorReportingEnabled": await UserSharedPrefs.getErrorReportingEnabled(),
      "useMonetTheme": await UserSharedPrefs.getUseMonetTheme(),
      "wallpaperSource": prefs.getString("wallpaperSource") ?? "internet",
      "folderPath": await UserSharedPrefs.getFolderPath(),

      // Constraints
      "constraint_charging": await UserSharedPrefs.getConstraintCharging(),
      "constraint_battery_not_low": await UserSharedPrefs.getConstraintBatteryNotLow(),
      "constraint_storage_not_low": await UserSharedPrefs.getConstraintStorageNotLow(),
      "constraint_no_faces": await UserSharedPrefs.getConstraintNoFaces(),
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(data);

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = "WallifyBackup.json";

    final appDir = await getTemporaryDirectory();
    final tempFile = File("${appDir.path}/$fileName");
    await tempFile.writeAsString(jsonString, flush: true);

    try {
      const channel = MethodChannel('wallpaper_channel');
      final result = await channel.invokeMethod<String>(
        'saveToDownloads',
        {'filePath': tempFile.path, 'fileName': fileName},
      );
      if (result != null) {
        await tempFile.delete();
        return File(result);
      }
    } catch (_) {
      // Fall back to legacy methods
    }

    final downloadDir = await getDownloadsDirectory();
    if (downloadDir != null) {
      final file = File("${downloadDir.path}/$fileName");
      await file.writeAsString(jsonString, flush: true);
      return file;
    }

    final extDir = await getExternalStorageDirectory();
    if (extDir != null) {
      final downloadSubdir = Directory("${extDir.path}/Download");
      if (!await downloadSubdir.exists()) {
        await downloadSubdir.create(recursive: true);
      }
      final file = File("${downloadSubdir.path}/$fileName");
      await file.writeAsString(jsonString, flush: true);
      return file;
    }

    final docDir = await getApplicationDocumentsDirectory();
    final file = File("${docDir.path}/$fileName");
    await file.writeAsString(jsonString, flush: true);
    return file;
  }

  static Future<int> importSettings(File file) async {
    final content = await file.readAsString();
    final decoded = jsonDecode(content);

    if (decoded is! Map<String, dynamic>) {
      throw FormatException("Invalid backup file: expected a JSON object");
    }

    final prefs = await SharedPreferences.getInstance();
    int count = 0;

    for (final entry in decoded.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value is String) {
        await prefs.setString(key, value);
        count++;
      } else if (value is int) {
        await prefs.setInt(key, value);
        count++;
      } else if (value is bool) {
        await prefs.setBool(key, value);
        count++;
      } else if (value is List) {
        final validStrings = <String>[];
        bool allStrings = true;
        for (final item in value) {
          if (item is String) {
            validStrings.add(item);
          } else {
            allStrings = false;
          }
        }
        if (allStrings) {
          await prefs.setStringList(key, validStrings);
          count++;
        }
      }
    }

    return count;
  }
}
