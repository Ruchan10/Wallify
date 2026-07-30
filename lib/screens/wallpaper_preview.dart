import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallify/core/snackbar.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/core/widget_helper.dart';
import 'package:wallify/functions/wallpaper_cache_manager.dart';
import 'package:wallify/functions/wallpaper_info_sheet.dart';
import 'package:wallify/model/wallpaper_model.dart';
import 'package:wallify/core/wallpaper_theme_provider.dart';
import 'package:wallify/services/ai_service.dart';
import 'package:wallpaper_manager_flutter/wallpaper_manager_flutter.dart';

class WallpaperPreviewPage extends ConsumerStatefulWidget {
  final List<Wallpaper> wallpapers;
  final int initialIndex;
  final bool isFavorite;

  const WallpaperPreviewPage({
    super.key,
    required this.wallpapers,
    required this.initialIndex,
    this.isFavorite = false,
  });

  @override
  ConsumerState<WallpaperPreviewPage> createState() => _WallpaperPreviewPageState();
}

class _WallpaperPreviewPageState extends ConsumerState<WallpaperPreviewPage>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late int _currentIndex;
  late Set<String> _favoritedIds;
  final Map<int, Map<String, dynamic>?> _infoCache = {};
  bool _isCropMode = false;
  bool _isProcessing = false;
  bool _showLockPreview = false;
  bool _isDownloading = false;
  bool _isSettingWallpaper = false;
  int? _selectedLocation;
  bool _blurEnabled = false;
  double _blurRadius = 4.0;
  File? _downloadedImage;
  bool _isAiGenerating = false;
  File? _aiGeneratedFile;
  bool _isAiMode = false;
  final TransformationController _transformationController =
      TransformationController();
  final GlobalKey _imageKey = GlobalKey();
  late AnimationController _fabAnimController;
  late Animation<double> _fabAnim;

  Wallpaper get _currentWallpaper => widget.wallpapers[_currentIndex];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _favoritedIds = {};
    if (widget.isFavorite) {
      _favoritedIds.add(_currentWallpaper.id);
    }
    _loadInfoForIndex(_currentIndex);
    _fabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fabAnim = CurvedAnimation(
      parent: _fabAnimController,
      curve: Curves.easeOutBack,
    );
    _fabAnimController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _transformationController.dispose();
    _fabAnimController.dispose();
    try { _aiGeneratedFile?.deleteSync(); } catch (_) {}
    super.dispose();
  }

  bool _isFav(String id) => _favoritedIds.contains(id);

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
    if (!_infoCache.containsKey(index)) {
      _loadInfoForIndex(index);
    }
  }

  Map<String, dynamic>? get _info => _infoCache[_currentIndex];

  void _showSetWallpaperOptions(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.home, color: colorScheme.primary),
                  ),
                  title: const Text("Set as Home Screen"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    Navigator.pop(context);
                    await _enterCropMode(WallpaperManagerFlutter.homeScreen);
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.lock, color: colorScheme.primary),
                  ),
                  title: const Text("Set as Lock Screen"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    Navigator.pop(context);
                    await _enterCropMode(WallpaperManagerFlutter.lockScreen);
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.phone_android, color: colorScheme.primary),
                  ),
                  title: const Text("Set as Both"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    Navigator.pop(context);
                    await _enterCropMode(WallpaperManagerFlutter.bothScreens);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  },
);

  }

  File? _cropTempFile;

  Future<void> _enterCropMode(int location) async {
    setState(() {
      _selectedLocation = location;
      _isProcessing = true;
    });

    try {
      final cacheManager = DefaultCacheManager();
      final fileInfo =
          await cacheManager.getFileFromCache(_currentWallpaper.url);

      File imageFile;

      if (fileInfo != null && fileInfo.file.existsSync()) {
        imageFile = fileInfo.file;
      } else {
        final cached = await WallpaperCacheManager.downloadAndCache(_currentWallpaper);
        if (cached != null) {
          imageFile = File(cached);
        } else {
          final response = await http.get(Uri.parse(_currentWallpaper.url));
          final dir = await getTemporaryDirectory();
          imageFile = File(
            "${dir.path}/wallpaper_${DateTime.now().millisecondsSinceEpoch}.jpg",
          );
          await imageFile.writeAsBytes(response.bodyBytes);
          _cropTempFile = imageFile;
        }
      }

      setState(() {
        _downloadedImage = imageFile;
        _isCropMode = true;
        _isProcessing = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _detectAndCenterFocus();
      });
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        showSnackBar(context: context, message: "Error: $e", color: Colors.red);
      }
    }
  }

  void _exitCropMode() {
    try { _cropTempFile?.deleteSync(); } catch (_) {}
    _cropTempFile = null;
    setState(() {
      _isCropMode = false;
      _selectedLocation = null;
      _downloadedImage = null;
      _transformationController.value = Matrix4.identity();
    });
  }

  Future<void> _detectAndCenterFocus() async {
    if (_downloadedImage == null) return;
    const channel = MethodChannel('wallpaper_channel');
    final size = MediaQuery.of(context).size;
    try {
      final focus = await channel.invokeMethod<Map<dynamic, dynamic>>(
        'detectFocusPoint',
        {'filePath': _downloadedImage!.path},
      );
      if (focus == null) return;
      final fx = (focus['x'] as num).toDouble();
      final fy = (focus['y'] as num).toDouble();

      final decoded = img.decodeImage(await _downloadedImage!.readAsBytes());
      if (decoded == null) return;
      final imgW = decoded.width.toDouble();
      final imgH = decoded.height.toDouble();

      final scaleX = size.width / imgW;
      final scaleY = size.height / imgH;
      final scale = scaleX > scaleY ? scaleX : scaleY;

      final tx = size.width / 2 - fx * scale;
      final ty = size.height / 2 - fy * scale;

      _transformationController.value = Matrix4.identity()
        ..translate(tx, ty)
        ..scale(scale);
    } catch (e) {
      _centerImageInViewport(size);
    }
  }

  void _centerImageInViewport(Size size) {
    if (_downloadedImage == null) return;
    try {
      final decoded = img.decodeImage(File(_downloadedImage!.path).readAsBytesSync());
      if (decoded == null) return;
      final imgW = decoded.width.toDouble();
      final imgH = decoded.height.toDouble();

      final scaleX = size.width / imgW;
      final scaleY = size.height / imgH;
      final scale = scaleX > scaleY ? scaleX : scaleY;

      final tx = (size.width - imgW * scale) / 2;
      final ty = (size.height - imgH * scale) / 2;

      _transformationController.value = Matrix4.identity()
        ..translate(tx, ty)
        ..scale(scale);
    } catch (_) {}
  }

  Future<img.Image?> _processImage() async {
    if (_downloadedImage == null) return null;
    final matrix = _transformationController.value;
    final screenSize = MediaQuery.of(context).size;
    final imageBytes = await _downloadedImage!.readAsBytes();
    final originalImage = img.decodeImage(imageBytes);
    if (originalImage == null) return null;

    img.Image processed;

    if (matrix == Matrix4.identity()) {
      processed = originalImage;
    } else {
      final imageWidth = originalImage.width.toDouble();
      final imageHeight = originalImage.height.toDouble();
      final scale = matrix.getMaxScaleOnAxis();
      final translation = matrix.getTranslation();

      if (scale >= 1.0) {
        final visibleWidth = screenSize.width / scale;
        final visibleHeight = screenSize.height / scale;
        final offsetX =
            (-translation.x / scale).clamp(0.0, imageWidth - visibleWidth);
        final offsetY =
            (-translation.y / scale).clamp(0.0, imageHeight - visibleHeight);
        processed = img.copyCrop(
          originalImage,
          x: offsetX.toInt(),
          y: offsetY.toInt(),
          width: visibleWidth.toInt().clamp(1, originalImage.width),
          height: visibleHeight.toInt().clamp(1, originalImage.height),
        );
      } else {
        final sw = screenSize.width.toInt();
        final sh = screenSize.height.toInt();
        final result = img.Image(width: sw, height: sh);
        final displayWidth = (imageWidth * scale).toInt().clamp(1, originalImage.width);
        final displayHeight = (imageHeight * scale).toInt().clamp(1, originalImage.height);
        final scaledImage = img.copyResize(originalImage,
          width: displayWidth,
          height: displayHeight,
        );
        final dx = translation.x.toInt();
        final dy = translation.y.toInt();
        img.compositeImage(result, scaledImage, dstX: dx, dstY: dy);
        processed = result;
      }
    }

    if (_blurEnabled) {
      processed = img.gaussianBlur(processed, radius: _blurRadius.toInt());
    }

    return processed;
  }

  Future<File> _saveProcessedToTemp(img.Image processImage) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      "${dir.path}/wallpaper_cropped_${DateTime.now().millisecondsSinceEpoch}.jpg",
    );
    await file.writeAsBytes(img.encodeJpg(processImage, quality: 100));
    return file;
  }

  Future<void> _setWallpaper() async {
    if (_downloadedImage == null || _selectedLocation == null) return;

    setState(() => _isSettingWallpaper = true);

    try {
      final processImage = await _processImage();
      if (processImage == null) throw Exception("Failed to process image");

      final croppedFile = await _saveProcessedToTemp(processImage);

      final noFacesEnabled = await UserSharedPrefs.getConstraintNoFaces();
      if (noFacesEnabled) {
        const channel = MethodChannel('wallpaper_channel');
        final hasFace = await channel.invokeMethod<bool>(
          'checkImageHasFace',
          {'filePath': croppedFile.path},
        );
        if (hasFace == true) {
          if (mounted) {
            showSnackBar(
              context: context,
              message: "Face detected — this wallpaper cannot be used with the 'No Faces' constraint enabled",
              color: Colors.red,
            );
          }
          setState(() => _isSettingWallpaper = false);
          return;
        }
      }

      await WallpaperManagerFlutter().setWallpaper(
        croppedFile,
        _selectedLocation!,
      );

      await UserSharedPrefs.saveWallpaperHistory(_currentWallpaper);

      try {
        const channel = MethodChannel('wallpaper_channel');
        final colors = await channel.invokeMethod<Map<dynamic, dynamic>>(
          'extractWallpaperColors',
          {'filePath': croppedFile.path},
        );
        if (colors != null && colors['dominant'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('wallpaperSeedColor', colors['dominant'] as int);
          ref.invalidate(wallpaperThemeProvider);
        }
      } catch (e) {
        debugPrint("Failed to extract wallpaper colors: $e");
      }

      if (mounted) {
        await _showSetAnimation();
        if (!mounted) return;
        showSnackBar(
          context: context,
          message: "Wallpaper set successfully",
        );
        _exitCropMode();
      }
      updateWidget();
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
        setState(() => _isSettingWallpaper = false);
      }
    }
  }

  Future<void> _showSetAnimation() async {
    final completer = Completer<void>();
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutBack,
            onEnd: () => completer.complete(),
            builder: (ctx, value, _) => Transform.scale(
              scale: value,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.9 * value),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check, color: Colors.white, size: 48),
              ),
            ),
          ),
        ),
      ),
    ));
    await completer.future;
    if (mounted) Navigator.of(context).pop();
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? "PM" : "AM";
    return "$h:$m $ampm";
  }

  String _formatDate(DateTime dt) {
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    return "${months[dt.month - 1]} ${dt.day}, ${dt.year}";
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

  Future<void> _saveFileToWallifyFolder(String tempPath, String fileName) async {
    try {
      const channel = MethodChannel('wallpaper_channel');
      final result = await channel.invokeMethod<String>(
        'saveToDownloads',
        {
          'filePath': tempPath,
          'fileName': fileName,
          'subdirectory': 'Wallify',
        },
      );
      if (result != null) {
        if (mounted) {
          showSnackBar(
            context: context,
            message: "Saved to Downloads/Wallify/",
            color: Colors.green,
          );
        }
      } else {
        throw Exception("Save returned null");
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(
          context: context,
          message: "Failed to save: $e",
          color: Colors.red,
        );
      }
    } finally {
      try { await File(tempPath).delete(); } catch (_) {}
    }
  }

  Future<void> _downloadCroppedWallpaper() async {
    setState(() => _isDownloading = true);
    File? tempFile;
    try {
      final processImage = await _processImage();
      if (processImage == null) throw Exception("Failed to process image");
      tempFile = await _saveProcessedToTemp(processImage);
      final fileName = "Wallify_Cropped_${DateTime.now().millisecondsSinceEpoch}.jpg";
      await _saveFileToWallifyFolder(tempFile.path, fileName);
    } catch (e) {
      if (mounted) {
        showSnackBar(context: context, message: "Download failed: $e", color: Colors.red);
      }
    } finally {
      if (tempFile != null) {
        try { await tempFile.delete(); } catch (_) {}
      }
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _downloadWallpaper() async {
    File? tempFile;
    try {
      final response = await http.get(Uri.parse(_currentWallpaper.url));
      final dir = await getTemporaryDirectory();
      final fileName = "Wallify_${DateTime.now().millisecondsSinceEpoch}.jpg";
      tempFile = File("${dir.path}/$fileName");
      await tempFile.writeAsBytes(response.bodyBytes);
      await _saveFileToWallifyFolder(tempFile.path, fileName);
    } catch (e) {
      if (mounted) {
        showSnackBar(context: context, message: "Download failed: $e", color: Colors.red);
      }
    } finally {
      try { await tempFile?.delete(); } catch (_) {}
    }
  }

  Future<void> _loadInfoForIndex(int index) async {
    final wallpaper = widget.wallpapers[index];
    Map<String, dynamic>? data;

    if (wallpaper.url.contains("wallhaven")) {
      data = await fetchWallhavenInfo(wallpaper.id);
    } else if (wallpaper.url.contains("pixabay.com")) {
      data = await fetchPixabayInfo(wallpaper.id);
    } else if (wallpaper.url.contains("unsplash.com")) {
      data = await fetchUnsplashInfo(wallpaper.id);
    }

    if (mounted) {
      setState(() => _infoCache[index] = data);
    }
  }

  Future<Map<String, dynamic>?> fetchWallhavenInfo(String id) async {
    try {
      final res = await http.get(Uri.parse("https://wallhaven.cc/api/v1/w/$id"));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body)["data"];
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
      final apiKey = await UserSharedPrefs.getPixabayApiKey();
      if (apiKey == null || apiKey.isEmpty) return null;
      final res = await http.get(
        Uri.parse("https://pixabay.com/api/?key=$apiKey&id=$id"),
      );

      if (res.statusCode == 200) {
        final hits = jsonDecode(res.body)["hits"];
        if (hits.isNotEmpty) {
          final img = hits[0];

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
      final accessKey = await UserSharedPrefs.getUnsplashApiKey();
      final res = await http.get(
        Uri.parse(
          "https://api.unsplash.com/photos/$id?client_id=$accessKey",
        ),
      );

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
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

        final tagsList = (json["tags"] as List?)
                ?.map((tag) => {"name": tag["title"]})
                .toList() ??
            [];

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

  Future<void> _triggerAiMagic() async {
    final apiKey = await UserSharedPrefs.getGeminiApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (mounted) {
        showSnackBar(
          context: context,
          message: "Set your free Gemini API key in Settings first",
          color: Colors.orange,
        );
      }
      return;
    }

    try { _aiGeneratedFile?.deleteSync(); } catch (_) {}

    setState(() => _isAiGenerating = true);

    try {
      final result = await AiWallpaperService.generateCustomWallpaper(
        _currentWallpaper.url,
        apiKey,
      );
      if (mounted) {
        setState(() {
          _aiGeneratedFile = result;
          _isAiMode = true;
          _isAiGenerating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAiGenerating = false);
        showSnackBar(
          context: context,
          message: "AI Magic failed: $e",
          color: Colors.red,
        );
      }
    }
  }

  void _toggleAiView() {
    setState(() {
      _isAiMode = !_isAiMode;
    });
  }

  void _showInfoSheet() {
    if (_info == null) {
      showSnackBar(
        context: context,
        message: "No info available",
        color: Colors.red,
      );
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
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
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
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          if (_isCropMode && _downloadedImage != null)
            Center(
              child: InteractiveViewer(
                key: _imageKey,
                transformationController: _transformationController,
                minScale: 0.3,
                maxScale: 4.0,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                constrained: false,
                child: _blurEnabled
                    ? ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: _blurRadius,
                          sigmaY: _blurRadius,
                        ),
                        child: Image.file(
                          _downloadedImage!,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                        ),
                      )
                    : Image.file(
                        _downloadedImage!,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                      ),
              ),
            )
          else if (_isAiMode && _aiGeneratedFile != null)
            Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Image.file(
                      _aiGeneratedFile!,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Positioned(
                  top: 100,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                          SizedBox(width: 6),
                          Text(
                            "AI Generated",
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 100,
                  right: 16,
                  child: FloatingActionButton.small(
                    heroTag: "view_original",
                    backgroundColor: Colors.black.withValues(alpha: 0.6),
                    foregroundColor: Colors.white,
                    onPressed: _toggleAiView,
                    child: const Icon(Icons.image),
                  ),
                ),
                Positioned(
                  bottom: 24,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FloatingActionButton.extended(
                        heroTag: "ai_set_wallpaper",
                        onPressed: () {
                          _downloadedImage = _aiGeneratedFile;
                          _isCropMode = true;
                          _isAiMode = false;
                          setState(() {});
                          WidgetsBinding.instance
                              .addPostFrameCallback((_) {
                            _detectAndCenterFocus();
                          });
                        },
                        backgroundColor:
                            Theme.of(context).colorScheme.primary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimary,
                        icon: const Icon(Icons.wallpaper),
                        label: const Text("Set as Wallpaper"),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            Positioned.fill(
              child: PageView(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                physics: _isCropMode
                    ? const NeverScrollableScrollPhysics()
                    : null,
                children: widget.wallpapers.asMap().entries.map((entry) {
                  final wallpaper = entry.value;
                  return Hero(
                    tag: 'wallpaper_${wallpaper.url}',
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: CachedNetworkImage(
                        imageUrl: wallpaper.url,
                        fit: BoxFit.contain,
                        memCacheWidth: 1080,
                        memCacheHeight: 1920,
                        maxWidthDiskCache: 1080,
                        maxHeightDiskCache: 1920,
                        fadeInDuration: const Duration(milliseconds: 200),
                        placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(),
                        ),
                        errorWidget: (context, url, error) => const Center(
                          child: Icon(Icons.error, color: Colors.white),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

          if (_isProcessing && !_isCropMode)
            const Positioned.fill(
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),

          if (_isAiGenerating)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      "AI is customizing your wallpaper...",
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),

          if (_isCropMode)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Pinch to zoom in/out • Drag to position",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.blur_on,
                          color: _blurEnabled ? Colors.blueAccent : Colors.white70,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Blur",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                        const Spacer(),
                        SizedBox(
                          width: 100,
                          child: Slider(
                            value: _blurRadius,
                            min: 1.0,
                            max: 10.0,
                            divisions: 9,
                            activeColor: Colors.blueAccent,
                            inactiveColor: Colors.white24,
                            onChanged: _blurEnabled
                                ? (v) {
                                    setState(() => _blurRadius = v);
                                  }
                                : null,
                          ),
                        ),
                        SizedBox(
                          width: 28,
                          child: Text(
                            _blurEnabled ? "${_blurRadius.toInt()}" : "",
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Switch(
                          value: _blurEnabled,
                          activeColor: Colors.blueAccent,
                          onChanged: (v) {
                            setState(() => _blurEnabled = v);
                          },
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () => setState(() => _showLockPreview = !_showLockPreview),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _showLockPreview ? Colors.blueAccent.withValues(alpha: 0.3) : Colors.white24,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.lock,
                                  size: 14,
                                  color: _showLockPreview ? Colors.blueAccent : Colors.white70,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  "Preview",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _showLockPreview ? Colors.blueAccent : Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          if (_isCropMode && _showLockPreview)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showLockPreview = false),
                child: Container(
                  color: Colors.black87,
                  child: Center(
                    child: Container(
                      width: 200,
                      height: 400,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white24, width: 2),
                        image: DecorationImage(
                          image: _downloadedImage != null
                              ? FileImage(File(_downloadedImage!.path))
                              : NetworkImage(_currentWallpaper.url) as ImageProvider,
                          fit: BoxFit.cover,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            top: 12,
                            left: 0,
                            right: 0,
                            child: Column(
                              children: [
                                Text(
                                  _formatTime(DateTime.now()),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _formatDate(DateTime.now()),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            top: 12,
                            left: 12,
                            child: Icon(
                              Icons.wifi,
                              color: Colors.white.withValues(alpha: 0.8),
                              size: 16,
                            ),
                          ),
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Icon(
                              Icons.battery_full,
                              color: Colors.white.withValues(alpha: 0.8),
                              size: 16,
                            ),
                          ),
                          Positioned(
                            bottom: 40,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 12,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Text(
                                "Slide to unlock",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          if (!_isCropMode && !_isAiMode)
            Positioned(
              bottom: 24,
              right: 24,
              child: FadeTransition(
                opacity: _fabAnim,
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
                      heroTag: "download_btn",
                      backgroundColor: colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.8),
                      foregroundColor: colorScheme.onSurface,
                      onPressed: () => _downloadWallpaper(),
                      child: const Icon(Icons.download),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton(
                      heroTag: "fav_btn",
                      backgroundColor: colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.8),
                      foregroundColor: colorScheme.onSurface,
                      onPressed: () {
                        final id = _currentWallpaper.id;
                        setState(() {
                          if (_isFav(id)) {
                            _favoritedIds.remove(id);
                            UserSharedPrefs.removeFavWallpaper(
                                _currentWallpaper);
                          } else {
                            _favoritedIds.add(id);
                            UserSharedPrefs.saveFavWallpaper(
                                _currentWallpaper);
                          }
                        });
                      },
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          _isFav(_currentWallpaper.id)
                              ? Icons.favorite
                              : Icons.favorite_border,
                          key: ValueKey(_isFav(_currentWallpaper.id)),
                          color: _isFav(_currentWallpaper.id)
                              ? colorScheme.secondary
                              : colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (_aiGeneratedFile != null && !_isAiMode)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FloatingActionButton(
                            heroTag: "show_ai_btn",
                            backgroundColor: Colors.purple.withValues(alpha: 0.8),
                            foregroundColor: Colors.white,
                            onPressed: _toggleAiView,
                            child: const Icon(Icons.auto_awesome),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    const SizedBox(height: 12),
                    FloatingActionButton(
                      heroTag: "ai_magic_btn",
                      backgroundColor: Colors.purple.withValues(alpha: 0.8),
                      foregroundColor: Colors.white,
                      onPressed:
                          _isAiGenerating ? null : _triggerAiMagic,
                      child: _isAiGenerating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.auto_awesome),
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
            ),

          if (_isCropMode)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FloatingActionButton(
                    heroTag: "crop_download",
                    onPressed: _isDownloading || _isSettingWallpaper ? null : _downloadCroppedWallpaper,
                    backgroundColor: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.8),
                    foregroundColor: colorScheme.onSurface,
                    elevation: 8,
                    child: _isDownloading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.download),
                  ),
                  const SizedBox(width: 16),
                  FloatingActionButton.extended(
                    onPressed: _isDownloading || _isSettingWallpaper ? null : _setWallpaper,
                    backgroundColor: _isSettingWallpaper
                        ? colorScheme.primary.withValues(alpha: 0.5)
                        : colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    elevation: 8,
                    icon: _isSettingWallpaper
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.wallpaper),
                    label: Text(_isSettingWallpaper ? "Setting..." : "Set Wallpaper"),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
