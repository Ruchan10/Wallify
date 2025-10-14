import 'dart:io';
import 'dart:math';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/functions/wallpaper_manager.dart';
import 'package:wallpaper_manager_flutter/wallpaper_manager_flutter.dart';

bool _listenersInitialized = false;

void initializeService() async {
  await ensureNotificationPermission();
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
      initialNotificationContent: "Wallify Service Running",
      initialNotificationTitle: "Listening for charging events",
      notificationChannelId: "wallify_channel",
      foregroundServiceNotificationId: 1,
    ),
    iosConfiguration: IosConfiguration(),
  );

  await service.startService();
  const MethodChannel('wallify_channel').setMethodCallHandler((call) async {
    if (call.method == 'charging') {
      bool isCharging = call.arguments as bool;
      service.invoke("charging", {"charging": isCharging});
    }
  });

  setupServiceListeners();
}

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final status = await UserSharedPrefs.getStatusHistory();

  service.on("charging").listen((event) async {
    status.add({
      "title": "Device Charging (event received)",
      "date": DateTime.now().toString(),
    });
    await UserSharedPrefs.saveStatusHistory(status);

    service.invoke("changeWallpaper");
  });
}

void setupServiceListeners() {
  if (_listenersInitialized) return;
  _listenersInitialized = true;

  final service = FlutterBackgroundService();

  service.on("changeWallpaper").listen((event) async {
    debugPrint("Main isolate: changeWallpaper triggered 🚀");

    final wallpaperLocation = await UserSharedPrefs.getWallpaperLocation();
    final status = await UserSharedPrefs.getStatusHistory();

    try {
      if (wallpaperLocation == WallpaperManagerFlutter.bothScreens) {
        final res1 = await WallpaperManager.fetchAndSetWallpaper(
          wallpaperLocation: WallpaperManagerFlutter.homeScreen,
        );
        final res2 = await WallpaperManager.fetchAndSetWallpaper(
          wallpaperLocation: WallpaperManagerFlutter.lockScreen,
        );
        debugPrint("Wallpaper updated: $res1 & $res2");
        status.add({
          "title": "Wallpaper updated: $res1 & $res2",
          "date": DateTime.now().toString(),
        });
        await UserSharedPrefs.saveStatusHistory(status);
      } else {
        final res = await WallpaperManager.fetchAndSetWallpaper(
          wallpaperLocation: wallpaperLocation,
        );
        debugPrint("Wallpaper updated: $res");
        status.add({
          "title": "Wallpaper updated: $res",
          "date": DateTime.now().toString(),
        });
        await UserSharedPrefs.saveStatusHistory(status);
      }
    } catch (e) {
      debugPrint("Error setting wallpaper: $e");
      status.add({
        "title": "Error setting wallpaper: $e",
        "date": DateTime.now().toString(),
      });
      await UserSharedPrefs.saveStatusHistory(status);
    }
  });
}

Future<void> ensureNotificationPermission() async {
  if (await Permission.notification.isDenied) {
    await Permission.notification.request();
  }
}

class BatteryOptimizationDialog extends StatelessWidget {
  const BatteryOptimizationDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Disable Battery Optimization",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text(
            "To ensure wallpapers update properly in the background, "
            "please set Wallify to 'Unrestricted' in battery settings.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text("Later", style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(width: 16),
            FilledButton(
              onPressed: () async {
                final status = await Permission.ignoreBatteryOptimizations
                    .request();
                if (status.isGranted) {
                } else {
                  const intent = AndroidIntent(
                    action:
                        'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
                  );
                  await intent.launch();
                }
              },
              child: const Text(
                "Open Settings",
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

Future<bool> hasInternet() async {
  try {
    final result = await InternetAddress.lookup(
      "google.com",
    ).timeout(const Duration(seconds: 3));
    return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}

Future<File?> getRandomCachedWallpaper() async {
  final dir = await getTemporaryDirectory();
  final files = dir
      .listSync()
      .where((f) => f.path.endsWith(".jpg") && f.path.contains("wallpaper_"))
      .toList();

  if (files.isEmpty) return null;

  final random = Random();
  final file = files[random.nextInt(files.length)];
  return File(file.path);
}
