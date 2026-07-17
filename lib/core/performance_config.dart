import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class PerformanceConfig {
  static const int gridCacheExtent = 500;
  static const bool addAutomaticKeepAlives = false;
  static const bool addRepaintBoundaries = true;

  static const int thumbnailWidth = 400;
  static const int thumbnailHeight = 600;

  static const Duration fadeInDuration = Duration(milliseconds: 150);

  static const int maxImagesInMemory = 200;

  static WallifyCacheManager? _cacheManager;
  static WallifyCacheManager get cacheManager {
    _cacheManager ??= WallifyCacheManager._();
    return _cacheManager!;
  }
}

class WallifyCacheManager extends CacheManager with ImageCacheManager {
  WallifyCacheManager._()
      : super(Config(
          'wallify_cache',
          stalePeriod: const Duration(days: 30),
          maxNrOfCacheObjects: 500,
          repo: JsonCacheInfoRepository(databaseName: 'wallify_cache'),
          fileService: HttpFileService(),
        ));
}
