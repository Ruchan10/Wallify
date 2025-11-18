import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:wallify/core/config.dart';

class UpdateManager {
  static const String _checkUrl =
      'https://raw.githubusercontent.com/Ruchan10/Wallify/main/update_info.json';
  static const String _releasesUrl =
      'https://api.github.com/repos/Ruchan10/Wallify/releases/latest';
  static const String _downloadUrlKey = 'url';
  static bool _isChecking = false;

  static Future<void> checkForUpdates() async {
    if (_isChecking) return;
    _isChecking = true;

    try {
      final versionResponse = await http
          .get(Uri.parse(_checkUrl))
          .timeout(const Duration(seconds: 10));

      if (versionResponse.statusCode != 200) {
        return;
      }
      final versionData =
          json.decode(versionResponse.body) as Map<String, dynamic>;
      final latestVersion = versionData['version']?.toString();

      if (latestVersion == null ||
          !_isVersionHigher(Config.getAppVersion(), latestVersion)) {
        return;
      }

      final releasesResponse = await http.get(Uri.parse(_releasesUrl));
      if (releasesResponse.statusCode != 200) {
        return;
      }

      final releasesData =
          json.decode(releasesResponse.body) as Map<String, dynamic>;
      Config.setupdateAvailable(true);

      _cacheUpdateInfo(versionData, releasesData);
    } catch (e) {
      Config.setupdateAvailable(false);
    } finally {
      _isChecking = false;
    }
  }


  static Future<void> showUpdateDialog(BuildContext context) async {
    if (!Config.getUpdateAvailable() || Config.getIsUpdateDialogopen()) {
      return;
    }

    Config.setIsUpdateDialogopen(true);
    final navigator = Navigator.of(context);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _UpdateDialog(
        latestVersion: Config.getCachedLatestVersion(),
        releaseNotes: Config.getCachedReleaseNotes(),
        onDownload: () => _handleDownload(context),
        onCancel: () {
          Config.setIsUpdateDialogopen(false);
          navigator.pop();
        },
      ),
    );
  }

  static Future<void> _handleDownload(BuildContext context) async {
    try {
      final url = await _getDownloadUrl();
      await launchURL(Uri.parse(url));
      Config.setIsUpdateDialogopen(false);
      Navigator.of(context).pop();
    } catch (e) {
      // _log.severe('Download failed', e);
    }
  }

  static Future<String> _getDownloadUrl() async {
    final versionData = Config.getCachedVersionData();

    return versionData[_downloadUrlKey]?.toString() ?? '';
  }

  static Future<void> launchURL(Uri url) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

  static bool _isVersionHigher(String current, String latest) {
    final currentParts = current.split('.').map(int.parse).toList();
    final latestParts = latest.split('.').map(int.parse).toList();

    for (var i = 0; i < latestParts.length; i++) {
      final currentNum = i < currentParts.length ? currentParts[i] : 0;
      final latestNum = latestParts[i];

      if (latestNum > currentNum) return true;
      if (latestNum < currentNum) return false;
    }
    return false;
  }

  static void _cacheUpdateInfo(
    Map<String, dynamic> versionData,
    Map<String, dynamic> releasesData,
  ) {
    Config.setCachedVersionData(versionData);
    Config.setCachedLatestVersion(versionData['version']?.toString() ?? '');
    Config.setCachedReleaseNotes(releasesData['body']?.toString() ?? '');
  }
}

class _UpdateDialog extends StatelessWidget {
  final String latestVersion;
  final String releaseNotes;
  final VoidCallback onDownload;
  final VoidCallback onCancel;

  const _UpdateDialog({
    required this.latestVersion,
    required this.releaseNotes,
    required this.onDownload,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Update Available",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),
          Text(
            'V$latestVersion',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          SizedBox(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.4,
            ),
            child: SingleChildScrollView(
              child: Text(releaseNotes, style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: onCancel,
              child: Text("Cancel", style: TextStyle(fontSize: 16)),
            ),
            SizedBox(width: 16),
            FilledButton(
              onPressed: onDownload,
              child: Text("Download", style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ],
    );
  }
}
