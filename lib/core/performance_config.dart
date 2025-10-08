/// Performance configuration for low-end device optimization
class PerformanceConfig {
  // Image cache limits
  static const int maxCachedImages = 100;
  static const int imageCacheWidth = 1080;
  static const int imageCacheHeight = 1920;
  
  // Grid view optimizations
  static const int gridCacheExtent = 1000;
  static const bool addAutomaticKeepAlives = false;
  static const bool addRepaintBoundaries = true;
  
  // Image quality settings
  static const int jpegQuality = 100;
  static const int thumbnailWidth = 400;
  static const int thumbnailHeight = 600;
  
  // Animation durations (shorter for low-end devices)
  static const Duration fadeInDuration = Duration(milliseconds: 150);
  static const Duration animationDuration = Duration(milliseconds: 200);
  
  // Memory limits
  static const int maxImagesInMemory = 200;
  static const int maxConcurrentDownloads = 3;
  
  // Rendering optimizations
  static const bool enableRepaintBoundary = true;
  static const bool enableCacheExtent = true;
}
