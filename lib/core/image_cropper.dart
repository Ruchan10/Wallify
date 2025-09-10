import 'dart:io';
import 'dart:ui' as ui show Rect;

import 'package:flutter/material.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:image/image.dart' as img;
import 'package:wallify/core/user_shared_prefs.dart';

class DetectedObjectResult {
  final ui.Rect boundingBox;
  final String label;
  DetectedObjectResult(this.boundingBox, this.label);
}

/// Returns a detected object bounding box if found, null if no object or human.
Future<DetectedObjectResult?> detectMainObject(String imagePath) async {
  debugPrint(
    'detectMainObject: $imagePath =========================================',
  );

  final options = ObjectDetectorOptions(
    mode: DetectionMode.single,
    classifyObjects: true,
    multipleObjects: true,
  );

  final detector = ObjectDetector(options: options);

  final inputImage = InputImage.fromFilePath(imagePath);
  debugPrint(
    'Input image: $inputImage =========================================',
  );
  final objects = await detector.processImage(inputImage);
  debugPrint(
    'Object detected after processing: $objects =========================================',
  );
  // await detector.close();
  // debugPrint(
  //   'Object detected after processing and closing: ${objects.first.labels.first.text} =========================================',
  // );
  for (final obj in objects) {
    // for (final label in obj.labels) {
    //   final text = label.text.toLowerCase();
    //   if (text.contains('person') || text.contains('human')) {
    //     debugPrint(
    //       'Object detected: ${obj.labels.first.text} =========================================',
    //     );
    //     return null;
    //   }
    // }

    // If not human, return this object's bounding box
    debugPrint(
      'Object detected: ${obj.labels} =========================================',
    );
    return DetectedObjectResult(
      obj.boundingBox,
      obj.labels.isNotEmpty ? obj.labels.first.text : 'object',
    );
  }
  debugPrint('Object not detected =========================================');
  return null;
}

Future<File?> cropAroundObject({
  required String filePath,
  required ui.Rect boundingBox,
}) async {
  debugPrint(
    'cropAroundObject: $filePath =========================================',
  );

  try {
    final deviceWidth = (await UserSharedPrefs.getDeviceWidth())!;
    final deviceHeight = (await UserSharedPrefs.getDeviceHeight())!;
    debugPrint(
      'cropAroundObject 1 : $deviceWidth, $deviceHeight =========================================',
    );
    final bytes = await File(filePath).readAsBytes();
    final src = img.decodeImage(bytes);
    if (src == null) return null;

    final aspectRatio = deviceWidth / deviceHeight;
    debugPrint(
      'cropAroundObject 2 : $aspectRatio =========================================',
    );
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
    debugPrint("Cropped file saved at $newPath ==========================");
    return File(newPath);
  } catch (e) {
    debugPrint("Error cropping image: $e ==========================");
    return null;
  }
}
