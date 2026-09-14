import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/model/wallpaper_model.dart';

class FetchOptions {
  final String? query;
  final int page;
  final int perPage;
  final String? sorting;
  final String? purity;
  final String? orientation;
  final String? category;
  final String? range;

  const FetchOptions({
    this.query,
    this.page = 1,
    this.perPage = 20,
    this.sorting,
    this.purity,
    this.orientation,
    this.category,
    this.range,
  });
}

class WallpaperApiService {
  static const _timeout = Duration(seconds: 15);

  static Future<List<Wallpaper>> fetchWallhaven(FetchOptions opts) async {
    final categoryParam = opts.category == null
        ? ""
        : "&categories=${opts.category == "general"
              ? "100"
              : opts.category == "anime"
              ? "101"
              : "110"}";
    final purityParam = opts.purity == null
        ? ""
        : "&purity=${opts.purity == "SFW"
              ? "100"
              : opts.purity == "Sketchy"
              ? "110"
              : "111"}";
    // Best-rated first by default; an explicit Discover sort still wins.
    final sorting = opts.sorting ?? "toplist";
    final rangeParam =
        sorting == "toplist" ? "&topRange=${opts.range ?? "1M"}" : "";
    final searchParam = opts.query == null
        ? ""
        : "&q=${Uri.encodeQueryComponent(opts.query!)}";

    final res = await http
        .get(
          Uri.parse(
            "https://wallhaven.cc/api/v1/search?"
            "page=${opts.page}"
            "$rangeParam"
            "$categoryParam"
            "$purityParam"
            "&sorting=$sorting"
            "$searchParam"
            "&order=desc",
          ),
        )
        .timeout(_timeout);

    final data = jsonDecode(res.body);
    final list = <Wallpaper>[];
    if (data["data"] is List) {
      for (var item in data["data"]) {
        list.add(
          Wallpaper(
            id: item["id"],
            url: item["path"],
            timestamp: DateTime.now(),
            width: Wallpaper.parseNum(item["dimension_x"])?.toInt(),
            height: Wallpaper.parseNum(item["dimension_y"])?.toInt(),
          ),
        );
      }
    }
    return list;
  }

  static Future<List<Wallpaper>> fetchUnsplash(FetchOptions opts) async {
    final apiKey = await UserSharedPrefs.getUnsplashApiKey();
    final isSearch = opts.query != null;
    final url = isSearch
        ? "https://api.unsplash.com/search/photos"
        : "https://api.unsplash.com/photos";

    // Browsing: most popular. Search only supports relevant/latest, and
    // relevance is the best-quality ordering there.
    final orderBy = opts.sorting == "date_added"
        ? "latest"
        : isSearch
        ? "relevant"
        : "popular";

    final params = <String>[
      if (isSearch) "query=${Uri.encodeQueryComponent(opts.query!)}",
      "order_by=$orderBy",
      if (opts.purity != null)
        "content_filter=${opts.purity == "NSFW" ? "high" : "low"}",
      if (opts.orientation != null) "orientation=${opts.orientation}",
      "page=${opts.page}",
      "per_page=${opts.perPage}",
    ];

    final res = await http
        .get(
          Uri.parse("$url?${params.join("&")}"),
          headers: {"Authorization": "Client-ID $apiKey"},
        )
        .timeout(_timeout);

    final data = jsonDecode(res.body);
    final items = isSearch
        ? (data["results"] is List ? data["results"] : <dynamic>[])
        : (data is List ? data : <dynamic>[]);

    return items
        .take(opts.perPage)
        .map<Wallpaper>(
          (item) => Wallpaper(
            id: item["id"],
            url: item["urls"]["regular"],
            timestamp: DateTime.now(),
            width: Wallpaper.parseNum(item["width"])?.toInt(),
            height: Wallpaper.parseNum(item["height"])?.toInt(),
          ),
        )
        .toList();
  }

  static Future<List<Wallpaper>> fetchPixabay(FetchOptions opts) async {
    final apiKey = await UserSharedPrefs.getPixabayApiKey();
    if (apiKey == null || apiKey.isEmpty) return [];

    final pixabayQuery =
        opts.query != null && opts.query!.length > 99
            ? opts.query!.substring(0, 99)
            : opts.query;

    final params = <String>[
      "key=$apiKey",
      if (pixabayQuery != null)
        "q=${Uri.encodeQueryComponent(pixabayQuery)}",
      "image_type=photo",
      if (opts.purity != null)
        "safesearch=${opts.purity == "NSFW" ? "false" : "true"}",
      "order=${opts.sorting == "date_added" ? "latest" : "popular"}",
      // Pixabay only understands vertical/horizontal.
      if (opts.orientation == "portrait") "orientation=vertical",
      if (opts.orientation == "landscape") "orientation=horizontal",
      "page=${opts.page}",
      "per_page=${opts.perPage}",
    ];

    final res = await http
        .get(Uri.parse("https://pixabay.com/api/?${params.join("&")}"))
        .timeout(_timeout);

    final data = jsonDecode(res.body);
    final list = <Wallpaper>[];
    if (data["hits"] is List) {
      for (var item in data["hits"]) {
        list.add(
          Wallpaper(
            id: item["id"].toString(),
            url: item["largeImageURL"],
            timestamp: DateTime.now(),
            width: Wallpaper.parseNum(item["imageWidth"])?.toInt(),
            height: Wallpaper.parseNum(item["imageHeight"])?.toInt(),
          ),
        );
      }
    }
    return list;
  }

  static Future<List<Wallpaper>> fetchPexels(FetchOptions opts) async {
    final apiKey = await UserSharedPrefs.getPexelsApiKey();
    if (apiKey == null || apiKey.isEmpty) return [];

    // Pexels has no sort parameter: "curated" is its hand-picked best-of
    // feed, and search results are ranked by relevance.
    final isSearch = opts.query != null;
    final endpoint = isSearch ? "v1/search" : "v1/curated";

    final params = <String>[
      "page=${opts.page}",
      "per_page=${opts.perPage}",
      if (isSearch) "query=${Uri.encodeQueryComponent(opts.query!)}",
    ];

    final res = await http
        .get(
          Uri.parse("https://api.pexels.com/$endpoint?${params.join("&")}"),
          headers: {"Authorization": apiKey},
        )
        .timeout(_timeout);

    if (res.statusCode != 200) {
      debugPrint("Pexels HTTP ${res.statusCode}");
      return [];
    }

    final data = jsonDecode(res.body);
    final photos = data["photos"];
    final list = <Wallpaper>[];
    if (photos is List) {
      for (var item in photos) {
        final src = item["src"];
        if (src is Map && src["original"] != null) {
          list.add(
            Wallpaper(
              id: item["id"].toString(),
              url: src["original"],
              timestamp: DateTime.now(),
              width: Wallpaper.parseNum(item["width"])?.toInt(),
              height: Wallpaper.parseNum(item["height"])?.toInt(),
            ),
          );
        }
      }
    }
    return list;
  }

  static Future<List<Wallpaper>> fetchLoremPicsum(FetchOptions opts) async {
    final res = await http
        .get(
          Uri.parse(
            "https://picsum.photos/v2/list?page=${opts.page}&limit=${opts.perPage}",
          ),
        )
        .timeout(_timeout);

    if (res.statusCode != 200) return [];

    final data = jsonDecode(res.body);
    final list = <Wallpaper>[];
    if (data is List) {
      for (var item in data) {
        final downloadUrl = item["download_url"] as String?;
        if (downloadUrl != null) {
          list.add(
            Wallpaper(
              id: item["id"].toString(),
              url: downloadUrl,
              timestamp: DateTime.now(),
              width: Wallpaper.parseNum(item["width"])?.toInt(),
              height: Wallpaper.parseNum(item["height"])?.toInt(),
            ),
          );
        }
      }
    }
    return list;
  }

  static Future<List<Wallpaper>> fetchAll({
    required List<String> sources,
    required FetchOptions Function(String source) optionsFor,
  }) async {
    final futures = <Future<List<Wallpaper>>>[];
    for (final source in sources) {
      final opts = optionsFor(source);
      final Future<List<Wallpaper>> future = switch (source) {
        "wallhaven" => fetchWallhaven(opts),
        "unsplash" => fetchUnsplash(opts),
        "pixabay" => fetchPixabay(opts),
        "pexels" => fetchPexels(opts),
        "lorempicsum" => fetchLoremPicsum(opts),
        _ => Future.value(<Wallpaper>[]),
      };
      futures.add(future.catchError((e) {
        debugPrint("$source failed: $e");
        return <Wallpaper>[];
      }));
    }
    final results = await Future.wait(futures);
    final all = <Wallpaper>[];
    for (final list in results) {
      all.addAll(list);
    }
    return all;
  }

  static Future<bool> validateTag(String tag) async {
    try {
      final results = await fetchAll(
        sources: ["wallhaven", "unsplash", "pixabay"],
        optionsFor: (source) => FetchOptions(
          query: tag,
          perPage: 1,
          sorting: "relevance",
        ),
      );
      return results.isNotEmpty;
    } catch (e) {
      debugPrint("Tag validation error: $e");
      return false;
    }
  }

  static Future<bool> testPexelsKey(String key) async {
    try {
      final res = await http
          .get(
            Uri.parse(
              "https://api.pexels.com/v1/search?query=nature&per_page=1&orientation=portrait",
            ),
            headers: {"Authorization": key},
          )
          .timeout(const Duration(seconds: 12));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> testPixabayKey(String key) async {
    try {
      final res = await http
          .get(
            Uri.parse(
              "https://pixabay.com/api/?key=$key&q=nature&per_page=3&orientation=vertical",
            ),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return false;
      final body = jsonDecode(res.body);
      return body is Map && body["hits"] is List;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> testUnsplashKey(String key) async {
    try {
      final res = await http
          .get(
            Uri.parse(
              "https://api.unsplash.com/search/photos?query=nature&per_page=1&orientation=portrait",
            ),
            headers: {"Authorization": "Client-ID $key"},
          )
          .timeout(const Duration(seconds: 12));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> testGeminiKey(String key) async {
    try {
      final res = await http
          .get(
            Uri.parse(
              "https://generativelanguage.googleapis.com/v1beta/models?key=$key",
            ),
          )
          .timeout(const Duration(seconds: 12));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
