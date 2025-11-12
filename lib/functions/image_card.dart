import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:wallify/core/performance_config.dart';
import 'package:wallify/model/wallpaper_model.dart';
import 'package:wallify/screens/wallpaper_preview.dart';

class ImageTile extends StatefulWidget {
  final Wallpaper wallpaper;
  final bool isFav;
  final VoidCallback onFavToggle;

  const ImageTile({super.key, required this.wallpaper, required this.isFav, required this.onFavToggle});

  @override
  State<ImageTile> createState() => _ImageTileState();
}

class _ImageTileState extends State<ImageTile> {

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        children: [
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      WallpaperPreviewPage(wallpaper: widget.wallpaper, isFavorite: widget.isFav),
                ),
              );
            },
            child: CachedNetworkImage(
              imageUrl: widget.wallpaper.url,
              fit: BoxFit.cover,
              maxWidthDiskCache: PerformanceConfig.thumbnailWidth * 2,
              maxHeightDiskCache: PerformanceConfig.thumbnailHeight * 2,
              fadeInDuration: PerformanceConfig.fadeInDuration,
              placeholder: (context, url) => Container(
                height: 200,
                color: colorScheme.surface.withValues(alpha: 0.3),
                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              errorWidget: (context, url, error) => Container(
                height: 100,
                color: colorScheme.surface.withValues(alpha: 0.2),
                child: Icon(Icons.broken_image, color: colorScheme.onSurface.withValues(alpha: 0.5)),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.surface.withValues(alpha: 0.6),
              ),
              icon: Icon(
                widget.isFav ? Icons.favorite : Icons.favorite_border,
                color: widget.isFav ? colorScheme.secondary : colorScheme.onSurface,
              ),
              onPressed: widget.onFavToggle,
            ),
          ),
        ],
      ),
    );
  }
}
