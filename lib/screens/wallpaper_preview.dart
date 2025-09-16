import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/functions/wallpaper_manager.dart';
import 'package:wallpaper_manager_flutter/wallpaper_manager_flutter.dart';

class WallpaperPreviewPage extends StatefulWidget {
  final String imageUrl;
  final bool isFavorite;

  const WallpaperPreviewPage({
    super.key,
    required this.imageUrl,
    this.isFavorite = false,
  });

  @override
  State<WallpaperPreviewPage> createState() => _WallpaperPreviewPageState();
}

class _WallpaperPreviewPageState extends State<WallpaperPreviewPage> {
  late bool _isFavorite;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.isFavorite;
  }

  void _showSetWallpaperOptions(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.home, color: colorScheme.primary), 
                title: const Text("Set as Home Screen"),
                onTap: () async {
                  Navigator.pop(context);
                  await _setWallpaper(WallpaperManagerFlutter.homeScreen);
                },
              ),
              ListTile(
                leading: Icon(Icons.lock, color: colorScheme.primary), 
                title: const Text("Set as Lock Screen"),
                onTap: () async {
                  Navigator.pop(context);
                  await _setWallpaper(WallpaperManagerFlutter.lockScreen);
                },
              ),
              ListTile(
                leading: Icon(Icons.phone_android, color: colorScheme.primary), 
                title: const Text("Set as Both"),
                onTap: () async {
                  Navigator.pop(context);
                  await _setWallpaper(WallpaperManagerFlutter.bothScreens);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _setWallpaper(int location) async {
    try {
      await WallpaperManager.fetchAndSetWallpaper(
        wallpaperLocation: location,
        imageUrl: widget.imageUrl,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Wallpaper set successfully!")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          /// Fullscreen interactive wallpaper preview
          Positioned.fill(
            child: PhotoView(
              imageProvider: CachedNetworkImageProvider(widget.imageUrl),
              minScale: PhotoViewComputedScale.contained, 
              maxScale: PhotoViewComputedScale.covered * 4, 
              initialScale: PhotoViewComputedScale.contained,
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              enableRotation: false,
            ),
          ),

          /// Floating buttons (bottom right)
          Positioned(
            bottom: 24,
            right: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                /// Favorite toggle
                FloatingActionButton.extended(
                  heroTag: "fav_btn",
                  backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
                  foregroundColor: colorScheme.onSurface,
                  onPressed: () {
                    setState(() => _isFavorite = !_isFavorite);
                    if (_isFavorite) {
                      UserSharedPrefs.removeFavWallpaper(widget.imageUrl);
                    } else {
                      UserSharedPrefs.saveFavWallpaper(widget.imageUrl);
                    }
                  },
                  label: Icon(
                    _isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: _isFavorite ? colorScheme.secondary : colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),

                /// Set wallpaper button
                FloatingActionButton.extended(
                  heroTag: "set_wallpaper_btn",
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  onPressed: () => _showSetWallpaperOptions(context),
                  icon: const Icon(Icons.wallpaper),
                  label: const Text("Set"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
