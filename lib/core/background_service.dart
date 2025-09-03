import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:wallify/core/wallpaper_manager.dart';

void initializeService() {
  FlutterBackgroundService().configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'wallify_channel',
      initialNotificationTitle: 'Wallify Service',
      initialNotificationContent: 'Listening for charging events...',
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );

  FlutterBackgroundService().startService();
}

// iOS background placeholder
bool onIosBackground(ServiceInstance service) {
  return true;
}

// Service start function
void onStart(ServiceInstance service) {
  // Bring Flutter engine alive

  // Listen for custom events from Kotlin if needed
  service.on('changeWallpaper').listen((event) async {
    WallpaperManager.fetchAndSetWallpaper();
  });

  // Optional: keep the service alive periodically
  // Timer.periodic(Duration(minutes: 15), (timer) async {
  //   if (service is AndroidServiceInstance) {
  //     service.setForegroundNotificationInfo(
  //       title: "Wallify Service",
  //       content: "Running in background",
  //     );
  //   }
  // });
}
