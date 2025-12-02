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

class _SplashViewState extends State<SplashView> {
  bool _initialized = false;
  final Completer<void> _navigationCompleter = Completer<void>();

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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initializeApp();

      _initialized = true;
    }

    precacheImage(const AssetImage('assets/images/logo.png'), context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 100,
                    child: Image.asset('assets/images/logo.png'),
                  ),
                  SizedBox(height: 50),
                  TickerMode(
                    enabled: ModalRoute.of(context)?.isCurrent ?? true,
                    child: const CircularProgressIndicator(),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 50,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'Version: ${Config.getAppVersion()}',
                  style: TextStyle(fontSize: 20),
                ),
              ),
            ),
            const Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Center(
                child: Text('Developed by: RK', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
