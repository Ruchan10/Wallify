import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:wallify/core/performance_config.dart';
import 'package:wallify/functions/shimmer_widget.dart';
import 'package:wallify/model/wallpaper_model.dart';
import 'package:wallify/screens/wallpaper_preview.dart';
import 'package:wallify/core/snackbar.dart';
import 'dart:async';

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

class _ImageTileState extends State<ImageTile> {
  bool _isPressed = false;

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text("Copy URL"),
              onTap: () {
                Navigator.pop(ctx);
                _copyUrl();
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text("Download"),
              onTap: () {
                Navigator.pop(ctx);
                _download();
              },
            ),
            ListTile(
              leading: Icon(widget.isFav ? Icons.favorite : Icons.favorite_border),
              title: Text(widget.isFav ? "Remove from Favorites" : "Add to Favorites"),
              onTap: () {
                Navigator.pop(ctx);
                widget.onFavToggle();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _copyUrl() {
    Clipboard.setData(ClipboardData(text: widget.wallpaper.url));
    if (context.mounted) {
      showSnackBar(context: context, message: "URL copied to clipboard");
    }
  }

  Future<void> _download() async {
    File? tempFile;
    try {
      final response = await http.get(Uri.parse(widget.wallpaper.url));
      if (response.statusCode != 200) {
        if (context.mounted) {
          showSnackBar(context: context, message: "Download failed", color: Colors.red);
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final fileName = "Wallify_${widget.wallpaper.id}.jpg";
      tempFile = File('${dir.path}/$fileName');
      await tempFile.writeAsBytes(response.bodyBytes);
      const channel = MethodChannel('wallpaper_channel');
      final result = await channel.invokeMethod<String>(
        'saveToDownloads',
        {
          'filePath': tempFile.path,
          'fileName': fileName,
          'subdirectory': 'Wallify',
        },
      );
      if (context.mounted) {
        showSnackBar(
          context: context,
          message: result != null
              ? "Saved to Downloads/Wallify/"
              : "Download failed",
          color: result != null ? Colors.green : Colors.red,
        );
      }
    } catch (e) {
      if (context.mounted) {
        showSnackBar(context: context, message: "Download failed: $e", color: Colors.red);
      }
    } finally {
      try { await tempFile?.delete(); } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          GestureDetector(
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) {
              setState(() => _isPressed = false);
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
            onTapCancel: () => setState(() => _isPressed = false),
            onLongPress: () => _showContextMenu(context),
            child: AnimatedScale(
              scale: _isPressed ? 0.95 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: Hero(
              tag: 'wallpaper_${widget.wallpaper.url}',
              child: CachedNetworkImage(
                  cacheManager: PerformanceConfig.cacheManager,
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
              behavior: HitTestBehavior.opaque,
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
                    size: 24,
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
