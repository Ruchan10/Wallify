import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:wallify/core/snackbar.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/functions/wallpaper_info_sheet.dart';
import 'package:wallify/model/wallpaper_model.dart';
import 'package:wallpaper_manager_flutter/wallpaper_manager_flutter.dart';

class WallpaperPreviewPage extends StatefulWidget {
  final Wallpaper wallpaper;
  final bool isFavorite;

  const WallpaperPreviewPage({
    super.key,
    required this.wallpaper,
    this.isFavorite = false,
  });

  @override
  State<WallpaperPreviewPage> createState() => _WallpaperPreviewPageState();
}

class _WallpaperPreviewPageState extends State<WallpaperPreviewPage> {
  late bool _isFavorite;
  bool _isCropMode = false;
  bool _isProcessing = false;
  int? _selectedLocation;
  File? _downloadedImage;
  final TransformationController _transformationController = TransformationController();
  final GlobalKey _imageKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.isFavorite;
    _loadInfo();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
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
                  await _enterCropMode(WallpaperManagerFlutter.homeScreen);
                },
              ),
              ListTile(
                leading: Icon(Icons.lock, color: colorScheme.primary),
                title: const Text("Set as Lock Screen"),
                onTap: () async {
                  Navigator.pop(context);
                  await _enterCropMode(WallpaperManagerFlutter.lockScreen);
                },
              ),
              ListTile(
                leading: Icon(Icons.phone_android, color: colorScheme.primary),
                title: const Text("Set as Both"),
                onTap: () async {
                  Navigator.pop(context);
                  await _enterCropMode(WallpaperManagerFlutter.bothScreens);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _enterCropMode(int location) async {
    setState(() {
      _selectedLocation = location;
      _isProcessing = true;
    });

    try {
      // Try to get cached image first
      final cacheManager = DefaultCacheManager();
      final fileInfo = await cacheManager.getFileFromCache(widget.wallpaper.url);
      
      File imageFile;
      
      if (fileInfo != null && fileInfo.file.existsSync()) {
        // Use cached image
        imageFile = fileInfo.file;
      } else {
        // Download if not cached
        final response = await http.get(Uri.parse(widget.wallpaper.url));
        final dir = await getTemporaryDirectory();
        imageFile = File("${dir.path}/wallpaper_${DateTime.now().millisecondsSinceEpoch}.jpg");
        await imageFile.writeAsBytes(response.bodyBytes);
      }

      setState(() {
        _downloadedImage = imageFile;
        _isCropMode = true;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        showSnackBar(context: context, message: "Error: $e", color: Colors.red);
      }
    }
  }

  void _exitCropMode() {
    setState(() {
      _isCropMode = false;
      _selectedLocation = null;
      _downloadedImage = null;
      _transformationController.value = Matrix4.identity();
    });
  }
    
  Future<void> _setWallpaper() async {
    if (_downloadedImage == null || _selectedLocation == null) return;

    setState(() => _isProcessing = true);

    try {
      // Get the current transformation matrix
      final matrix = _transformationController.value;
      
      // Get screen size
      final screenSize = MediaQuery.of(context).size;
      
      // Load and decode the original image
      final imageBytes = await _downloadedImage!.readAsBytes();
      final originalImage = img.decodeImage(imageBytes);
      
      if (originalImage == null) {
        throw Exception("Failed to decode image");
      }

      File croppedFile;
      
      if (matrix != Matrix4.identity()) {
        // Calculate the crop area based on transformation
        final imageWidth = originalImage.width.toDouble();
        final imageHeight = originalImage.height.toDouble();
        
        // Get scale from matrix
        final scale = matrix.getMaxScaleOnAxis();
        
        // Get translation
        final translation = matrix.getTranslation();
        
        // Calculate visible area in image coordinates
        final visibleWidth = screenSize.width / scale;
        final visibleHeight = screenSize.height / scale;
        
        final offsetX = (-translation.x / scale).clamp(0.0, imageWidth - visibleWidth);
        final offsetY = (-translation.y / scale).clamp(0.0, imageHeight - visibleHeight);
        
        // Crop the image
        final croppedImage = img.copyCrop(
          originalImage,
          x: offsetX.toInt(),
          y: offsetY.toInt(),
          width: visibleWidth.toInt().clamp(1, originalImage.width),
          height: visibleHeight.toInt().clamp(1, originalImage.height),
        );
        
        // Save cropped image
        final dir = await getTemporaryDirectory();
        croppedFile = File("${dir.path}/wallpaper_cropped_${DateTime.now().millisecondsSinceEpoch}.jpg");
        await croppedFile.writeAsBytes(img.encodeJpg(croppedImage, quality: 100));
      } else {
        // No transformation, use original file
        croppedFile = _downloadedImage!;
      }

      // Set the wallpaper
      debugPrint("Setting wallpaper - Path: ${croppedFile.path}");
      debugPrint("Setting wallpaper - Location: $_selectedLocation");
      debugPrint("Setting wallpaper - File exists: ${await croppedFile.exists()}");
      
      await WallpaperManagerFlutter().setWallpaper(
        croppedFile,
        _selectedLocation!,
      );

      if (mounted) {
        showSnackBar(
          context: context,
          message: "Wallpaper set successfully",
        );
        _exitCropMode();
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(
          context: context,
          message: "Error: $e",
          color: Colors.red,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  String _getLocationText() {
    if (_selectedLocation == null) return "";
    switch (_selectedLocation!) {
      case WallpaperManagerFlutter.homeScreen:
        return "Home Screen";
      case WallpaperManagerFlutter.lockScreen:
        return "Lock Screen";
      case WallpaperManagerFlutter.bothScreens:
        return "Both Screens";
      default:
        return "Wallpaper";
    }
  }


  Future<void> _loadInfo() async {
    debugPrint("URL:- ${widget.wallpaper.url} ===============================");

    Map<String, dynamic>? data;

    if (widget.wallpaper.url.contains("wallhaven")) {
      data = await fetchWallhavenInfo(widget.wallpaper.id);
    } else if (widget.wallpaper.url.contains("pixabay.com")) {
      data = await fetchPixabayInfo(widget.wallpaper.id);
    } else if (widget.wallpaper.url.contains("unsplash.com")) {
      data = await fetchUnsplashInfo(widget.wallpaper.id);
    }

    setState(() => _info = data);
    debugPrint(jsonEncode(_info), wrapWidth: 1024);
  }

Future<Map<String, dynamic>?> fetchWallhavenInfo(String id) async {
  try {
    final res = await http.get(Uri.parse("https://wallhaven.cc/api/v1/w/$id"));
    if (res.statusCode == 200) {
      final json = jsonDecode(res.body)["data"];
      debugPrint(jsonEncode(json), wrapWidth: 1024);
      return {
        "source": "Wallhaven",
        "id": json["id"],
        "uploader": json["uploader"],
        "resolution": json["resolution"],
        "dimension_x": json["dimension_x"],
        "dimension_y": json["dimension_y"],
        "file_size": json["file_size"],
        "file_type": json["file_type"],
        "category": json["category"],
        "purity": json["purity"],
        "views": json["views"],
        "favorites": json["favorites"],
        "created_at": json["created_at"],
        "colors": json["colors"],
        "tags": json["tags"],
        "url": json["url"],
        "short_url": json["short_url"],
        "ratio": json["ratio"],
      };
    }
  } catch (e) {
    debugPrint("Error fetching Wallhaven info: $e");
  }
  return null;
}

Future<Map<String, dynamic>?> fetchPixabayInfo(String id) async {
  try {
    const apiKey = "52028006-a7e910370a5d0158c371bb06a";
    final res = await http.get(
      Uri.parse("https://pixabay.com/api/?key=$apiKey&id=$id"),
    );

    if (res.statusCode == 200) {
      final hits = jsonDecode(res.body)["hits"];
      if (hits.isNotEmpty) {
        final img = hits[0];
        debugPrint(jsonEncode(img), wrapWidth: 1024);
        
        // Parse tags string into list format
        final tagsList = (img["tags"] as String)
            .split(",")
            .map((tag) => {"name": tag.trim()})
            .toList();
        
        return {
          "source": "Pixabay",
          "id": img["id"].toString(),
          "uploader": img["user"],
          "uploader_id": img["user_id"],
          "uploader_avatar": img["userImageURL"],
          "tags": tagsList,
          "resolution": "${img["imageWidth"]}x${img["imageHeight"]}",
          "dimension_x": img["imageWidth"],
          "dimension_y": img["imageHeight"],
          "file_size": img["imageSize"],
          "views": img["views"],
          "downloads": img["downloads"],
          "likes": img["likes"],
          "comments": img["comments"],
          "url": img["pageURL"],
          "type": img["type"],
        };
      }
    }
  } catch (e) {
    debugPrint("Error fetching Pixabay info: $e");
  }
  return null;
}

Future<Map<String, dynamic>?> fetchUnsplashInfo(String id) async {
  try {
    const accessKey = "yTBcYNAtnRHbrYMn2p4DrBiqzOAfdH9nyexQQtJWO-E";
    final res = await http.get(
      Uri.parse("https://api.unsplash.com/photos/$id?client_id=$accessKey"),
    );

    if (res.statusCode == 200) {
      final json = jsonDecode(res.body);
      debugPrint(jsonEncode(json), wrapWidth: 1024);
      
      // Format user info
      final user = json["user"];
      final uploaderInfo = {
        "username": user["username"],
        "name": user["name"],
        "avatar": {
          "32px": user["profile_image"]?["small"],
          "64px": user["profile_image"]?["medium"],
        },
        "bio": user["bio"],
        "location": user["location"],
      };
      
      // Format tags
      final tagsList = (json["tags"] as List?)
          ?.map((tag) => {"name": tag["title"]})
          .toList() ?? [];
      
      // Extract color if available
      final color = json["color"];
      
      return {
        "source": "Unsplash",
        "id": json["id"],
        "uploader": uploaderInfo,
        "resolution": "${json["width"]}x${json["height"]}",
        "dimension_x": json["width"],
        "dimension_y": json["height"],
        "likes": json["likes"],
        "downloads": json["downloads"],
        "views": json["views"],
        "created_at": json["created_at"],
        "updated_at": json["updated_at"],
        "description": json["description"] ?? json["alt_description"],
        "exif": json["exif"],
        "location": json["location"],
        "tags": tagsList,
        "colors": color != null ? [color] : [],
        "url": json["links"]["html"],
        "blur_hash": json["blur_hash"],
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
      appBar: _isCropMode
          ? AppBar(
              backgroundColor: Colors.black.withValues(alpha: 0.7),
              elevation: 0,
              title: Text(
                "Set as ${_getLocationText()}",
                style: const TextStyle(color: Colors.white),
              ),
              leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: _exitCropMode,
              ),
            )
          : AppBar(backgroundColor: Colors.transparent, elevation: 0),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          /// Fullscreen interactive wallpaper preview
          Positioned.fill(
            child: _isCropMode && _downloadedImage != null
                ? InteractiveViewer(
                    key: _imageKey,
                    transformationController: _transformationController,
                    minScale: 1.0,
                    maxScale: 4.0,
                    boundaryMargin: EdgeInsets.zero,
                    constrained: false,
                    child: Image.file(
                      _downloadedImage!,
                      fit: BoxFit.cover,
                      width: MediaQuery.of(context).size.width,
                      height: MediaQuery.of(context).size.height,
                      // Reduce memory usage
                      cacheWidth: MediaQuery.of(context).size.width.toInt() * 2,
                      cacheHeight: MediaQuery.of(context).size.height.toInt() * 2,
                      filterQuality: FilterQuality.medium,
                    ),
                  )
                : InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: CachedNetworkImage(
                      imageUrl: widget.wallpaper.url,
                      fit: BoxFit.contain,
                      // Memory optimizations for low-end devices
                      memCacheWidth: 1080,
                      memCacheHeight: 1920,
                      maxWidthDiskCache: 1080,
                      maxHeightDiskCache: 1920,
                      fadeInDuration: const Duration(milliseconds: 150),
                      placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      errorWidget: (context, url, error) => const Center(
                        child: Icon(Icons.error, color: Colors.white),
                      ),
                    ),
                  ),
          ),

          // Loading overlay
          if (_isProcessing && !_isCropMode)
            const Positioned.fill(
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),

          // Instruction text (crop mode only)
          if (_isCropMode)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  "Drag to position • Pinch to zoom",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),

          // FAB buttons (only show in normal mode)
          if (!_isCropMode)
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
                        UserSharedPrefs.removeFavWallpaper(widget.wallpaper);
                      } else {
                        UserSharedPrefs.saveFavWallpaper(widget.wallpaper);
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

          // Set wallpaper FAB (crop mode only)
          if (_isCropMode)
            Positioned(
              bottom: 24,
              right: 24,
              child: FloatingActionButton.extended(
                onPressed: _isProcessing ? null : _setWallpaper,
                backgroundColor: _isProcessing
                    ? colorScheme.primary.withValues(alpha: 0.5)
                    : colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                elevation: 8,
                icon: _isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.wallpaper),
                label: Text(_isProcessing ? "Setting..." : "Set Wallpaper"),
              ),
            ),
        ],
      ),
    );
  }
}
