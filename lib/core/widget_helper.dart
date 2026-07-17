import 'package:flutter/services.dart';

const _channel = MethodChannel('wallpaper_channel');

Future<void> updateWidget() async {
  try {
    await _channel.invokeMethod('updateWidget');
  } catch (e) {
    // Silently fail — widget updates are non-critical
  }
}
