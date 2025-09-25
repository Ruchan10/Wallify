class Wallpaper {
  final String id;
  final String url;

  Wallpaper({required this.id, required this.url});

  Map<String, dynamic> toJson() => {
        "id": id,
        "url": url,
      };

  factory Wallpaper.fromJson(Map<String, dynamic> json) {
    return Wallpaper(
      id: json["id"],
      url: json["url"],
    );
  }
}
