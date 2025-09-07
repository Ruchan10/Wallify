import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wallify/core/background_service.dart';
import 'package:wallify/core/wallpaper_manager.dart';
import 'package:wallify/screens/home_screen.dart';

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

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final lightColorScheme = const ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF7E57C2),
      onPrimary: Colors.white,
      secondary: Color(0xFFFF7043),
      onSecondary: Colors.white,
      surface: Colors.white,
      onSurface: Color(0xFF1C1B1F),
      error: Color(0xFFD32F2F),
      onError: Colors.white,
    );

    final darkColorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: const Color(0xFFB39DDB),
      onPrimary: const Color(0xFF1C1B1F),
      secondary: const Color(0xFFFF8A65),
      onSecondary: const Color(0xFF1C1B1F),
      surface: const Color(0xFF1E1E1E),
      onSurface: const Color(0xFFE6E1E5),
      error: const Color(0xFFEF5350),
      onError: const Color(0xFF1C1B1F),
    );

    ThemeData lightTheme = ThemeData(
      colorScheme: lightColorScheme,
      useMaterial3: true,
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    ThemeData darkTheme = ThemeData(
      colorScheme: darkColorScheme,
      useMaterial3: true,
    );

    return MaterialApp(
      title: 'Auto Wallpaper',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      home: const WallpaperScreen(),
    );
  }
}
