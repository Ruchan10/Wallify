class Wallpaper {
  final String id;
  final String url;
  final DateTime? timestamp;
  final int? width;
  final int? height;
  final double? ratio;

  Wallpaper({
    required this.id,
    required this.url,
    this.timestamp,
    this.width,
    this.height,
    this.ratio,
  });

  /// Width / height of the original image, or null when unknown (e.g. older
  /// saved entries that were stored without dimensions).
  double? get aspectRatio {
    if (width != null && height != null && width! > 0 && height! > 0) {
      return width! / height!;
    }
    if (ratio != null && ratio! > 0) return ratio;
    return null;
  }

  static const _thumbWidth = 800;

  /// A smaller version of [url] for grids, so the disk cache doesn't keep
  /// multi-MB originals. Derived from the url so saved entries work too;
  /// unknown hosts fall back to [url].
  String get thumbnailUrl {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;

    switch (uri.host) {
      case 'w.wallhaven.cc':
        // /full/ab/wallhaven-abcdef.png -> th.wallhaven.cc/<size>/ab/abcdef.jpg
        // "lg" is cropped to landscape, so only use it for landscape images;
        // "orig" keeps the original aspect ratio but is ~300px on its long side.
        final m = RegExp(r'/full/(\w+)/wallhaven-(\w+)\.\w+$').firstMatch(uri.path);
        if (m == null) return url;
        final ratio = aspectRatio;
        final size = ratio != null && ratio > 1 ? 'lg' : 'orig';
        return 'https://th.wallhaven.cc/$size/${m[1]}/${m[2]}.jpg';
      case 'images.pexels.com':
        return uri.replace(queryParameters: {
          ...uri.queryParameters,
          'auto': 'compress',
          'cs': 'tinysrgb',
          'w': '$_thumbWidth',
        }).toString();
      case 'images.unsplash.com':
        return uri.replace(queryParameters: {
          ...uri.queryParameters,
          'w': '$_thumbWidth',
        }).toString();
      case 'picsum.photos':
        // /id/10/2500/1667 -> /id/10/800/533
        final m = RegExp(r'^/id/(\w+)/(\d+)/(\d+)').firstMatch(uri.path);
        final w = int.tryParse(m?[2] ?? '') ?? 0;
        final h = int.tryParse(m?[3] ?? '') ?? 0;
        if (m == null || w <= 0 || h <= 0) return url;
        return 'https://picsum.photos/id/${m[1]}/$_thumbWidth/${(h * _thumbWidth / w).round()}';
    }
    return url;
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "url": url,
        "timestamp": timestamp?.toIso8601String(),
        if (width != null) "width": width,
        if (height != null) "height": height,
        if (ratio != null) "ratio": ratio,
      };

  factory Wallpaper.fromJson(Map<String, dynamic> json) {
    // Some entries (e.g. wallpapers fetched natively in the background) may not
    // carry an "id", so fall back to the url to keep a stable, unique key.
    return Wallpaper(
      id: (json["id"] ?? json["url"] ?? "").toString(),
      url: (json["url"] ?? "").toString(),
      timestamp: json["timestamp"] != null ? DateTime.parse(json["timestamp"]) : null,
      width: parseNum(json["width"])?.toInt(),
      height: parseNum(json["height"])?.toInt(),
      ratio: parseNum(json["ratio"])?.toDouble(),
    );
  }

  /// Accepts ints, doubles and numeric strings (APIs aren't consistent).
  static num? parseNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }
}
