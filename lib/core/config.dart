class Config {
  static bool _updateAvaliable = false;
  static bool _isUpdateDialogOpen = false;
  static String _appVersion = '1.1.0';
  static String _appName = 'Wallify';
  static bool _hasInternet = false;
  static Map<String, dynamic> _versionData = {};
  static String _cachedLatestVersion = '';
  static String _cachedReleaseNotes = '';
  static List<String> _imageUrls = [];

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

  static List<String> getImageUrls() {
    return _imageUrls;
  }

  static void setImageUrls(List<String> imageUrls) {
    _imageUrls = imageUrls;
  }
}
