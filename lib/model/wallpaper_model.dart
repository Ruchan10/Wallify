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
