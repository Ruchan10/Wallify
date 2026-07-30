import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService extends ValueNotifier<bool> {
  ConnectivityService() : super(true) {
    _init();
  }

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  void _init() {
    _connectivity.checkConnectivity().then((r) {
      value = r.any((e) => e != ConnectivityResult.none);
    });
    _subscription = _connectivity.onConnectivityChanged.listen((r) {
      value = r.any((e) => e != ConnectivityResult.none);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
