import 'dart:io';
import 'dart:ui' as ui show Rect;

import 'package:flutter/material.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:image/image.dart' as img;

class DetectedObjectResult {
  final ui.Rect boundingBox;
  final String label;
  DetectedObjectResult(this.boundingBox, this.label);
}

/// Returns a detected object bounding box if found, null if no object or human.
Future<DetectedObjectResult?> detectMainObject(String imagePath) async {
  final options = ObjectDetectorOptions(
    mode: DetectionMode.single,
    classifyObjects: true,
    multipleObjects: true,
  );

  final detector = ObjectDetector(options: options);

  final inputImage = InputImage.fromFilePath(imagePath);
  final objects = await detector.processImage(inputImage);
  for (final obj in objects) {
    return DetectedObjectResult(
      obj.boundingBox,
      obj.labels.isNotEmpty ? obj.labels.first.text : 'object',
    );
  }
  return null;
}

Future<File?> cropAroundObject({
  required String filePath,
  required ui.Rect boundingBox,
  int deviceWidth = 360,
  int deviceHeight = 800,
}) async {
  try {
    final bytes = await File(filePath).readAsBytes();
    final src = img.decodeImage(bytes);
    if (src == null) return null;

    final aspectRatio = deviceWidth / deviceHeight;

    // Center crop around object
    int objCenterX = (boundingBox.left + boundingBox.width ~/ 2).toInt();
    int objCenterY = (boundingBox.top + boundingBox.height ~/ 2).toInt();

    // Desired crop dimensions
    int cropHeight = (src.width / aspectRatio).toInt();
    if (cropHeight > src.height) {
      cropHeight = src.height;
    }
    int cropWidth = (cropHeight * aspectRatio).toInt();

    // Position crop rectangle centered on object
    int left = (objCenterX - cropWidth ~/ 2).clamp(0, src.width - cropWidth);
    int top = (objCenterY - cropHeight ~/ 2).clamp(0, src.height - cropHeight);

    // Ensure in bounds
    if (left + cropWidth > src.width) left = src.width - cropWidth;
    if (top + cropHeight > src.height) top = src.height - cropHeight;

    final cropped = img.copyCrop(
      src,
      x: left,
      y: top,
      width: cropWidth,
      height: cropHeight,
    );

    // Resize to device resolution (optional, avoids stretching)
    final resized = img.copyResize(
      cropped,
      width: deviceWidth,
      height: deviceHeight,
    );

    // Save new file
    final newPath = filePath.replaceFirst('.jpg', '_cropped.jpg');
    await File(newPath).writeAsBytes(img.encodeJpg(resized, quality: 100));
    return File(newPath);
  } catch (e) {
    debugPrint("Error cropping image: $e ==========================");
    return null;
  }
}
