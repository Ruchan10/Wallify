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
    // Normalize uploader
    final uploaderData = info["uploader"];
    String uploaderName = "Unknown";
    String uploaderAvatar =
        "https://wallhaven.cc/images/user/avatar/32/default-avatar.jpg";

    if (uploaderData is Map) {
      uploaderName = uploaderData["username"] ?? uploaderName;
      uploaderAvatar = uploaderData["avatar"]?["32px"] ?? uploaderAvatar;
    } else if (uploaderData is String) {
      uploaderName = uploaderData;
    }

    final tags = (info["tags"] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final colors = (info["colors"] as List?)?.cast<String>() ?? [];

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
                  CircleAvatar(backgroundImage: NetworkImage(uploaderAvatar)),
                  const SizedBox(width: 8),
                  Text(uploaderName,
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  Text(info["created_at"]?.toString().split(" ").first ?? ""),
                ],
              ),

              const SizedBox(height: 16),

              // 🔹 Stats
              Wrap(
                spacing: 12,
                children: [
                  if (info["views"] != null)
                    Chip(label: Text("👁 ${info["views"]} views")),
                  if (info["favorites"] != null)
                    Chip(label: Text("❤️ ${info["favorites"]} favs")),
                  if (info["resolution"] != null)
                    Chip(label: Text("📐 ${info["resolution"]}")),
                  if (info["file_size"] != null)
                    Chip(
                      label: Text("⚖ ${_formatFileSize(info["file_size"])}"),
                    ),
                ],
              ),

              const SizedBox(height: 16),

              // 🔹 Category + Purity
              Wrap(
                spacing: 8,
                children: [
                  if (info["category"] != null)
                    Chip(label: Text("Category: ${info["category"]}")),
                  if (info["purity"] != null)
                    Chip(label: Text("Purity: ${info["purity"]}")),
                ],
              ),

              const SizedBox(height: 16),

              // 🔹 Source
              if (info["source"] != null &&
                  info["source"].toString().isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.link),
                  title: const Text("Source"),
                  subtitle: Text(info["source"]),
                  onTap: () {
                    // TODO: use url_launcher to open info["url"]
                  },
                ),

              const SizedBox(height: 16),

              // 🔹 Tags
              if (tags.isNotEmpty) ...[
                Text("Tags", style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: -6,
                  children: tags
                      .map(
                        (tag) => Chip(
                          label: Text(tag["name"] ?? ""),
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.1),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),
              ],

              // 🔹 Colors
              if (colors.isNotEmpty) ...[
                Text("Colors", style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  children: colors
                      .map(
                        (c) => Container(
                          width: 30,
                          height: 30,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: Color(int.parse(c.replaceFirst("#", "0xff"))),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
