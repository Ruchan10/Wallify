import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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
  
  String _formatNumber(int number) {
    if (number >= 1000000) {
      return "${(number / 1000000).toStringAsFixed(1)}M";
    } else if (number >= 1000) {
      return "${(number / 1000).toStringAsFixed(1)}K";
    }
    return number.toString();
  }
  
  String _formatDate(String? dateStr) {
    if (dateStr == null) return "";
    try {
      final date = DateTime.parse(dateStr);
      return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
    } catch (e) {
      return dateStr.split(" ").first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    
    // Normalize uploader
    final uploaderData = info["uploader"];
    String uploaderName = "Unknown";
    String uploaderAvatar =
        "https://wallhaven.cc/images/user/avatar/32/default-avatar.jpg";
    String? uploaderBio;
    String? uploaderLocation;

    if (uploaderData is Map) {
      uploaderName = uploaderData["name"] ?? uploaderData["username"] ?? uploaderName;
      uploaderAvatar = uploaderData["avatar"]?["32px"] ?? 
                       uploaderData["avatar"]?["64px"] ?? 
                       info["uploader_avatar"] ?? 
                       uploaderAvatar;
      uploaderBio = uploaderData["bio"];
      uploaderLocation = uploaderData["location"];
    } else if (uploaderData is String) {
      uploaderName = uploaderData;
      if (info["uploader_avatar"] != null) {
        uploaderAvatar = info["uploader_avatar"];
      }
    }

    final tags = (info["tags"] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final colors = (info["colors"] as List?)?.cast<String>() ?? [];
    final exif = info["exif"] as Map<String, dynamic>?;
    final location = info["location"] as Map<String, dynamic>?;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: scrollController,
            children: [
              // Drag handle
              Center(
                child: Container(
                  height: 4,
                  width: 40,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // 🔹 Source Badge
              if (info["source"] != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    avatar: Icon(
                      info["source"] == "Wallhaven" ? Icons.image :
                      info["source"] == "Unsplash" ? Icons.camera_alt :
                      Icons.photo_library,
                      size: 18,
                    ),
                    label: Text(info["source"]),
                    backgroundColor: colorScheme.primaryContainer,
                  ),
                ),

              const SizedBox(height: 12),

              // 🔹 Uploader Section
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundImage: NetworkImage(uploaderAvatar),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(uploaderName, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        if (uploaderLocation != null)
                          Text("📍 $uploaderLocation", style: textTheme.bodySmall),
                        if (info["created_at"] != null)
                          Text("📅 ${_formatDate(info["created_at"])}", style: textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),

              if (uploaderBio != null && uploaderBio.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(uploaderBio, style: textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
              ],

              if (info["description"] != null && info["description"].toString().isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(info["description"], style: textTheme.bodyMedium),
                ),
              ],

              const SizedBox(height: 16),
              Divider(color: colorScheme.outline.withValues(alpha: 0.3)),
              const SizedBox(height: 16),

              // 🔹 Image Details
              Text("Image Details", style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (info["resolution"] != null)
                    _buildInfoChip("📐", info["resolution"], colorScheme),
                  if (info["file_size"] != null)
                    _buildInfoChip("⚖️", _formatFileSize(info["file_size"]), colorScheme),
                  if (info["file_type"] != null)
                    _buildInfoChip("📄", info["file_type"].toString().toUpperCase(), colorScheme),
                  if (info["ratio"] != null)
                    _buildInfoChip("📏", info["ratio"], colorScheme),
                  if (info["type"] != null)
                    _buildInfoChip("🖼️", info["type"], colorScheme),
                ],
              ),

              const SizedBox(height: 16),

              // 🔹 Engagement Stats
              if (info["views"] != null || info["likes"] != null || info["favorites"] != null || 
                  info["downloads"] != null || info["comments"] != null) ...[
                Text("Engagement", style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (info["views"] != null)
                      _buildStatChip("👁️", _formatNumber(info["views"]), "Views", colorScheme),
                    if (info["likes"] != null)
                      _buildStatChip("❤️", _formatNumber(info["likes"]), "Likes", colorScheme),
                    if (info["favorites"] != null)
                      _buildStatChip("⭐", _formatNumber(info["favorites"]), "Favs", colorScheme),
                    if (info["downloads"] != null)
                      _buildStatChip("⬇️", _formatNumber(info["downloads"]), "Downloads", colorScheme),
                    if (info["comments"] != null)
                      _buildStatChip("💬", _formatNumber(info["comments"]), "Comments", colorScheme),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // 🔹 Category & Purity
              if (info["category"] != null || info["purity"] != null) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    if (info["category"] != null)
                      Chip(
                        label: Text("Category: ${info["category"]}"),
                        backgroundColor: colorScheme.secondaryContainer,
                      ),
                    if (info["purity"] != null)
                      Chip(
                        label: Text("Purity: ${info["purity"]}"),
                        backgroundColor: colorScheme.tertiaryContainer,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // 🔹 EXIF Data (Camera Info)
              if (exif != null && exif.isNotEmpty) ...[
                Text("Camera Info", style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (exif["make"] != null)
                        _buildExifRow("Camera", "${exif["make"]} ${exif["model"] ?? ""}", textTheme),
                      if (exif["focal_length"] != null)
                        _buildExifRow("Focal Length", exif["focal_length"], textTheme),
                      if (exif["aperture"] != null)
                        _buildExifRow("Aperture", "f/${exif["aperture"]}", textTheme),
                      if (exif["exposure_time"] != null)
                        _buildExifRow("Shutter Speed", "${exif["exposure_time"]}s", textTheme),
                      if (exif["iso"] != null)
                        _buildExifRow("ISO", exif["iso"].toString(), textTheme),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 🔹 Location
              if (location != null && location["name"] != null) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.location_on, color: colorScheme.primary),
                  title: Text(location["name"] ?? ""),
                  subtitle: location["city"] != null || location["country"] != null
                      ? Text("${location["city"] ?? ""} ${location["country"] ?? ""}".trim())
                      : null,
                ),
                const SizedBox(height: 8),
              ],

              // 🔹 Tags
              if (tags.isNotEmpty) ...[
                Text("Tags", style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: tags
                      .map(
                        (tag) => Chip(
                          label: Text(tag["name"] ?? "", style: textTheme.bodySmall),
                          backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                          side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.3)),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),
              ],

              // 🔹 Colors
              if (colors.isNotEmpty) ...[
                Text("Color Palette", style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: colors.map((c) {
                    final colorValue = Color(int.parse(c.replaceFirst("#", "0xff")));
                    return GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: c));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Copied $c"), duration: const Duration(seconds: 1)),
                        );
                      },
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: colorValue,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3), width: 1),
                        ),
                        child: Center(
                          child: Text(
                            c.substring(1),
                            style: TextStyle(
                              color: colorValue.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],

              // 🔹 Links
              if (info["url"] != null) ...[
                ElevatedButton.icon(
                  onPressed: () async {
                    final url = Uri.parse(info["url"]);
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text("View on Source Website"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primaryContainer,
                    foregroundColor: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 8),
              ],

              if (info["short_url"] != null) ...[
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: info["short_url"]));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Short URL copied!"), duration: Duration(seconds: 1)),
                    );
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text("Copy Short URL"),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoChip(String icon, String text, ColorScheme colorScheme) {
    return Chip(
      avatar: Text(icon),
      label: Text(text, style: const TextStyle(fontSize: 12)),
      backgroundColor: colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }

  Widget _buildStatChip(String icon, String value, String label, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(icon, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 4),
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          Text(label, style: TextStyle(fontSize: 10, color: colorScheme.onSurface.withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  Widget _buildExifRow(String label, String value, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
          Text(value, style: textTheme.bodySmall),
        ],
      ),
    );
  }
}
