import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:wallify/screens/wallpaper_preview.dart';

class ImageTile extends StatefulWidget {
  final String img;
  final bool isFav;
  final VoidCallback onFavToggle;

  const ImageTile({super.key, required this.img, required this.isFav, required this.onFavToggle});

  @override
  State<ImageTile> createState() => _ImageTileState();
}

class _ImageTileState extends State<ImageTile> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); 
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
                      WallpaperPreviewPage(imageUrl: widget.img, isFavorite: widget.isFav),
                ),
              );
            },
            child: CachedNetworkImage(
              imageUrl: widget.img,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                height: 100,
                color: colorScheme.surface.withValues(alpha: 0.3),
                child: const Center(child: CircularProgressIndicator()),
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
