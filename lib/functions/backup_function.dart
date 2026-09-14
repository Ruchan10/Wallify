import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _PrefType { string, integer, boolean, stringList }

class SettingsBackup {
  static const _format = "wallify-backup";
  static const _version = 2;

  /// Everything a backup carries. Device-specific state (screen size, cached
  /// file paths, usage tracking, worker logs) is deliberately left out so a
  /// backup can be restored on another phone.
  static const Map<String, _PrefType> _keys = {
    // Wallpapers
    "tags": _PrefType.stringList,
    "invalidTags": _PrefType.stringList,
    "favWallpaper": _PrefType.stringList,
    "imageUrls": _PrefType.stringList,
    "wallpaperHistory": _PrefType.string,
    "wallpaperLocation": _PrefType.integer,
    "wallpaperSource": _PrefType.string,
    "folderPath": _PrefType.string,
    "customApis": _PrefType.stringList,

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

  /// Writes a backup to Downloads and returns a human-readable location.
  static Future<String> exportSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // pick up values the native worker wrote

    final settings = <String, dynamic>{};
    for (final key in _keys.keys) {
      final value = prefs.get(key);
      if (value != null) settings[key] = value;
    }

    final data = {
      "format": _format,
      "version": _version,
      "exportedAt": DateTime.now().toIso8601String(),
      "settings": settings,
    };
    final jsonString = const JsonEncoder.withIndent('  ').convert(data);

    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final fileName = "Wallify_backup_$stamp.json";

    final tempFile = File("${(await getTemporaryDirectory()).path}/$fileName");
    await tempFile.writeAsString(jsonString, flush: true);

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
      if (result != null) {
        await tempFile.delete();
        return "Downloads/Wallify/$fileName";
      }
    } catch (_) {
      // Fall back to app-accessible directories below.
    }

    final dir = await getDownloadsDirectory() ??
        await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/$fileName");
    await tempFile.copy(file.path);
    await tempFile.delete();
    return file.path;
  }

  /// Restores a backup. Only known settings are written; anything else in the
  /// file is counted as skipped. Also accepts the older flat backup format.
  static Future<({int imported, int skipped})> importSettings(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException("Not a Wallify backup file");
    }

    final Map<String, dynamic> settings;
    if (decoded.containsKey("format")) {
      if (decoded["format"] != _format || decoded["settings"] is! Map) {
        throw const FormatException("Not a Wallify backup file");
      }
      settings = Map<String, dynamic>.from(decoded["settings"] as Map);
    } else {
      settings = decoded; // v1: settings at the top level
    }

    if (!settings.keys.any(_keys.containsKey)) {
      throw const FormatException("Not a Wallify backup file");
    }

    final prefs = await SharedPreferences.getInstance();
    var imported = 0;
    var skipped = 0;

    for (final entry in settings.entries) {
      final type = _keys[entry.key];
      final ok = type != null && await _write(prefs, entry.key, type, entry.value);
      ok ? imported++ : skipped++;
    }

    return (imported: imported, skipped: skipped);
  }

  static Future<bool> _write(
    SharedPreferences prefs,
    String key,
    _PrefType type,
    dynamic value,
  ) async {
    switch (type) {
      case _PrefType.string:
        if (value is! String) return false;
        return prefs.setString(key, value);
      case _PrefType.integer:
        if (value is! num) return false;
        return prefs.setInt(key, value.toInt());
      case _PrefType.boolean:
        if (value is! bool) return false;
        return prefs.setBool(key, value);
      case _PrefType.stringList:
        // Older installs stored some lists as a JSON string; keep that form.
        if (value is String) return prefs.setString(key, value);
        if (value is! List || value.any((e) => e is! String)) return false;
        return prefs.setStringList(key, value.cast<String>());
    }
  }
}
