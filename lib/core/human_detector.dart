import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

/// Returns true if the image contains humans (face or person label).
Future<bool> containsHuman(String imagePath) async {
  debugPrint(
    "Checking for humans in $imagePath =========================================",
  );
  final file = File(imagePath);
  if (!await file.exists()) return false;

  // 1) Face detection (fast)
  final faceOptions = FaceDetectorOptions(
    performanceMode: FaceDetectorMode.fast,
    enableLandmarks: false,
    enableContours: false,
  );
  final faceDetector = FaceDetector(options: faceOptions);

  try {
    final inputImage = InputImage.fromFilePath(imagePath);
    final faces = await faceDetector.processImage(inputImage);
    await faceDetector.close();

    if (faces.isNotEmpty) {
      return true;
    }
  } catch (e) {
    try {
      await faceDetector.close();
    } catch (_) {}
  }

  // 2) Object detection with classification (for full-body people)
  final options = ObjectDetectorOptions(
    mode: DetectionMode.single,
    classifyObjects: true,
    multipleObjects: true,
  );
  final objectDetector = ObjectDetector(options: options);

  try {
    final inputImage = InputImage.fromFilePath(imagePath);
    final objects = await objectDetector.processImage(inputImage);
    await objectDetector.close();

    if (objects.isNotEmpty) {
      for (final obj in objects) {
        for (final label in obj.labels) {
          final text = label.text.toLowerCase();
          if (text.contains('person') || text.contains('human')) {
            return true;
          }
        }
      }
    }
  } catch (e) {
    try {
      await objectDetector.close();
    } catch (_) {}
  }

  // no humans detected
  return false;
}
