import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallify/core/user_shared_prefs.dart';

final wallpaperThemeProvider = FutureProvider<int?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt('wallpaperSeedColor');
});

final monetThemeProvider = FutureProvider<bool>((ref) async {
  return UserSharedPrefs.getUseMonetTheme();
});
