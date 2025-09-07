import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/core/wallpaper_manager.dart';
import 'package:wallpaper_manager_flutter/wallpaper_manager_flutter.dart';

void initializeService() async {
  ensureNotificationPermission();
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'wallify_channel',
      initialNotificationTitle: 'Wallify Service',
      initialNotificationContent: 'Listening for charging events...',
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
    ),
    iosConfiguration: IosConfiguration(),
  );

  await service.startService();
  const MethodChannel('wallify_channel').setMethodCallHandler((call) async {
    debugPrint(
      "Charging event received $call==============================",
    );
    if (call.method == 'charging') {
      bool isCharging = call.arguments as bool;
      service.invoke("charging", {"charging": isCharging});
    }
  });

}

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final status = await UserSharedPrefs.getStatusHistory();
  status.add({"title": "Service started", "date": DateTime.now().toString()});
  await UserSharedPrefs.saveStatusHistory(status);

  debugPrint("ON START ===============================");

  service.on("WALLIFY_CHARGING_EVENT").listen((event) async {
    debugPrint(
      "Wallify Service: WALLIFY_CHARGING_EVENT event received ===============================",
    );
  });

  service.on("charging").listen((event) async {
    debugPrint(
      "Wallify Service: Charging event received $event===============================",
    );

    final wallpaperLocation = await UserSharedPrefs.getWallpaperLocation();

    try {
      if (wallpaperLocation == WallpaperManagerFlutter.bothScreens) {
        final res1 = await WallpaperManager.fetchAndSetWallpaper(
          wallpaperLocation: WallpaperManagerFlutter.homeScreen,
        );
        final res2 = await WallpaperManager.fetchAndSetWallpaper(
          wallpaperLocation: WallpaperManagerFlutter.lockScreen,
        );
        status.add({
          "title": "$res1 & $res2",
          "date": DateTime.now().toString(),
        });
      } else {
        final res = await WallpaperManager.fetchAndSetWallpaper(
          wallpaperLocation: wallpaperLocation,
        );
        status.add({"title": res, "date": DateTime.now().toString()});
      }
    } catch (e) {
      status.add({"title": "Error: $e", "date": DateTime.now().toString()});
    }

    await UserSharedPrefs.saveStatusHistory(status);
  });
}

Future<void> ensureNotificationPermission() async {
  if (await Permission.notification.isDenied) {
    await Permission.notification.request();
  }
}
