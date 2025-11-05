import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wallify/core/app_theme.dart';
import 'package:wallify/core/error_reporter.dart';
import 'package:wallify/core/theme_provider.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/functions/wallpaper_manager.dart';
import 'package:wallify/screens/nav_bar.dart';
import 'package:workmanager/workmanager.dart';


void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();

    // Set up global error handlers
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      ErrorReporter.logError(
        errorMessage: details.exceptionAsString(),
        stackTrace: details.stack,
        additionalContext: 'Flutter Framework Error',
      );
    };

    // Initialize WorkManager
    Workmanager().initialize(callbackDispatcher);

    // Start preloading in background (don't wait for it)
    _preloadWallpaperData();

    runApp(const ProviderScope(child: MyApp()));
  }, (error, stack) {
    // Catch errors that occur outside of Flutter's framework
    ErrorReporter.logError(
      errorMessage: error.toString(),
      stackTrace: stack,
      additionalContext: 'Uncaught Error',
    );
  });
}

// In main.dart - Background preloading (completely async)
Future<void> _preloadWallpaperData() async {
  // Run in background isolate to prevent UI blocking
  Future.microtask(() async {
    try {
      final wallpaperObjects = await UserSharedPrefs.getImageUrls();
      debugPrint("Background preloading...${wallpaperObjects.length} URLs");

      if (wallpaperObjects.isEmpty) {
        debugPrint("No URLs to preload");
        return;
      }

      // Convert to URLs and sync them
      final imageUrls = wallpaperObjects.map((w) => w.url).toList();

      // Limit to prevent hanging
      final limitedUrls = imageUrls.take(20).toList();
      debugPrint("Preloading ${limitedUrls.length} URLs in background");

      try {
        await WallpaperManager.syncImageUrls(limitedUrls);
        debugPrint("Background preloading complete");
      } catch (e) {
        debugPrint("Background preloading error: $e");
        // Don't throw - this is background operation
      }
    } catch (e) {
      debugPrint("Error in background preloading: $e");
    }
  });
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) {
    try {
      debugPrint("WorkManager task executed: $task ------------------------STEP 1");
      
      // Safe type conversion for cached file paths
      final cachedFilePathsRaw = inputData?['cachedFilePaths'];
      final cachedFilePaths = <String>[];
      if (cachedFilePathsRaw is List) {
        for (var item in cachedFilePathsRaw) {
          if (item is String) {
            cachedFilePaths.add(item);
          }
        }
      }
      
      // Safe type conversion for wallpaperLocation
      final wallpaperLocation = inputData?['wallpaperLocation'] as int? ?? 1;

      debugPrint("Background task - Cached files: ${cachedFilePaths.length}, Location: $wallpaperLocation ================================");
      // Wallpaper changing is now handled by native Android workers
      // No need for Flutter background processing

      return Future.value(true);
    } catch (e) {
      debugPrint("Error in WorkManager task: $e");
      return Future.value(false);
    }
  });
}


class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'Wallify',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const MainScaffold(),
    );
  }
}
