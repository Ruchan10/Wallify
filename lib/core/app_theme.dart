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

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: lightColorScheme,
    appBarTheme: AppBarTheme(
      backgroundColor: lightColorScheme.primary,
      foregroundColor: lightColorScheme.onPrimary,
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 2,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: lightColorScheme.primary,
      foregroundColor: lightColorScheme.onPrimary,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: StadiumBorder(
        side: BorderSide.none,
      ),
      backgroundColor: lightColorScheme.surfaceContainerHighest,
      selectedColor: lightColorScheme.primary.withValues(alpha: 0.2),
      labelStyle: TextStyle(color: lightColorScheme.onSurface),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: lightColorScheme.surfaceContainerHighest
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

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    colorScheme: darkColorScheme,
    appBarTheme: AppBarTheme(
      backgroundColor: darkColorScheme.surface,
      foregroundColor: darkColorScheme.onSurface,
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 2,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: darkColorScheme.primary,
      foregroundColor: darkColorScheme.onPrimary,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: StadiumBorder(
        side: BorderSide.none,
      ),
      backgroundColor: darkColorScheme.surfaceContainerHighest,
      selectedColor: darkColorScheme.primary.withValues(alpha: 0.3),
      labelStyle: TextStyle(color: darkColorScheme.onSurface),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkColorScheme.surfaceContainerHighest
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
