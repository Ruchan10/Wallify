import 'dart:ui' as img;

import 'package:wallify/functions/image_cropper.dart';

Future<void> setWallpaperWithDetection(
  String imagePath,
  int deviceWidth,
  int deviceHeight,
) async {
  final obj = await HumanDetector.detectMainObject(imagePath);
  if (obj == null) {
    print("No suitable object found or human detected, skipping...");
    return;
  }

  final croppedPath = await cropAroundObject(
    filePath: imagePath,
    boundingBox: img.Rect.fromLTWH(
      obj.boundingBox.left.toInt(),
      obj.boundingBox.top.toInt(),
      obj.boundingBox.width.toInt(),
      obj.boundingBox.height.toInt(),
    ),
  );

  if (croppedPath != null) {
    print("Wallpaper ready at $croppedPath");
    // TODO: call your WallpaperManager to set this cropped file
  }
}
