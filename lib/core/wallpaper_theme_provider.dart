import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallify/core/user_shared_prefs.dart';

const _channel = MethodChannel('wallpaper_channel');

/// Seed colour for the Monet theme.
///
/// Prefers the colours of the wallpaper that is actually on the home screen
/// (covers wallpapers set by the background worker or other apps), then falls
/// back to the colour saved when Wallify last set a wallpaper.
final wallpaperThemeProvider = FutureProvider<int?>((ref) async {
  try {
    final current = await _channel.invokeMethod<int>('getCurrentWallpaperColor');
    if (current != null) return current;
  } catch (_) {}

  final prefs = await SharedPreferences.getInstance();
  // Native code writes this while the app is running; drop the stale cache.
  await prefs.reload();
  return prefs.getInt('wallpaperSeedColor');
});

class MonetThemeNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => UserSharedPrefs.getUseMonetTheme();

  /// Updates the theme immediately, then persists the choice.
  Future<void> set(bool enabled) async {
    state = AsyncData(enabled);
    if (enabled) ref.invalidate(wallpaperThemeProvider);
    await UserSharedPrefs.setUseMonetTheme(enabled);
  }
}

final monetThemeProvider = AsyncNotifierProvider<MonetThemeNotifier, bool>(
  MonetThemeNotifier.new,
);
