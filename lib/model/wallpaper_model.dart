class Wallpaper {
  final String id;
  final String url;
  final DateTime? timestamp;

  Wallpaper({required this.id, required this.url, this.timestamp});

  Map<String, dynamic> toJson() => {
        "id": id,
        "url": url,
        "timestamp": timestamp?.toIso8601String(),
      };

  factory Wallpaper.fromJson(Map<String, dynamic> json) {
    // Some entries (e.g. wallpapers fetched natively in the background) may not
    // carry an "id", so fall back to the url to keep a stable, unique key.
    return Wallpaper(
      id: (json["id"] ?? json["url"] ?? "").toString(),
      url: (json["url"] ?? "").toString(),
      timestamp: json["timestamp"] != null ? DateTime.parse(json["timestamp"]) : null,
    );
  }
}
