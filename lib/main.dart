import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wallify/core/app_theme.dart';
import 'package:wallify/core/error_reporter.dart';
import 'package:wallify/core/routes.dart';
import 'package:wallify/core/theme_provider.dart';
import 'package:wallify/core/wallpaper_theme_provider.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        ErrorReporter.logError(
          errorMessage: details.exceptionAsString(),
          stackTrace: details.stack,
          additionalContext: 'Flutter Framework Error',
        );
      };

      runApp(const ProviderScope(child: MyApp()));
    },
    (error, stack) {
      ErrorReporter.logError(
        errorMessage: error.toString(),
        stackTrace: stack,
        additionalContext: 'Uncaught Error',
      );
    },
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final seedColorAsync = ref.watch(wallpaperThemeProvider);

    final seedColor = seedColorAsync.whenOrNull(
      data: (color) => color,
    );

    final seed = seedColor != null ? Color(seedColor) : null;

    return MaterialApp(
      title: 'Wallify',
      theme: AppTheme.generateLightTheme(seed),
      darkTheme: AppTheme.generateDarkTheme(seed),
      themeMode: themeMode,
      initialRoute: AppRoute.splashRoute,
      routes: AppRoute.getAppRoutes(),
    );
  }
}
