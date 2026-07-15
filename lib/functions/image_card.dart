import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:wallify/core/performance_config.dart';
import 'package:wallify/functions/shimmer_widget.dart';
import 'package:wallify/model/wallpaper_model.dart';
import 'package:wallify/screens/wallpaper_preview.dart';

class ImageTile extends StatefulWidget {
  final Wallpaper wallpaper;
  final bool isFav;
  final VoidCallback onFavToggle;
  final List<Wallpaper> allWallpapers;
  final int index;

  const ImageTile({
    super.key,
    required this.wallpaper,
    required this.isFav,
    required this.onFavToggle,
    required this.allWallpapers,
    required this.index,
  });

  @override
  State<ImageTile> createState() => _ImageTileState();
}

class _ImageTileState extends State<ImageTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          GestureDetector(
            onTapDown: (_) {
              _animController.forward();
              _isPressed = true;
            },
            onTapUp: (_) {
              _animController.reverse();
              _isPressed = false;
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      FadeTransition(
                        opacity: animation,
                        child: WallpaperPreviewPage(
                          wallpapers: widget.allWallpapers,
                          initialIndex: widget.index,
                          isFavorite: widget.isFav,
                        ),
                      ),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                    return FadeTransition(
                      opacity: animation,
                      child: child,
                    );
                  },
                  transitionDuration:
                      const Duration(milliseconds: 300),
                ),
              );
            },
            onTapCancel: () {
              _animController.reverse();
              _isPressed = false;
            },
            child: Hero(
              tag: 'wallpaper_${widget.wallpaper.url}',
              child: AnimatedBuilder(
                animation: _scaleAnim,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _scaleAnim.value,
                    child: child,
                  );
                },
                child: CachedNetworkImage(
                  imageUrl: widget.wallpaper.url,
                  fit: BoxFit.cover,
                  memCacheWidth: PerformanceConfig.thumbnailWidth,
                  memCacheHeight: PerformanceConfig.thumbnailHeight,
                  maxWidthDiskCache: PerformanceConfig.thumbnailWidth * 2,
                  maxHeightDiskCache: PerformanceConfig.thumbnailHeight * 2,
                  fadeInDuration: PerformanceConfig.fadeInDuration,
                  placeholder: (context, url) => ShimmerLoading(
                    height: 200,
                    borderRadius: 12,
                  ),
                  errorWidget: (context, url, error) => Container(
                    height: 100,
                    color: colorScheme.surface.withValues(alpha: 0.2),
                    child: Icon(
                      Icons.broken_image,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: GestureDetector(
              onTap: () {
                widget.onFavToggle();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    widget.isFav
                        ? Icons.favorite
                        : Icons.favorite_border,
                    key: ValueKey(widget.isFav),
                    color: widget.isFav
                        ? colorScheme.secondary
                        : colorScheme.onSurface,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
