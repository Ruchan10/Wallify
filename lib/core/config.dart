import 'package:flutter/material.dart';
import 'package:wallify/core/user_shared_prefs.dart';

enum SpeedType { notice, table, team, gallery, news }

class Config {
  static bool _updateAvaliable = false;
  static bool _isUpdateDialogOpen = false;
  static String _appVersion = '1.0.3';
  static String _appName = 'SmartBadapatra';
  static UserSharedPrefs usp = UserSharedPrefs();
  static bool _hasInternet = false;

  static Map<String, dynamic> _versionData = {};
  static final Map<String, dynamic> _releasesData = {};
  static String _cachedLatestVersion = '';
  static String _cachedReleaseNotes = '';

  static String getAppVersion() {
    return _appVersion;
  }

  static void setAppVersion(String version) {
    _appVersion = version;
  }

  static void setAppName(String name) {
    _appName = name;
  }

  static String getAppName() {
    return _appName;
  }

  static void setupdateAvailable(bool update) {
    _updateAvaliable = update;
  }

  static bool getUpdateAvailable() {
    return _updateAvaliable;
  }

  static void setIsUpdateDialogopen(bool update) {
    _isUpdateDialogOpen = update;
  }

  static bool getIsUpdateDialogopen() {
    return _isUpdateDialogOpen;
  }

  static void setHasInternet(bool hasInternet) {
    _hasInternet = hasInternet;
  }

  static bool getHasInternet() {
    return _hasInternet;
  }

  static void setCachedVersionData(Map<String, dynamic> versionData) {
    _versionData = versionData;
  }

  static Map<String, dynamic> getCachedVersionData() {
    return _versionData;
  }

  static void setCachedLatestVersion(String version) {
    _cachedLatestVersion = version;
  }

  static String getCachedLatestVersion() {
    return _cachedLatestVersion;
  }

  static void setCachedReleaseNotes(String notes) {
    _cachedReleaseNotes = notes;
  }

  static String getCachedReleaseNotes() {
    return _cachedReleaseNotes;
  }
}

class SpeedConfig {
  static final Map<SpeedType, ValueNotifier<double>> _speeds = {
    SpeedType.notice: ValueNotifier(15.0),
    SpeedType.table: ValueNotifier(30.0),
    SpeedType.team: ValueNotifier(10.0),
    SpeedType.gallery: ValueNotifier(18.0),
    SpeedType.news: ValueNotifier(10.0),
  };

  static final Map<SpeedType, double> _defaultSpeeds = {
    SpeedType.notice: 15.0,
    SpeedType.table: 30.0,
    SpeedType.team: 10.0,
    SpeedType.gallery: 18.0,
    SpeedType.news: 10.0,
  };

  static ValueNotifier<double> getNotifier(SpeedType type) => _speeds[type]!;

  static void changeSpeed(SpeedType type, String action) {
    final notifier = _speeds[type]!;
    switch (action) {
      case 'reset':
        notifier.value = _defaultSpeeds[type]!;
        break;
      case 'increment':
        notifier.value = (notifier.value + 1).clamp(1, 50);
        break;
      case 'decrement':
        notifier.value = (notifier.value - 1).clamp(1, 50);
        break;
      default:
        notifier.value = double.parse(action);
        break;
    }
  }
}
