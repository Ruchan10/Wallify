import 'dart:async';

import 'package:wallify/core/config.dart';
import 'package:wallify/core/routes.dart';
import 'package:wallify/core/update_manager.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:flutter/material.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with SingleTickerProviderStateMixin {
  bool _initialized = false;
  final Completer<void> _navigationCompleter = Completer<void>();
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  Future<void> _initializeApp() async {
    if (_navigationCompleter.isCompleted) return;
    _navigationCompleter.complete();
    await UpdateManager.checkForUpdates();
    if (!mounted) return;
    Navigator.popAndPushNamed(context, AppRoute.navRoute);
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );
    _scaleAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initializeApp();
      _initialized = true;
    }
    precacheImage(const AssetImage('assets/images/logo.webp'), context);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: ScaleTransition(
                  scale: _scaleAnim,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer
                              .withValues(alpha: 0.3),
                          shape: BoxShape.circle,
                        ),
                        child: SizedBox(
                          height: 80,
                          child: Image.asset('assets/images/logo.webp'),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        Config.getAppName(),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 50,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Version: ${Config.getAppVersion()}',
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Developed by: RK',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
