import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class PerformanceConfig {
  static const int gridCacheExtent = 500;
  static const bool addAutomaticKeepAlives = false;
  static const bool addRepaintBoundaries = true;

  static const int thumbnailWidth = 400;

  static const Duration fadeInDuration = Duration(milliseconds: 150);

  static const int maxImagesInMemory = 200;
  static const int imageCacheMaximumSizeBytes = 100 * 1024 * 1024;

  static void applyImageCacheLimits() {
    PaintingBinding.instance.imageCache.maximumSize = maxImagesInMemory;
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        imageCacheMaximumSizeBytes;
  }

  static WallifyCacheManager? _cacheManager;
  static WallifyCacheManager get cacheManager {
    _cacheManager ??= WallifyCacheManager._();
    return _cacheManager!;
  }

  static PreviewCacheManager? _previewCacheManager;
  static PreviewCacheManager get previewCacheManager {
    _previewCacheManager ??= PreviewCacheManager._();
    return _previewCacheManager!;
  }
}

/// Full-size preview images. Kept small because each entry stores both the
/// original download and a resized copy.
class PreviewCacheManager extends CacheManager with ImageCacheManager {
  static const key = 'wallify_preview_cache';

  PreviewCacheManager._()
      : super(Config(
          key,
          stalePeriod: const Duration(days: 3),
          maxNrOfCacheObjects: 20,
          repo: JsonCacheInfoRepository(databaseName: key),
          fileService: HttpFileService(),
        ));
}

class WallifyCacheManager extends CacheManager with ImageCacheManager {
  WallifyCacheManager._()
      : super(Config(
          'wallify_cache',
          stalePeriod: const Duration(days: 14),
          maxNrOfCacheObjects: 100,
          repo: JsonCacheInfoRepository(databaseName: 'wallify_cache'),
          fileService: HttpFileService(),
        ));
}
