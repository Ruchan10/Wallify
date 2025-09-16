import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wallify/core/app_theme.dart';
import 'package:wallify/core/theme_provider.dart';
import 'package:wallify/functions/background_service.dart';
import 'package:wallify/functions/background_service.dart' as BackgroundService;
import 'package:wallify/functions/wallpaper_manager.dart';
import 'package:wallify/screens/settings_page.dart';
import 'package:wallify/screens/nav_bar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
