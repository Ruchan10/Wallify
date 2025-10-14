import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wallify/core/user_shared_prefs.dart';

class ErrorReporter {
  static const String developerEmail = "ruchan0@protonmail.com"; 
  
  /// Collect device information
  static Future<Map<String, dynamic>> collectDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    final packageInfo = await PackageInfo.fromPlatform();
    
    Map<String, dynamic> info = {
      'app_name': packageInfo.appName,
      'app_version': packageInfo.version,
      'build_number': packageInfo.buildNumber,
      'package_name': packageInfo.packageName,
    };
    
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        info.addAll({
          'platform': 'Android',
          'device_model': androidInfo.model,
          'device_brand': androidInfo.brand,
          'device_manufacturer': androidInfo.manufacturer,
          'android_version': androidInfo.version.release,
          'sdk_int': androidInfo.version.sdkInt,
          'device_id': androidInfo.id,
          'is_physical_device': androidInfo.isPhysicalDevice,
        });
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        info.addAll({
          'platform': 'iOS',
          'device_model': iosInfo.model,
          'device_name': iosInfo.name,
          'system_version': iosInfo.systemVersion,
          'is_physical_device': iosInfo.isPhysicalDevice,
        });
      }
    } catch (e) {
      debugPrint('Error collecting device info: $e');
    }
    
    return info;
  }
  
  /// Format error report
  static String formatErrorReport({
    required Map<String, dynamic> deviceInfo,
    required String errorMessage,
    required StackTrace? stackTrace,
    String? additionalContext,
  }) {
    final buffer = StringBuffer();
    
    buffer.writeln('=== WALLIFY ERROR REPORT ===\n');
    
    // App Info
    buffer.writeln('APP INFORMATION:');
    buffer.writeln('App: ${deviceInfo['app_name']}');
    buffer.writeln('Version: ${deviceInfo['app_version']} (${deviceInfo['build_number']})');
    buffer.writeln('Package: ${deviceInfo['package_name']}\n');
    
    // Device Info
    buffer.writeln('DEVICE INFORMATION:');
    buffer.writeln('Platform: ${deviceInfo['platform']}');
    buffer.writeln('Model: ${deviceInfo['device_model'] ?? 'Unknown'}');
    buffer.writeln('Brand: ${deviceInfo['device_brand'] ?? deviceInfo['device_manufacturer'] ?? 'Unknown'}');
    if (deviceInfo['platform'] == 'Android') {
      buffer.writeln('Android Version: ${deviceInfo['android_version']} (SDK ${deviceInfo['sdk_int']})');
    } else if (deviceInfo['platform'] == 'iOS') {
      buffer.writeln('iOS Version: ${deviceInfo['system_version']}');
    }
    buffer.writeln('Physical Device: ${deviceInfo['is_physical_device']}\n');
    
    // Error Details
    buffer.writeln('ERROR DETAILS:');
    buffer.writeln('Timestamp: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Error Message: $errorMessage\n');
    
    if (additionalContext != null && additionalContext.isNotEmpty) {
      buffer.writeln('ADDITIONAL CONTEXT:');
      buffer.writeln('$additionalContext\n');
    }
    
    if (stackTrace != null) {
      buffer.writeln('STACK TRACE:');
      buffer.writeln(stackTrace.toString());
    }
    
    buffer.writeln('\n=== END OF REPORT ===');
    
    return buffer.toString();
  }
  
  /// Send error report via email
  static Future<bool> sendErrorReport({
    required String errorMessage,
    required StackTrace? stackTrace,
    String? additionalContext,
  }) async {
    try {
      // Check if error reporting is enabled
      final isEnabled = await UserSharedPrefs.getErrorReportingEnabled();
      if (!isEnabled) {
        debugPrint('Error reporting is disabled');
        return false;
      }
      
      // Collect device info
      final deviceInfo = await collectDeviceInfo();
      
      // Format report
      final report = formatErrorReport(
        deviceInfo: deviceInfo,
        errorMessage: errorMessage,
        stackTrace: stackTrace,
        additionalContext: additionalContext,
      );
      
      // Create email
      final subject = Uri.encodeComponent('Wallify Error Report - ${deviceInfo['app_version']}');
      final body = Uri.encodeComponent(report);
      final emailUri = Uri.parse('mailto:$developerEmail?subject=$subject&body=$body');
      
      // Try to launch email client
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
        return true;
      } else {
        debugPrint('Could not launch email client');
        return false;
      }
    } catch (e) {
      debugPrint('Error sending report: $e');
      return false;
    }
  }
  
  /// Show error dialog with option to report
  static Future<void> showErrorDialog({
    required BuildContext context,
    required String errorMessage,
    required StackTrace? stackTrace,
    String? additionalContext,
  }) async {
    final isEnabled = await UserSharedPrefs.getErrorReportingEnabled();
    
    if (!context.mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Error Occurred'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              errorMessage,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            if (isEnabled) ...[
              const SizedBox(height: 16),
              const Text(
                'Would you like to send an error report to help us fix this issue?',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (isEnabled)
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await sendErrorReport(
                  errorMessage: errorMessage,
                  stackTrace: stackTrace,
                  additionalContext: additionalContext,
                );
              },
              icon: const Icon(Icons.send, size: 18),
              label: const Text('Send Report'),
            ),
        ],
      ),
    );
  }
  
  /// Log error without showing dialog
  static Future<void> logError({
    required String errorMessage,
    StackTrace? stackTrace,
    String? additionalContext,
    bool autoSend = false,
  }) async {
    debugPrint('ERROR: $errorMessage');
    if (stackTrace != null) {
      debugPrint('STACK TRACE: $stackTrace');
    }
    
    if (autoSend) {
      await sendErrorReport(
        errorMessage: errorMessage,
        stackTrace: stackTrace,
        additionalContext: additionalContext,
      );
    }
  }
}
