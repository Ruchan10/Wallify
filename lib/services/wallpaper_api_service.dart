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

  /// Smallest acceptable image size in pixels, where the source supports it.
  final int? minWidth;
  final int? minHeight;

  /// Ask for the source's own "best of" selection (editor's choice, curated).
  final bool bestOf;

  const FetchOptions({
    this.query,
    this.page = 1,
    this.perPage = 20,
    this.sorting,
    this.purity,
    this.orientation,
    this.category,
    this.range,
    this.minWidth,
    this.minHeight,
    this.bestOf = false,
  });
}

/// Thrown when a source answers with something other than results, so callers
/// can tell "no results" apart from "source unreachable".
class SourceException implements Exception {
  final String source;
  final int statusCode;
  const SourceException(this.source, this.statusCode);

  @override
  String toString() => "$source HTTP $statusCode";
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
    // Browsing defaults to best-rated; searching defaults to best match,
    // because "toplist" only searches the top wallpapers of the last month.
    // An explicit Discover sort still wins.
    final sorting =
        opts.sorting ?? (opts.query == null ? "toplist" : "relevance");
    final rangeParam = sorting == "toplist"
        ? "&topRange=${_wallhavenRange(opts.range ?? "1M")}"
        : "";
    final searchParam = opts.query == null
        ? ""
        : "&q=${Uri.encodeQueryComponent(opts.query!)}";
    final ratiosParam = switch (opts.orientation) {
      "portrait" => "&ratios=portrait",
      "landscape" => "&ratios=landscape",
      "squarish" => "&ratios=1x1",
      _ => "",
    };
    final atLeastParam = opts.minWidth != null && opts.minHeight != null
        ? "&atleast=${opts.minWidth}x${opts.minHeight}"
        : "";

    final res = await http
        .get(
          Uri.parse(
            "https://wallhaven.cc/api/v1/search?"
            "page=${opts.page}"
            "$rangeParam"
            "$categoryParam"
            "$purityParam"
            "$ratiosParam"
            "$atLeastParam"
            "&sorting=$sorting"
            "$searchParam"
            "&order=desc",
          ),
        )
        .timeout(_timeout);
    if (res.statusCode != 200) throw SourceException("wallhaven", res.statusCode);

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
      // Only search takes an orientation, and calls square "squarish" too.
      if (isSearch && opts.orientation != null)
        "orientation=${opts.orientation}",
      "page=${opts.page}",
      "per_page=${opts.perPage}",
    ];

    final res = await http
        .get(
          Uri.parse("$url?${params.join("&")}"),
          headers: {"Authorization": "Client-ID $apiKey"},
        )
        .timeout(_timeout);
    if (res.statusCode != 200) throw SourceException("unsplash", res.statusCode);

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
      if (opts.minWidth != null) "min_width=${opts.minWidth}",
      if (opts.minHeight != null) "min_height=${opts.minHeight}",
      if (opts.bestOf) "editors_choice=true",
      "page=${opts.page}",
      // Pixabay rejects per_page below 3.
      "per_page=${opts.perPage.clamp(3, 200)}",
    ];

    final res = await http
        .get(Uri.parse("https://pixabay.com/api/?${params.join("&")}"))
        .timeout(_timeout);
    if (res.statusCode != 200) throw SourceException("pixabay", res.statusCode);

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
      if (isSearch && opts.orientation != null)
        "orientation=${opts.orientation == "squarish" ? "square" : opts.orientation}",
    ];

    final res = await http
        .get(
          Uri.parse("https://api.pexels.com/$endpoint?${params.join("&")}"),
          headers: {"Authorization": apiKey},
        )
        .timeout(_timeout);

    if (res.statusCode != 200) throw SourceException("pexels", res.statusCode);

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

  /// Every source Discover can search, in display order.
  static const searchableSources = ["wallhaven", "unsplash", "pixabay", "pexels"];

  static Future<List<Wallpaper>> fetchSource(String source, FetchOptions opts) {
    return switch (source) {
      "wallhaven" => fetchWallhaven(opts),
      "unsplash" => fetchUnsplash(opts),
      "pixabay" => fetchPixabay(opts),
      "pexels" => fetchPexels(opts),
      "lorempicsum" => fetchLoremPicsum(opts),
      _ => Future.value(<Wallpaper>[]),
    };
  }

  /// Fetches every source in parallel; a failing source contributes nothing.
  static Future<List<Wallpaper>> fetchAll({
    required List<String> sources,
    required FetchOptions Function(String source) optionsFor,
  }) async {
    final results = await fetchEach(sources: sources, optionsFor: optionsFor);
    return [for (final list in results.values) ...?list];
  }

  /// Like [fetchAll], but keeps each source's results apart, in source order.
  /// A source that failed maps to null.
  static Future<Map<String, List<Wallpaper>?>> fetchEach({
    required List<String> sources,
    required FetchOptions Function(String source) optionsFor,
  }) async {
    final futures = [
      for (final source in sources)
        fetchSource(source, optionsFor(source))
            .then<List<Wallpaper>?>((list) => list)
            .catchError((Object e) {
          debugPrint("$source failed: $e");
          return null;
        }),
    ];
    final results = await Future.wait(futures);
    return {for (var i = 0; i < sources.length; i++) sources[i]: results[i]};
  }

  /// Merges per-source lists round-robin so every source is represented near
  /// the top while each keeps its own ranking. Drops duplicate urls.
  static List<Wallpaper> interleave(Iterable<List<Wallpaper>> lists) {
    final iterators = [for (final l in lists) l.iterator];
    final seen = <String>{};
    final out = <Wallpaper>[];
    var active = true;
    while (active) {
      active = false;
      for (final it in iterators) {
        if (it.moveNext()) {
          active = true;
          if (seen.add(it.current.url)) out.add(it.current);
        }
      }
    }
    return out;
  }

  /// Whether any source has results for [tag]: true if one does, false if
  /// every source that answered had none, and null when no source could be
  /// reached (offline, rate limited), so a tag isn't flagged by mistake.
  static Future<bool?> validateTag(String tag) async {
    final sources = ["wallhaven", "unsplash"];
    final pixabayKey = await UserSharedPrefs.getPixabayApiKey();
    if (pixabayKey != null && pixabayKey.isNotEmpty) sources.add("pixabay");
    final pexelsKey = await UserSharedPrefs.getPexelsApiKey();
    if (pexelsKey != null && pexelsKey.isNotEmpty) sources.add("pexels");

    final results = await fetchEach(
      sources: sources,
      optionsFor: (source) => FetchOptions(
        query: tag,
        perPage: 3,
        sorting: "relevance",
      ),
    );
    final answered = results.values.whereType<List<Wallpaper>>();
    if (answered.any((list) => list.isNotEmpty)) return true;
    return answered.isEmpty ? null : false;
  }

  /// Wallhaven wants "1d", "1w", "1y" but "1M", "3M", "6M" for months.
  static String _wallhavenRange(String range) {
    final lower = range.toLowerCase();
    return lower.endsWith("m") ? "${lower.substring(0, lower.length - 1)}M" : lower;
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
