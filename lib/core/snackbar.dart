import 'dart:async';

import 'package:flutter/material.dart';

OverlayEntry? _overlayEntry;
Timer? _removalTimer;

void removeSnackBar() {
  _removalTimer?.cancel();

  if (_overlayEntry != null) {
    _overlayEntry!.remove();
    _overlayEntry = null;
  }
}

void showSnackBar({
  required BuildContext context,
  required String message,
  Color color = Colors.green,
  int duration = 5,
  bool removeBar = true,
}) {
  removeSnackBar();
  final overlayState = Overlay.maybeOf(context);
  if (overlayState == null) {
    return;
  }

  _overlayEntry = OverlayEntry(
    builder: (BuildContext context) {
      return Positioned(
        top: MediaQuery.of(context).padding.top + 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: AnimatedOpacity(
            opacity: 1.0,
            duration: const Duration(milliseconds: 300),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ),
      );
    },
  );

  overlayState.insert(_overlayEntry!);

  if (removeBar) {
    _removalTimer = Timer(Duration(seconds: duration), removeSnackBar);
  }
}