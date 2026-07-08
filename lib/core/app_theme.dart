import 'package:flutter/material.dart';

class AppTheme {
  static const ColorScheme lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF7E57C2),
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFEDE7F6),
    onPrimaryContainer: Color(0xFF2D1B69),
    secondary: Color(0xFFFF7043),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFFFF3E0),
    onSecondaryContainer: Color(0xFF5D2A10),
    surface: Color(0xFFFEFBFF),
    onSurface: Color(0xFF1C1B1F),
    surfaceContainerHighest: Color(0xFFF0EDF1),
    onSurfaceVariant: Color(0xFF49454F),
    error: Color(0xFFD32F2F),
    onError: Colors.white,
    outline: Color(0xFF7A7680),
    outlineVariant: Color(0xFFCAC4D0),
  );

  static const ColorScheme darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFB39DDB),
    onPrimary: Color(0xFF1C1B1F),
    primaryContainer: Color(0xFF4A3B7C),
    onPrimaryContainer: Color(0xFFEDE7F6),
    secondary: Color(0xFFFF8A65),
    onSecondary: Color(0xFF1C1B1F),
    secondaryContainer: Color(0xFF633B22),
    onSecondaryContainer: Color(0xFFFFF3E0),
    surface: Color(0xFF141218),
    onSurface: Color(0xFFE6E1E5),
    surfaceContainerHighest: Color(0xFF2B2930),
    onSurfaceVariant: Color(0xFFCAC4D0),
    error: Color(0xFFEF5350),
    onError: Color(0xFF1C1B1F),
    outline: Color(0xFF938F99),
    outlineVariant: Color(0xFF49454F),
  );

  static ThemeData _buildTheme(ColorScheme colorScheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 2,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: StadiumBorder(
          side: BorderSide.none,
        ),
        backgroundColor: colorScheme.surfaceContainerHighest,
        selectedColor: colorScheme.primary.withValues(alpha: 0.2),
        labelStyle: TextStyle(color: colorScheme.onSurface),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 4,
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  static ThemeData generateLightTheme([Color? seedColor]) {
    if (seedColor == null) return lightTheme;
    return _buildTheme(
      ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.light,
      ),
    );
  }

  static ThemeData generateDarkTheme([Color? seedColor]) {
    if (seedColor == null) return darkTheme;
    return _buildTheme(
      ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.dark,
      ),
    );
  }

  static ThemeData lightTheme = _buildTheme(lightColorScheme);

  static ThemeData darkTheme = _buildTheme(darkColorScheme);
}
