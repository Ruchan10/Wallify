import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:wallify/core/snackbar.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/functions/wallpaper_info_sheet.dart';
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
    _loadInfo();
  }

  Map<String, dynamic>? _info;


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

      showSnackBar(context: context, message: "Wallpaper set successfully");
    } catch (e) {
      showSnackBar(context: context, message: "Error: $e");
    }
  }

  Future<void> _loadInfo() async {
  debugPrint("URL:- ${widget.imageUrl} ===============================");

  Map<String, dynamic>? data;

  if (widget.imageUrl.contains("wallhaven")) {
    data = await fetchWallhavenInfo(widget.imageUrl);
  } else if (widget.imageUrl.contains("pixabay.com")) {
    data = await fetchPixabayInfo(widget.imageUrl);
  } else if (widget.imageUrl.contains("unsplash.com")) {
    data = await fetchUnsplashInfo(widget.imageUrl);
  }

  setState(() => _info = data);
  debugPrint(jsonEncode(_info), wrapWidth: 1024);
}

Future<Map<String, dynamic>?> fetchWallhavenInfo(String url) async {
  try {
    final regex = RegExp(r'wallhaven-([a-z0-9]+)\.');
    final match = regex.firstMatch(url);
    if (match == null) return null;

    final id = match.group(1);
    final res = await http.get(
      Uri.parse("https://wallhaven.cc/api/v1/w/$id"),
    );
    debugPrint("${res.body} =================");

    if (res.statusCode == 200) {
      final json = jsonDecode(res.body)["data"];
      return {
        "source": "Wallhaven",
        "id": json["id"],
        "uploader": json["uploader"]["username"],
        "resolution": json["resolution"],
        "category": json["category"],
        "url": json["url"],
      };
    }
  } catch (e) {
    debugPrint("Error fetching Wallhaven info: $e");
  }
  return null;
}

Future<Map<String, dynamic>?> fetchPixabayInfo(String url) async {
  try {
    const apiKey = "52028006-a7e910370a5d0158c371bb06a";
    final uri = Uri.parse(url);
    final fileName = uri.pathSegments.last;

    final res = await http.get(
      Uri.parse("https://pixabay.com/api/?key=$apiKey&q=$fileName"),
    );

    debugPrint("${res.body} =================");
    if (res.statusCode == 200) {
      final hits = jsonDecode(res.body)["hits"];
      if (hits.isNotEmpty) {
        final img = hits[0];
        return {
          "source": "Pixabay",
          "id": img["id"].toString(),
          "uploader": img["user"],
          "tags": img["tags"],
          "resolution": "${img["imageWidth"]}x${img["imageHeight"]}",
          "url": img["pageURL"],
        };
      }
    }
  } catch (e) {
    debugPrint("Error fetching Pixabay info: $e");
  }
  return null;
}

Future<Map<String, dynamic>?> fetchUnsplashInfo(String url) async {
  try {
    const accessKey = "yTBcYNAtnRHbrYMn2p4DrBiqzOAfdH9nyexQQtJWO-E";
    final uri = Uri.parse(url);

    final regex = RegExp(r'photo-([a-zA-Z0-9_-]+)');
    final match = regex.firstMatch(uri.toString());

    if (match == null) return null;
    final photoId = match.group(1);

    final res = await http.get(
      Uri.parse("https://api.unsplash.com/photos/$photoId?client_id=$accessKey"),
    );

    if (res.statusCode == 200) {
      final json = jsonDecode(res.body);
      return {
        "source": "Unsplash",
        "id": json["id"],
        "uploader": json["user"]["name"],
        "username": json["user"]["username"],
        "resolution": "${json["width"]}x${json["height"]}",
        "likes": json["likes"],
        "url": json["links"]["html"],
      };
    }
  } catch (e) {
    debugPrint("Error fetching Unsplash info: $e");
  }
  return null;
}


  void _showInfoSheet() {
    if (_info == null) {
      showSnackBar(context: context, message: "No info available", color:Colors.red);
      return;
    }

showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(16),
      child: WallpaperInfoSheet(info: _info!),
    );
  },
);

  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
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
              enableRotation: true,
            ),
          ),
        
        

          Positioned(
            bottom: 24,
            right: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  heroTag: "info_btn",
                  backgroundColor: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.8),
                  foregroundColor: colorScheme.onSurface,
                  onPressed: _showInfoSheet,
                  child: Icon(
                    Icons.info,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: "fav_btn",
                  backgroundColor: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.8),
                  foregroundColor: colorScheme.onSurface,
                  onPressed: () {
                    setState(() => _isFavorite = !_isFavorite);
                    if (_isFavorite) {
                      UserSharedPrefs.removeFavWallpaper(widget.imageUrl);
                    } else {
                      UserSharedPrefs.saveFavWallpaper(widget.imageUrl);
                    }
                  },
                  child: Icon(
                    _isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: _isFavorite
                        ? colorScheme.secondary
                        : colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),

                FloatingActionButton(
                  heroTag: "set_wallpaper_btn",
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  onPressed: () => _showSetWallpaperOptions(context),
                  child: const Icon(Icons.wallpaper),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
