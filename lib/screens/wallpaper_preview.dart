import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:wallify/functions/wallpaper_manager.dart';
import 'package:wallpaper_manager_flutter/wallpaper_manager_flutter.dart';
// import your own WallpaperManager if you wrapped it

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
                leading: const Icon(Icons.home),
                title: const Text("Set as Home Screen"),
                onTap: () async {
                  Navigator.pop(context);
                  await _setWallpaper(WallpaperManagerFlutter.homeScreen);
                },
              ),
              ListTile(
                leading: const Icon(Icons.lock),
                title: const Text("Set as Lock Screen"),
                onTap: () async {
                  Navigator.pop(context);
                  await _setWallpaper(WallpaperManagerFlutter.lockScreen);
                },
              ),
              ListTile(
                leading: const Icon(Icons.phone_android),
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
        SnackBar(content: Text("Wallpaper set successfully!")),
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
          /// Fullscreen Image
          Positioned.fill(
            child: InteractiveViewer(
              child: 
               CachedNetworkImage(
  imageUrl: widget.imageUrl,
  fit: BoxFit.cover,
  placeholder: (context, url) => Container(
    height: 200,
    color: Colors.grey[200],
    child: const Center(
      child: CircularProgressIndicator(),
    ),
  ),
  errorWidget: (context, url, error) => Container(
    height: 200,
    color: Colors.grey[200],
    child: const Icon(Icons.broken_image, color: Colors.grey),
  ),
),
            ),
          ),

          /// Buttons (bottom right)
          Positioned(
            bottom: 24,
            right: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                /// Love button
                FloatingActionButton(
                  heroTag: "fav_btn",
                  mini: true,
                  backgroundColor: Colors.black54,
                  onPressed: () {
                    setState(() => _isFavorite = !_isFavorite);
                    // TODO: Save to favorites in shared prefs/db
                  },
                  child: Icon(
                    _isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: _isFavorite
                        ? colorScheme.secondary
                        : colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(height: 12),

                /// Set Wallpaper button
                FloatingActionButton.extended(
                  heroTag: "set_wallpaper_btn",
                  backgroundColor: colorScheme.primary,
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
