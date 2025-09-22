import 'package:flutter/material.dart';

class WallpaperInfoSheet extends StatelessWidget {
  final Map<String, dynamic> info;

  const WallpaperInfoSheet({super.key, required this.info});

  String _formatFileSize(int bytes) {
    const units = ["B", "KB", "MB", "GB"];
    int i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return "${size.toStringAsFixed(2)} ${units[i]}";
  }

  @override
  Widget build(BuildContext context) {
    final uploader = info["uploader"] ?? {};
    final tags = List<Map<String, dynamic>>.from(info["tags"] ?? []);
    final colors = List<String>.from(info["colors"] ?? []);

    return DraggableScrollableSheet(
   expand: false,
  initialChildSize: 0.5,
  minChildSize: 0.2,
  maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  height: 4,
                  width: 40,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          
              // 🔹 Uploader
              Row(
                children: [
                  CircleAvatar(
                    backgroundImage: NetworkImage(
                      uploader["avatar"]?["32px"] ??
                          "https://wallhaven.cc/images/user/avatar/32/default-avatar.jpg",
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    uploader["username"] ?? "Unknown",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  Text(info["created_at"]?.split(" ")?.first ?? ""),
                ],
              ),
          
              const SizedBox(height: 16),
          
              // 🔹 Stats
              Wrap(
                spacing: 12,
                children: [
                  Chip(label: Text("👁 ${info["views"]} views")),
                  Chip(label: Text("❤️ ${info["favorites"]} favs")),
                  Chip(label: Text("📐 ${info["resolution"]}")),
                  Chip(label: Text("⚖ ${_formatFileSize(info["file_size"] ?? 0)}")),
                ],
              ),
          
              const SizedBox(height: 16),
          
              // 🔹 Category + Purity
              Wrap(
                spacing: 8,
                children: [
                  Chip(label: Text("Category: ${info["category"]}")),
                  Chip(label: Text("Purity: ${info["purity"]}")),
                ],
              ),
          
              const SizedBox(height: 16),
          
              // 🔹 Source
              if (info["source"] != null && info["source"].toString().isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.link),
                  title: Text("Source"),
                  subtitle: Text(info["source"]),
                  onTap: () {
                    // open url with url_launcher
                  },
                ),
          
              const SizedBox(height: 16),
          
              // 🔹 Tags
              Text("Tags", style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: -6,
                children: tags
                    .map((tag) => Chip(
                          label: Text(tag["name"]),
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.1),
                        ))
                    .toList(),
              ),
          
              const SizedBox(height: 16),
          
              // 🔹 Colors
              Text("Colors", style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: colors
                    .map((c) => Container(
                          width: 30,
                          height: 30,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: Color(
                              int.parse(c.replaceFirst("#", "0xff")),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}
