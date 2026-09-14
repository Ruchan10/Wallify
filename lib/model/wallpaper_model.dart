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
      width: json["width"] as int?,
      height: json["height"] as int?,
      ratio: json["ratio"] as double?,
    );
  }
}
