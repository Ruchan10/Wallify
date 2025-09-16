import 'package:flutter/material.dart';

class AppTheme {
  // --- LIGHT COLOR SCHEME ---
  static const ColorScheme lightColorScheme = ColorScheme(
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

  // --- DARK COLOR SCHEME ---
  static const ColorScheme darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFB39DDB),
    onPrimary: Color(0xFF1C1B1F),
    secondary: Color(0xFFFF8A65),
    onSecondary: Color(0xFF1C1B1F),
    surface: Color(0xFF1E1E1E),
    onSurface: Color(0xFFE6E1E5),
    error: Color(0xFFEF5350),
    onError: Color(0xFF1C1B1F),
  );

  // --- LIGHT THEME ---
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: lightColorScheme,
    appBarTheme: AppBarTheme(
      backgroundColor: lightColorScheme.primary,
      foregroundColor: lightColorScheme.onPrimary,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: lightColorScheme.primary,
      foregroundColor: lightColorScheme.onPrimary,
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: lightColorScheme.surface,
      selectedColor: lightColorScheme.primary.withValues(alpha: 0.2),
      labelStyle: TextStyle(color: lightColorScheme.onSurface),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: lightColorScheme.surface.withValues(alpha: 0.9),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );

  // --- DARK THEME ---
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    colorScheme: darkColorScheme,
    appBarTheme: AppBarTheme(
      backgroundColor: darkColorScheme.surface,
      foregroundColor: darkColorScheme.onSurface,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: darkColorScheme.primary,
      foregroundColor: darkColorScheme.onPrimary,
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: darkColorScheme.surface,
      selectedColor: darkColorScheme.primary.withValues(alpha: 0.3),
      labelStyle: TextStyle(color: darkColorScheme.onSurface),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkColorScheme.surface.withValues(alpha: 0.9),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
