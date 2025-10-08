import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsBackup {
  static Future<File> exportSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final data = {
      "tags": prefs.getStringList("_tagsKey") ?? [],
      "wallpaperLocation": prefs.getInt("_wallpaperLocationKey") ?? 3,
      "favWallpapers": prefs.getStringList("_favWallpaperKey") ?? [],
      "interval": prefs.getInt("_keyInterval") ?? 1,
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(data);

    Directory? downloadsDir;

    if (Platform.isAndroid) {
      downloadsDir = Directory('/storage/emulated/0/Download');
      if (!await downloadsDir.exists()) {
        downloadsDir = await getApplicationDocumentsDirectory();
      }
    } else if (Platform.isIOS) {
      downloadsDir = await getApplicationDocumentsDirectory();
    } else {
      downloadsDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    }

    final filePath = "${downloadsDir.path}/wallify_settings_backup.json";
    final file = File(filePath);

    await file.writeAsString(jsonString, flush: true);

    return file;
  }


  static Future<void> importSettings(File file) async {
    final prefs = await SharedPreferences.getInstance();
    final content = await file.readAsString();
    final data = jsonDecode(content);

    if (data is Map<String, dynamic>) {
      if (data.containsKey("tags")) {
        await prefs.setStringList("_tagsKey", List<String>.from(data["tags"]));
      }
      if (data.containsKey("wallpaperLocation")) {
        await prefs.setInt("_wallpaperLocationKey", data["wallpaperLocation"]);
      }
      if (data.containsKey("favWallpapers")) {
        await prefs.setStringList(
            "_favWallpaperKey", List<String>.from(data["favWallpapers"]));
      }
      if (data.containsKey("interval")) {
        await prefs.setInt("_keyInterval", data["interval"]);
      }
    }
  }
}
