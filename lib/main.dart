import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wallify/core/app_theme.dart';
import 'package:wallify/core/error_reporter.dart';
import 'package:wallify/core/theme_provider.dart';
import 'package:wallify/functions/background_service.dart';
import 'package:wallify/functions/wallpaper_manager.dart';
import 'package:wallify/screens/nav_bar.dart';

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
    
    initializeService();
    // const MethodChannel('wallify_channel').setMethodCallHandler((call) async {
    //   if (call.method == 'changeWallpaper') {
    //     await WallpaperManager.fetchAndSetWallpaper();
    //   }
    // });

    const platform = MethodChannel("wallify/background");
    platform.setMethodCallHandler((call) async {
      if (call.method == "charging_event") {
        final String event = call.arguments ?? "UNKNOWN";

        if (event == "CHARGING") {
          debugPrint(
            "⚡ Device charging → changing wallpaper.. ==========================================.",
          );
          await WallpaperManager.fetchAndSetWallpaper();
        } else if (event == "DISCONNECTED") {
          debugPrint(
            "🔋 Device unplugged → no wallpaper change ==========================================.",
          );
        }
      }
    });

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
