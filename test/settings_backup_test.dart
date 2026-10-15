import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallify/functions/backup_function.dart';
import 'package:wallify/model/wallpaper_model.dart';
import 'package:wallify/services/wallpaper_api_service.dart';

List<int> _backup(Map<String, Object?> settings) => utf8.encode(
  jsonEncode({
    "format": "wallify-backup",
    "version": 3,
    "exportedAt": "2026-10-01T10:00:00.000",
    "appVersion": "1.6.1",
    "settings": settings,
  }),
);

String _fav(String id) => jsonEncode({"id": id, "url": "https://x/$id.jpg"});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("SettingsBackup.parse", () {
    test("rejects files that aren't backups", () {
      expect(() => SettingsBackup.parse([]), throwsFormatException);
      expect(
        () => SettingsBackup.parse(utf8.encode("not json")),
        throwsFormatException,
      );
      expect(
        () => SettingsBackup.parse(utf8.encode('{"hello": 1}')),
        throwsFormatException,
      );
      expect(
        () => SettingsBackup.parse([0xff, 0xfe, 0x00]),
        throwsFormatException,
      );
    });

    test("accepts a UTF-8 BOM and the old flat format", () {
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('{"tags": ["a"]}')];
      expect(SettingsBackup.parse(bytes).settings["tags"], ["a"]);
    });

    test("cleans values and rejects nonsense", () {
      final preview = SettingsBackup.parse(
        _backup({
          "tags": [" space ", "Space", "", "ocean"],
          "wallpaperLocation": 4,
          "wallpaper_interval": 5,
          "themeMode": 9,
          "wallpaperSource": "internet,bogus",
          "favWallpaper": [
            _fav("1"),
            _fav("1"),
            "garbage",
            {"id": "2", "url": "https://x/2"},
          ],
          "scheduleDays": "[0, 3, 3, 8, 1]",
          "pexels_api_key": "  abc  ",
          "gemini_api_key": "   ",
          "imageUrls": ["ignored"],
          "unknown_key": true,
        }),
      );
      final s = preview.settings;
      expect(s["tags"], ["space", "ocean"]);
      expect(s["wallpaperLocation"], 3, reason: "random mode becomes both");
      expect(s["wallpaper_interval"], 15);
      expect(s.containsKey("themeMode"), isFalse);
      expect(s["wallpaperSource"], "internet");
      expect((s["favWallpaper"] as List).length, 2);
      expect(s["scheduleDays"], "[1,3]");
      expect(s["pexels_api_key"], "abc");
      expect(s.containsKey("gemini_api_key"), isFalse);
      expect(s.containsKey("imageUrls"), isFalse);
      expect(
        preview.rejected,
        containsAll(["themeMode", "gemini_api_key", "unknown_key"]),
      );
      expect(preview.rejected, isNot(contains("imageUrls")));
      expect(preview.apiKeyNames, ["Pexels"]);
      expect(preview.appVersion, "1.6.1");
    });
  });

  group("SettingsBackup.importSettings", () {
    test(
      "merges favorites and tags, replaces the rest, honours key opt-out",
      () async {
        SharedPreferences.setMockInitialValues({
          "favWallpaper": [_fav("1")],
          "tags": ["nature"],
          "wallpaperLocation": 1,
          "pexels_api_key": "mine",
        });
        final preview = SettingsBackup.parse(
          _backup({
            "favWallpaper": [_fav("1"), _fav("2")],
            "tags": ["Nature", "space"],
            "wallpaperLocation": 2,
            "pexels_api_key": "theirs",
          }),
        );

        final result = await SettingsBackup.importSettings(
          preview,
          includeApiKeys: false,
        );
        final prefs = await SharedPreferences.getInstance();

        expect(prefs.getStringList("favWallpaper"), [_fav("1"), _fav("2")]);
        expect(prefs.getStringList("tags"), ["nature", "space"]);
        expect(prefs.getInt("wallpaperLocation"), 2);
        expect(prefs.getString("pexels_api_key"), "mine");
        expect(result.imported, 3);
      },
    );

    test("merges history newest first", () async {
      SharedPreferences.setMockInitialValues({
        "wallpaperHistory": jsonEncode([
          {"id": "a", "url": "u/a", "timestamp": "2026-01-02T00:00:00.000"},
        ]),
      });
      final preview = SettingsBackup.parse(
        _backup({
          "wallpaperHistory": jsonEncode([
            {"id": "b", "url": "u/b", "timestamp": "2026-01-03T00:00:00.000"},
            {"id": "a", "url": "u/a", "timestamp": "2026-01-02T00:00:00.000"},
          ]),
        }),
      );
      await SettingsBackup.importSettings(preview);
      final prefs = await SharedPreferences.getInstance();
      final ids = (jsonDecode(prefs.getString("wallpaperHistory")!) as List)
          .map((e) => e["id"]);
      expect(ids, ["b", "a"]);
    });
  });

  test("interleave alternates sources, keeps order and drops duplicates", () {
    Wallpaper w(String id) => Wallpaper(id: id, url: "u/$id");
    final merged = WallpaperApiService.interleave([
      [w("a1"), w("a2"), w("a3")],
      [w("b1"), w("a2")],
      [],
    ]);
    expect(merged.map((e) => e.id), ["a1", "b1", "a2", "a3"]);
  });
}
