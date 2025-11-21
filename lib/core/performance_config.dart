class PerformanceConfig {
  static const int gridCacheExtent = 1000;
  static const bool addAutomaticKeepAlives = false;
  static const bool addRepaintBoundaries = true;

  static const int thumbnailWidth = 400;
  static const int thumbnailHeight = 600;

  static const Duration fadeInDuration = Duration(milliseconds: 150);

  static const int maxImagesInMemory = 200;
}
