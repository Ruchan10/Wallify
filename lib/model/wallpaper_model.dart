class Wallpaper {
  final String id;
  final String url;
  final DateTime timestamp;

  Wallpaper({required this.id, required this.url, required this.timestamp});

  Map<String, dynamic> toJson() => {
        "id": id,
        "url": url,
        "timestamp": timestamp.toIso8601String(),
      };

  factory Wallpaper.fromJson(Map<String, dynamic> json) {
    return Wallpaper(
      id: json["id"],
      url: json["url"],
      timestamp: DateTime.parse(json["timestamp"]),
    );
  }
}
