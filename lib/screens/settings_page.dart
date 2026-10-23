import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' hide Config;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wallify/core/config.dart';
import 'package:wallify/core/performance_config.dart';
import 'package:wallify/core/snackbar.dart';
import 'package:wallify/core/theme_provider.dart';
import 'package:wallify/core/update_manager.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/core/wallpaper_theme_provider.dart';
import 'package:wallify/functions/backup_function.dart';
import 'package:wallify/functions/wallpaper_cache_manager.dart';
import 'package:wallify/functions/wallpaper_manager.dart';
import 'package:wallify/core/widget_helper.dart';
import 'package:wallify/services/wallpaper_api_service.dart';
import 'package:wallpaper_manager_flutter/wallpaper_manager_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsPage extends ConsumerStatefulWidget {
  final bool isNavBarVisible;
  const SettingsPage({super.key, required this.isNavBarVisible});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final TextEditingController _tagController = TextEditingController();

  List<String> savedTags = [];
  Set<String> _invalidTags = {};

  /// Tags whose availability check is still running.
  final Set<String> _checkingTags = {};
  int wallpaperLocation = WallpaperManagerFlutter.bothScreens;

  int _intervalMinutes = 60;
  final TextEditingController _intervalController = TextEditingController(
    text: "60",
  );
  Timer? _intervalDebounce;
  Timer? _rescheduleDebounce;
  static const platform = MethodChannel('wallpaper_channel');
  bool _autoWallpaperEnabled = false;
  List<String> _wallpaperSources = [UserSharedPrefs.defaultWallpaperSource];
  String _topPicksRange = "1w";

  static const _sourceLabels = {
    "internet": "Internet",
    "toppicks": "Top Picks",
    "folder": "Folder",
    "favorites": "Favorites",
  };
  static const _topPicksRangeLabels = {
    "1d": "Today",
    "1w": "This week",
    "1M": "This month",
    "1y": "This year",
  };
  List<String> _folderPaths = [];
  bool _updateAvailable = false;
  bool _checkingUpdate = true;
  bool _errorReportingEnabled = false;
  DateTime? _lastChange;
  /// What Change Now is doing, shown on the button; null when idle.
  String? _changeStatus;
  bool get _changingNow => _changeStatus != null;
  Timer? _changeStatusPoll;
  bool _backupBusy = false;

  /// [defaultOn] matches what the native worker assumes while unset.
  static const _constraints = [
    (key: "constraint_charging", label: "Charging", defaultOn: false),
    (key: "constraint_battery_not_low", label: "Battery Not Low", defaultOn: false),
    (key: "constraint_storage_not_low", label: "Storage Not Low", defaultOn: false),
    (key: "constraint_no_faces", label: "No Faces", defaultOn: true),
  ];
  Map<String, bool> _constraintValues = {};

  static const _locations = [
    (value: WallpaperManagerFlutter.homeScreen, label: "Home"),
    (value: WallpaperManagerFlutter.lockScreen, label: "Lock"),
    (value: WallpaperManagerFlutter.bothScreens, label: "Both"),
  ];

  int? _cacheSize;
  bool _batteryOptimized = false;

  /// Bumped after an import so the API key fields reload their values.
  int _apiKeysVersion = 0;

  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _initialize();
    _checkUpdateStatus();
    _loadCacheSize();
    _loadBatteryStatus();
    // The Quick Settings tile and the worker change state while the app is open.
    _lifecycleListener = AppLifecycleListener(onResume: _refreshFromNative);
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _intervalDebounce?.cancel();
    _rescheduleDebounce?.cancel();
    _changeStatusPoll?.cancel();
    _tagController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  Future<void> _refreshFromNative() async {
    final enabled = await UserSharedPrefs.getAutoWallpaperEnabled();
    final lastChange = await UserSharedPrefs.getLastWallpaperChange();
    if (!mounted) return;
    if (enabled != _autoWallpaperEnabled || lastChange != _lastChange) {
      setState(() {
        _autoWallpaperEnabled = enabled;
        _lastChange = lastChange;
      });
    }
    _followRunningChange();
  }

  /// Sums file sizes in a background isolate; the image caches can hold
  /// thousands of files and stat-ing them on the UI thread stalls scrolling.
  static int _sumDirSizes(List<String> paths) {
    var total = 0;
    for (final path in paths) {
      final dir = Directory(path);
      if (!dir.existsSync()) continue;
      try {
        for (final entity in dir.listSync(recursive: true)) {
          if (entity is File) {
            try {
              total += entity.lengthSync();
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
    return total;
  }

  static Future<int> _computeDirSizes(List<String> paths) =>
      Isolate.run(() => _sumDirSizes(paths));

  Future<void> _loadCacheSize() async {
    try {
      final temp = (await getTemporaryDirectory()).path;
      final paths = [
        '$temp/libCachedImageData',
        '$temp/wallify_cache',
        '$temp/${PreviewCacheManager.key}',
        await WallpaperCacheManager.cacheDirPath(),
      ];
      final size = await _computeDirSizes(paths);
      if (mounted) setState(() => _cacheSize = size);
    } catch (_) {}
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  Future<void> _clearAllCaches() async {
    try {
      await Future.wait([
        DefaultCacheManager().emptyCache(),
        PerformanceConfig.cacheManager.emptyCache(),
        PerformanceConfig.previewCacheManager.emptyCache(),
        WallpaperCacheManager.clearCache(),
      ]);
      await _loadCacheSize();
      if (mounted) {
        showSnackBar(context: context, message: "Cache cleared");
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(
          context: context,
          message: "Failed to clear cache: $e",
          color: Colors.red,
        );
      }
    }
  }

  Future<void> _checkUpdateStatus() async {
    await UpdateManager.checkForUpdates();
    if (mounted) {
      setState(() {
        _updateAvailable = Config.getUpdateAvailable();
        _checkingUpdate = false;
      });
    }
  }

  Future<void> _loadBatteryStatus() async {
    try {
      final ignoring =
          await platform.invokeMethod<bool>("isIgnoringBatteryOptimizations");
      if (mounted) {
        setState(() => _batteryOptimized = ignoring ?? false);
      }
    } catch (_) {}
  }

  Future<void> _requestBatteryOptimization() async {
    try {
      await platform.invokeMethod("requestIgnoreBatteryOptimizations");
      if (!mounted) return;
      showSnackBar(
        context: context,
        message: "Allow 'Don't restrict' in the battery settings",
      );
      await Future.delayed(const Duration(seconds: 2));
      await _loadBatteryStatus();
    } catch (e) {
      if (mounted) {
        showSnackBar(
          context: context,
          message: "Failed to open battery settings: $e",
          color: Colors.red,
        );
      }
    }
  }

  Future<void> _initialize() async {
    final results = await Future.wait<Object?>([
      UserSharedPrefs.getAutoWallpaperEnabled(),
      UserSharedPrefs.getTags(),
      UserSharedPrefs.getInvalidTags(),
      UserSharedPrefs.getWallpaperLocation(),
      UserSharedPrefs.getInterval(),
      UserSharedPrefs.getWallpaperSources(),
      UserSharedPrefs.getFolderPaths(),
      UserSharedPrefs.getErrorReportingEnabled(),
      UserSharedPrefs.getLastWallpaperChange(),
      Future.wait(_constraints.map(
        (c) => UserSharedPrefs.getBool(c.key, defaultValue: c.defaultOn),
      )),
      UserSharedPrefs.getTopPicksRange(),
    ]);
    if (!mounted) return;

    final constraintValues = results[9] as List<bool>;
    setState(() {
      _autoWallpaperEnabled = results[0] as bool;
      savedTags = results[1] as List<String>;
      _invalidTags = results[2] as Set<String>;
      wallpaperLocation = results[3] as int;
      _intervalMinutes = results[4] as int;
      _intervalController.text = _intervalMinutes.toString();
      _wallpaperSources = results[5] as List<String>;
      _folderPaths = results[6] as List<String>;
      _errorReportingEnabled = results[7] as bool;
      _lastChange = results[8] as DateTime?;
      _topPicksRange = results[10] as String;
      _constraintValues = {
        for (var i = 0; i < _constraints.length; i++)
          _constraints[i].key: constraintValues[i],
      };
    });
    if (_autoWallpaperEnabled) _rescheduleWorker(immediately: true);
    _followRunningChange();
  }

  /// Re-registers the background worker so it picks up new settings. Calls
  /// within a short window are merged, since each one restarts native work.
  void _rescheduleWorker({bool immediately = false}) {
    _rescheduleDebounce?.cancel();
    Future<void> run() async {
      try {
        await platform.invokeMethod("scheduleBackgroundWallpaperWorker");
      } catch (e) {
        debugPrint("Rescheduling worker failed: $e");
      }
    }

    if (immediately) {
      run();
    } else {
      _rescheduleDebounce = Timer(const Duration(milliseconds: 500), run);
    }
  }

  /// Settings that change which wallpapers the worker can pick were edited:
  /// reschedule it and refresh its pool in the background.
  void _onPoolSettingsChanged() {
    _rescheduleWorker();
    WallpaperManager.scheduleRefresh();
  }

  Future<void> changeWallpaper() async {
    if (_changingNow) return;
    setState(() => _changeStatus = "Finding wallpapers…");
    try {
      // Make sure the worker picks from the current tags and sources.
      if (_wallpaperSources.any(const {"internet", "favorites", "toppicks"}.contains)) {
        await WallpaperManager.refreshPool();
      }
      // Returns once the wallpaper is actually set (download, crop, apply);
      // until then the button shows which of those it's on.
      _pollChangeStatus();
      await platform.invokeMethod("scheduleBackgroundWallpaperWorkerNow");
      await updateWidget();
      final lastChange = await UserSharedPrefs.getLastWallpaperChange();
      if (mounted) {
        setState(() => _lastChange = lastChange);
        showSnackBar(
          context: context,
          color: Colors.green,
          message: "Wallpaper changed",
        );
      }
    } on PlatformException catch (e) {
      if (mounted) {
        showSnackBar(
          context: context,
          color: Colors.red,
          message: switch (e.code) {
            "CHANGE_FAILED" => "Couldn't change the wallpaper — no suitable image found",
            "OFFLINE" => "Couldn't download a wallpaper — check your connection",
            "BUSY" => "Another wallpaper change is still running",
            _ => "Error: ${e.message ?? e.code}",
          },
        );
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context: context, color: Colors.red, message: "Error: $e");
      }
    } finally {
      _changeStatusPoll?.cancel();
      if (mounted) setState(() => _changeStatus = null);
    }
  }

  Future<String?> _nativeChangeStatus() async {
    try {
      return await platform.invokeMethod<String>("getWallpaperChangeStatus");
    } catch (_) {
      return null;
    }
  }

  /// Mirrors the native change's current step on the button.
  void _pollChangeStatus() {
    _changeStatusPoll?.cancel();
    _changeStatusPoll = Timer.periodic(
      const Duration(milliseconds: 400),
      (_) async {
        final status = await _nativeChangeStatus();
        if (status != null && mounted && _changingNow) {
          setState(() => _changeStatus = status);
        }
      },
    );
  }

  /// Shows a change this page didn't start on the button until it ends: the
  /// worker, the widget, or a Change Now from before the app was restarted
  /// (the system can restart it when the new wallpaper re-themes the phone).
  Future<void> _followRunningChange() async {
    if (_changingNow) return;
    String? status = await _nativeChangeStatus();
    if (status == null || !mounted || _changingNow) return;
    setState(() => _changeStatus = status);
    while (status != null) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      status = await _nativeChangeStatus();
      if (status != null && mounted) setState(() => _changeStatus = status);
    }
    final lastChange = await UserSharedPrefs.getLastWallpaperChange();
    if (mounted) {
      setState(() {
        _changeStatus = null;
        _lastChange = lastChange;
      });
    }
  }

  // ------------------------------------------------------------------ tags

  /// Adds one or more comma-separated tags, then checks each against every
  /// source in the background.
  Future<void> _addTags(String input) async {
    final existing = savedTags.map((t) => t.toLowerCase()).toSet();
    final newTags = <String>[];
    for (final raw in input.split(",")) {
      final tag = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (tag.isNotEmpty && existing.add(tag.toLowerCase())) newTags.add(tag);
    }
    _tagController.clear();
    if (newTags.isEmpty) return;

    setState(() {
      savedTags = [...savedTags, ...newTags];
      _checkingTags.addAll(newTags);
    });
    await UserSharedPrefs.saveTags(savedTags);
    _onPoolSettingsChanged();
    await Future.wait(newTags.map(_validateTag));
  }

  Future<void> _validateTag(String tag) async {
    if (mounted) setState(() => _checkingTags.add(tag));
    final valid = await WallpaperManager.validateTag(tag);

    // The tag may have been removed while it was being checked.
    if (savedTags.contains(tag)) {
      if (valid == false) _invalidTags.add(tag);
      if (valid == true) _invalidTags.remove(tag);
      await UserSharedPrefs.saveInvalidTags(_invalidTags);
    }
    if (!mounted) return;
    setState(() => _checkingTags.remove(tag));

    if (valid == false) {
      showSnackBar(
        context: context,
        color: Colors.red,
        message: "No wallpapers found for \"$tag\" in any source",
      );
    } else if (valid == null) {
      showSnackBar(
        context: context,
        color: Colors.orange,
        message: "Couldn't check \"$tag\" — no source reachable. Tap it to retry.",
      );
    }
  }

  Future<void> _removeTag(String tag) async {
    setState(() {
      savedTags = savedTags.where((t) => t != tag).toList();
      _invalidTags.remove(tag);
      _checkingTags.remove(tag);
    });
    await Future.wait([
      UserSharedPrefs.saveTags(savedTags),
      UserSharedPrefs.saveInvalidTags(_invalidTags),
    ]);
    _onPoolSettingsChanged();
  }

  // ------------------------------------------------------------ automation

  Future<void> _setAutoWallpaper(bool value) async {
    setState(() => _autoWallpaperEnabled = value);
    // Save first: the native scheduler reads this flag and does nothing
    // while it is still false.
    await UserSharedPrefs.setAutoWallpaperEnabled(value);
    // Persist the shown selection (Top Picks unless the user chose other
    // sources) so the native worker and widgets read the same thing.
    if (value) await UserSharedPrefs.saveWallpaperSources(_wallpaperSources);

    try {
      await platform.invokeMethod(
        value
            ? "scheduleBackgroundWallpaperWorker"
            : "cancelBackgroundWallpaperWorker",
      );
      if (mounted) {
        showSnackBar(
          context: context,
          color: value ? Colors.green : Colors.red,
          message: value ? "Auto wallpaper enabled ✅" : "Auto wallpaper disabled 🚫",
        );
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(
          context: context,
          color: Colors.red,
          message: value
              ? "Failed to enable auto wallpaper: $e"
              : "Failed to disable automation: $e",
        );
      }
    }
    if (value) WallpaperManager.scheduleRefresh(delay: Duration.zero);
    updateWidget();
  }

  void _setLocation(int location) {
    if (location == wallpaperLocation) return;
    setState(() => wallpaperLocation = location);
    UserSharedPrefs.saveWallpaperLocation(location);
    _rescheduleWorker();
    updateWidget();
  }

  void _onIntervalChanged(String value) {
    _intervalDebounce?.cancel();
    // Wait until typing stops: applying "1" while the user is typing "120"
    // would snap the field to the 15 minute minimum.
    _intervalDebounce = Timer(
      const Duration(milliseconds: 900),
      () => _applyInterval(value, restoreIfInvalid: false),
    );
  }

  void _applyInterval(String value, {bool restoreIfInvalid = true}) {
    _intervalDebounce?.cancel();
    if (!mounted) return;
    final minutes = int.tryParse(value.trim());
    if (minutes == null || minutes <= 0) {
      if (restoreIfInvalid) _intervalController.text = "$_intervalMinutes";
      return;
    }
    final applied = max(15, minutes);
    if (applied != minutes) {
      showSnackBar(
        context: context,
        color: Colors.orange,
        message: "Minimum interval is 15 minutes",
      );
      _intervalController.text = "$applied";
    }
    if (applied == _intervalMinutes) return;
    setState(() => _intervalMinutes = applied);
    UserSharedPrefs.saveInterval(applied);
    updateWidget();
    _rescheduleWorker();
  }

  Future<void> _toggleSource(String source, bool selected) async {
    setState(() {
      _wallpaperSources = [
        ..._wallpaperSources.where((s) => s != source),
        if (selected) source,
      ];
      // Always keep at least one source selected.
      if (_wallpaperSources.isEmpty) {
        _wallpaperSources = [UserSharedPrefs.defaultWallpaperSource];
      }
    });
    await UserSharedPrefs.saveWallpaperSources(_wallpaperSources);
    _onPoolSettingsChanged();
    updateWidget();
  }

  Future<void> _setTopPicksRange(String range) async {
    if (range == _topPicksRange) return;
    setState(() => _topPicksRange = range);
    await UserSharedPrefs.setTopPicksRange(range);
    _onPoolSettingsChanged();
  }

  Future<void> _setFolders(List<String> folders) async {
    setState(() => _folderPaths = folders);
    await UserSharedPrefs.setFolderPaths(folders);
    _rescheduleWorker();
  }

  Future<void> _setConstraint(String key, bool selected) async {
    setState(() => _constraintValues = {..._constraintValues, key: selected});
    await UserSharedPrefs.setBool(key, selected);
    _rescheduleWorker();
  }

  Future<void> _setErrorReporting(bool value) async {
    setState(() => _errorReportingEnabled = value);
    await UserSharedPrefs.setErrorReportingEnabled(value);
    if (mounted) {
      showSnackBar(
        context: context,
        message: value ? "Error reporting enabled" : "Error reporting disabled",
      );
    }
  }

  // ---------------------------------------------------------- backup

  Future<bool> _hasApiKeys() async {
    final keys = await Future.wait([
      UserSharedPrefs.getPexelsApiKey(),
      UserSharedPrefs.getPixabayApiKey(),
      UserSharedPrefs.getGeminiApiKey(),
      UserSharedPrefs.getUnsplashApiKey().then(
        (v) => v == UserSharedPrefs.defaultUnsplashKey ? null : v,
      ),
    ]);
    return keys.any((k) => k != null && k.isNotEmpty);
  }

  Future<void> _exportSettings() async {
    if (_backupBusy) return;
    var includeKeys = true;
    if (await _hasApiKeys()) {
      if (!mounted) return;
      final choice = await showDialog<bool>(
        context: context,
        builder: (context) => _IncludeKeysDialog(
          title: "Export settings",
          message:
              "Saves tags, favorites, history, automation and appearance "
              "settings to Downloads/Wallify.",
          keysLabel: "Include API keys",
          keysWarning:
              "Keys are stored in plain text in the file. Don't share it.",
          confirmLabel: "Export",
        ),
      );
      if (choice == null) return;
      includeKeys = choice;
    }

    setState(() => _backupBusy = true);
    try {
      final location = await SettingsBackup.exportSettings(
        includeApiKeys: includeKeys,
      );
      if (mounted) {
        showSnackBar(
          context: context,
          color: Colors.green,
          message: "Saved to $location",
        );
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(
          context: context,
          color: Colors.red,
          message: "Export failed: $e",
        );
      }
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _importSettings() async {
    if (_backupBusy) return;
    try {
      // Any type: many file managers don't tag .json files with a JSON
      // MIME type, so filtering by extension can hide valid backups.
      final picked = await FilePicker.pickFile(type: FileType.any);
      if (picked == null) return;

      setState(() => _backupBusy = true);
      // Read through the picker rather than a path: files picked from
      // Drive or a document provider have no local path.
      final preview = SettingsBackup.parse(await picked.readAsBytes());
      if (!mounted) return;

      final includeKeys = await showDialog<bool>(
        context: context,
        builder: (context) => _IncludeKeysDialog(
          title: "Restore backup?",
          message: _describeBackup(preview),
          keysLabel: preview.apiKeyNames.isEmpty
              ? null
              : "Restore API keys (${preview.apiKeyNames.join(", ")})",
          keysWarning: "Replaces the keys saved on this device.",
          confirmLabel: "Restore",
        ),
      );
      if (includeKeys == null) return;

      final result = await SettingsBackup.importSettings(
        preview,
        includeApiKeys: includeKeys,
      );
      await _applyImportedSettings();

      if (mounted) {
        showSnackBar(
          context: context,
          color: Colors.green,
          message: result.skipped == 0
              ? "Restored ${result.imported} settings"
              : "Restored ${result.imported} settings, "
                    "skipped ${result.skipped} unrecognised",
        );
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(
          context: context,
          color: Colors.red,
          message: e is FormatException ? e.message : "Import failed: $e",
        );
      }
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  String _describeBackup(BackupPreview preview) {
    final parts = <String>[
      if (preview.exportedAt != null)
        "Exported ${DateFormat("MMM d, y 'at' h:mm a").format(preview.exportedAt!.toLocal())}"
            "${preview.appVersion != null ? " from v${preview.appVersion}" : ""}.",
      "Contains ${preview.tagCount} tags, ${preview.favoriteCount} favorites "
          "and ${preview.historyCount} history entries.",
      "Favorites, history and tags are merged with this device's; other "
          "settings are replaced.",
    ];
    return parts.join("\n\n");
  }

  /// Makes imported settings take effect without restarting the app.
  Future<void> _applyImportedSettings() async {
    ref.invalidate(themeProvider);
    ref.invalidate(monetThemeProvider);
    ref.invalidate(wallpaperThemeProvider);
    await _initialize(); // reloads state and reschedules if auto is on
    if (!_autoWallpaperEnabled) {
      try {
        await platform.invokeMethod("cancelBackgroundWallpaperWorker");
      } catch (_) {}
    }
    WallpaperManager.scheduleRefresh(delay: Duration.zero);
    await updateWidget();
    if (mounted) setState(() => _apiKeysVersion++);
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.only(
                top: 16.0,
                left: 16.0,
                right: 16.0,
                bottom: 56,
              ),

              children: [
                Text(
                  "Apply To",
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final location in _locations)
                      ChoiceChip(
                        label: Text(location.label),
                        selected: wallpaperLocation == location.value,
                        onSelected: (_) => _setLocation(location.value),
                        selectedColor: scheme.primary.withValues(alpha: 0.2),
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildTagSection(scheme),
                const Divider(),

                SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Automate Wallpaper",
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Switch(
                      value: _autoWallpaperEnabled,
                      onChanged: _setAutoWallpaper,
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                if (_autoWallpaperEnabled)
                  _buildWallpaperSettings(context, scheme),
                const SizedBox(height: 8),
                ListTile(
                  leading: Icon(
                    Icons.battery_saver,
                    color: _batteryOptimized ? Colors.green : Colors.orange,
                  ),
                  title: const Text("Battery Optimization"),
                  subtitle: Text(
                    _batteryOptimized
                        ? "Wallify is exempt from battery restrictions"
                        : "Exempt the app so auto wallpaper changes run reliably",
                  ),
                  trailing: FilledButton.tonal(
                    onPressed: _requestBatteryOptimization,
                    child: Text(_batteryOptimized ? "Exempted" : "Exempt"),
                  ),
                ),
                const Divider(),
                // ========== THEME TOGGLE ==========
                Text(
                  "Appearance",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: Icon(Icons.brightness_6, color: scheme.primary),
                  title: const Text("Dark Theme"),
                  subtitle: const Text("Switch between light and dark mode"),
                  trailing: Switch(
                    value: isDark,
                    onChanged: (val) {
                      ref.read(themeProvider.notifier).toggleTheme(val);
                    },
                    activeThumbColor: scheme.secondary,
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.palette, color: scheme.primary),
                  title: const Text("Use Monet Theme"),
                  subtitle: const Text("Derive colors from current wallpaper"),
                  trailing: Switch(
                    value:
                        ref
                            .watch(monetThemeProvider)
                            .whenOrNull(data: (v) => v) ??
                        false,
                    onChanged: (val) =>
                        ref.read(monetThemeProvider.notifier).set(val),
                    activeThumbColor: scheme.secondary,
                  ),
                ),

                // ========== ERROR REPORTING ==========
                ListTile(
                  leading: Icon(Icons.bug_report, color: scheme.primary),
                  title: const Text("Error Reporting"),
                  subtitle: const Text(
                    "Send crash reports to help improve the app",
                  ),
                  trailing: Switch(
                    value: _errorReportingEnabled,
                    onChanged: _setErrorReporting,
                    activeThumbColor: scheme.secondary,
                  ),
                ),
                const Divider(),

                // ========== EXPORT / IMPORT ==========
                SizedBox(height: 16),
                Text("Data", style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                ListTile(
                  enabled: !_backupBusy,
                  leading: Icon(Icons.upload_file, color: scheme.primary),
                  title: const Text("Export Settings"),
                  subtitle: const Text(
                    "Tags, favorites, history, settings and optionally API keys",
                  ),
                  onTap: _exportSettings,
                ),
                ListTile(
                  enabled: !_backupBusy,
                  leading: Icon(Icons.download, color: scheme.primary),
                  title: const Text("Import Settings"),
                  subtitle: const Text("Restore from a Wallify backup"),
                  trailing: _backupBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: _importSettings,
                ),
                const Divider(),
                SizedBox(height: 16),

                // ========== API KEYS ==========
                Text(
                  "API Keys",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                _ApiKeyGuideRow(
                  text: "Free key at pexels.com/api",
                  url: "https://www.pexels.com/api/",
                  scheme: scheme,
                ),
                const SizedBox(height: 4),
                _ApiKeyField(
                  key: ValueKey("pexels_$_apiKeysVersion"),
                  label: "Pexels API Key",
                  hint: "Paste your key",
                  isSecret: true,
                  load: () => UserSharedPrefs.getPexelsApiKey(),
                  save: (v) => UserSharedPrefs.setPexelsApiKey(v),
                  test: _testPexelsKey,
                  scheme: scheme,
                ),
                _ApiKeyCaption(
                  text: "Adds Pexels photos to Discover.",
                  scheme: scheme,
                ),
                const SizedBox(height: 12),
                _ApiKeyGuideRow(
                  text: "Free key at pixabay.com/api",
                  url: "https://pixabay.com/api/docs/",
                  scheme: scheme,
                ),
                const SizedBox(height: 4),
                _ApiKeyField(
                  key: ValueKey("pixabay_$_apiKeysVersion"),
                  label: "Pixabay API Key",
                  hint: "Paste your key",
                  isSecret: true,
                  load: () => UserSharedPrefs.getPixabayApiKey(),
                  save: (v) => UserSharedPrefs.setPixabayApiKey(v),
                  test: _testPixabayKey,
                  scheme: scheme,
                ),
                _ApiKeyCaption(
                  text: "More wallpapers for Discover and auto-change.",
                  scheme: scheme,
                ),
                const SizedBox(height: 12),
                _ApiKeyGuideRow(
                  text: "Free key at unsplash.com/developers",
                  url: "https://unsplash.com/oauth/applications",
                  scheme: scheme,
                ),
                const SizedBox(height: 4),
                _ApiKeyField(
                  key: ValueKey("unsplash_$_apiKeysVersion"),
                  label: "Unsplash Access Key",
                  hint: "Access Key, not Secret Key",
                  isSecret: true,
                  load: () => UserSharedPrefs.getUnsplashApiKey().then((v) =>
                      v == UserSharedPrefs.defaultUnsplashKey ? null : v),
                  save: (v) => UserSharedPrefs.setUnsplashApiKey(v),
                  test: _testUnsplashKey,
                  scheme: scheme,
                ),
                _ApiKeyCaption(
                  text: "Optional. Works with a demo key; yours avoids limits.",
                  scheme: scheme,
                ),
                const SizedBox(height: 12),
                _ApiKeyGuideRow(
                  text: "Free key at aistudio.google.com",
                  url: "https://aistudio.google.com/apikey",
                  scheme: scheme,
                ),
                const SizedBox(height: 4),
                _ApiKeyField(
                  key: ValueKey("gemini_$_apiKeysVersion"),
                  label: "Gemini API Key",
                  hint: "Paste your key",
                  isSecret: true,
                  load: () => UserSharedPrefs.getGeminiApiKey(),
                  save: (v) => UserSharedPrefs.setGeminiApiKey(v),
                  test: _testGeminiKey,
                  scheme: scheme,
                ),
                _ApiKeyCaption(
                  text: "Powers AI Magic in the preview.",
                  scheme: scheme,
                ),
                const SizedBox(height: 8),

                const Divider(),
                SizedBox(height: 16),

                // ========== CHECK UPDATE ==========
                if (!Config.isFdroidBuild) ListTile(
                  leading: Icon(
                    _updateAvailable ? Icons.update : Icons.system_update,
                    color: scheme.primary,
                  ),
                  title: _checkingUpdate
                      ? const Text("Checking for updates...")
                      : _updateAvailable
                      ? Text(
                          "Update Available",
                          style: TextStyle(color: scheme.primary),
                        )
                      : const Text("Up to date"),
                  subtitle: _checkingUpdate
                      ? null
                      : _updateAvailable
                      ? Text(
                          "v${Config.getCachedLatestVersion()} is ready to download",
                        )
                      : const Text("You're on the latest version"),
                  trailing: _checkingUpdate
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.primary,
                          ),
                        )
                      : _updateAvailable
                      ? FilledButton(
                          onPressed: () =>
                              UpdateManager.showUpdateDialog(context),
                          child: const Text("Update"),
                        )
                      : null,
                  onTap: _updateAvailable
                      ? () => UpdateManager.showUpdateDialog(context)
                      : null,
                ),

                const SizedBox(height: 8),
                Center(
                  child: Text(
                    "Version ${Config.getAppVersion()}",
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Divider(),
                _buildStorageSection(scheme),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                _buildSupportSection(),
                const SizedBox(height: 80),
              ],
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: widget.isNavBarVisible ? 20 : 4,
              child: Stack(
                // Hands the full width on to the button, as before the Stack.
                fit: StackFit.passthrough,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      // Stay in full colour while busy so the progress is visible.
                      disabledBackgroundColor: scheme.primary,
                      disabledForegroundColor: scheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _changingNow ? null : changeWallpaper,
                    icon: _changingNow
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.onPrimary,
                            ),
                          )
                        : const Icon(Icons.wallpaper),
                    label: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        _changeStatus ?? "Change Now",
                        key: ValueKey(_changeStatus),
                      ),
                    ),
                  ),
                  if (_changingNow)
                    Positioned(
                      left: 32,
                      right: 32,
                      bottom: 5,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          minHeight: 3,
                          color: scheme.onPrimary,
                          backgroundColor: scheme.onPrimary.withValues(alpha: 0.25),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagSection(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tagController,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: "Enter a tag",
                  helperText: "Separate several tags with commas",
                  fillColor: scheme.surfaceContainerHighest,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onSubmitted: _addTags,
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              // Line up with the field rather than its helper text.
              padding: const EdgeInsets.only(bottom: 20),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                ),
                onPressed: () => _addTags(_tagController.text),
                child: const Text("Add"),
              ),
            ),
          ],
        ),
        if (savedTags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in savedTags)
                _TagChip(
                  key: ValueKey(tag),
                  tag: tag,
                  invalid: _invalidTags.contains(tag),
                  checking: _checkingTags.contains(tag),
                  scheme: scheme,
                  onRecheck: () => _validateTag(tag),
                  onDelete: () => _removeTag(tag),
                ),
            ],
          ),
          if (_invalidTags.any(savedTags.contains)) ...[
            const SizedBox(height: 6),
            Text(
              "Red tags have no wallpapers in any source and are skipped. "
              "Tap one to check again.",
              style: TextStyle(fontSize: 12, color: scheme.error),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildWallpaperSettings(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                "Auto Change Interval (minutes):",
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 120,
              child: TextField(
                controller: _intervalController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: _onIntervalChanged,
                onSubmitted: _applyInterval,
                onTapOutside: (_) {
                  FocusManager.instance.primaryFocus?.unfocus();
                  _applyInterval(_intervalController.text);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          "Wallpaper Source",
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final source in _sourceLabels.keys)
              FilterChip(
                label: Text(_sourceLabels[source]!),
                selected: _wallpaperSources.contains(source),
                onSelected: (selected) => _toggleSource(source, selected),
                selectedColor: scheme.primaryContainer,
                backgroundColor: scheme.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                showCheckmark: true,
                shape: StadiumBorder(
                  side: BorderSide(
                    color: _wallpaperSources.contains(source)
                        ? Colors.transparent
                        : scheme.outlineVariant,
                  ),
                ),
              ),
          ],
        ),
        if (_wallpaperSources.contains("toppicks")) ...[
          const SizedBox(height: 12),
          Text(
            "The best-rated wallpapers from every source, ignoring your tags.",
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final entry in _topPicksRangeLabels.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: _topPicksRange == entry.key,
                  onSelected: (_) => _setTopPicksRange(entry.key),
                  selectedColor: scheme.primary.withValues(alpha: 0.2),
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
            ],
          ),
        ],
        if (_wallpaperSources.contains("folder")) ...[
          const SizedBox(height: 12),
          ..._folderPaths.map((path) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    path,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, size: 18, color: scheme.onSurfaceVariant),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _setFolders(
                    _folderPaths.where((p) => p != path).toList(),
                  ),
                ),
              ],
            ),
          )),
          if (_folderPaths.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                "No folders selected",
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: () async {
              final path = await FilePicker.getDirectoryPath();
              if (path != null && !_folderPaths.contains(path)) {
                await _setFolders([..._folderPaths, path]);
              }
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text("Add Folder"),
          ),
        ],
        const SizedBox(height: 8),
        _buildConstraintsChipSection(context),
        const SizedBox(height: 20),
        if (_lastChange != null)
          Row(
            children: [
              Icon(
                Icons.history,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                "Last changed: ${DateFormat("MMM d, h:mm a").format(_lastChange!)}",
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.bolt,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  "Next change approx. after ${DateFormat("MMM d, h:mm a").format((_lastChange ?? DateTime.now()).add(Duration(minutes: _intervalMinutes)))} when device meets constraints",
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildConstraintsChipSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          "Automation Constraints",
          style: Theme.of(context).textTheme.titleMedium,
        ),

        const SizedBox(height: 12),

        Wrap(
          spacing: 8,
          children: _constraints.map((c) {
            final isSelected = _constraintValues[c.key] ?? false;

            return ChoiceChip(
              label: Text(
                c.label,
                style: TextStyle(
                  color: isSelected
                      ? scheme.onPrimary
                      : scheme.onSurfaceVariant,
                ),
              ),
              selected: isSelected,
              selectedColor: scheme.primary,
              backgroundColor: scheme.surfaceContainerHighest,
              onSelected: (selected) => _setConstraint(c.key, selected),
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              showCheckmark: false,
              shape: StadiumBorder(
                side: BorderSide(
                  color: isSelected
                      ? Colors.transparent
                      : scheme.outlineVariant,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Text(
          "Auto change runs on the interval above whenever all selected constraints are met. Charging means plugged in.",
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildStorageSection(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.cleaning_services_outlined,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                "Storage",
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  "Cached wallpapers & images: ${_cacheSize != null ? _formatBytes(_cacheSize!) : "…"}",
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _clearAllCaches,
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text("Clear Cache"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static final _coffeeUrl = Uri.parse("https://ko-fi.com/ruchan10");
  static final _sourceUrl = Uri.parse("https://github.com/Ruchan10/Wallify");

  Future<void> _openLink(Uri url) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication) && mounted) {
      showSnackBar(
        context: context,
        color: Colors.red,
        message: "Couldn't open ${url.host}",
      );
    }
  }

  Widget _buildSupportSection() {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              // Ko-fi's brand red, readable in light and dark themes.
              backgroundColor: const Color(0xFFFF5E5B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: () => _openLink(_coffeeUrl),
            icon: const Icon(Icons.coffee_rounded),
            label: const Text("Buy me a coffee"),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: () => _openLink(_sourceUrl),
            icon: const Icon(Icons.code_rounded),
            label: const Text("View source code"),
          ),
        ),
      ],
    );
  }
}

/// A saved tag. Red when no source has wallpapers for it; shows a spinner
/// while that is being checked.
class _TagChip extends StatelessWidget {
  final String tag;
  final bool invalid;
  final bool checking;
  final ColorScheme scheme;
  final VoidCallback onRecheck;
  final VoidCallback onDelete;

  const _TagChip({
    super.key,
    required this.tag,
    required this.invalid,
    required this.checking,
    required this.scheme,
    required this.onRecheck,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final red = Colors.red.shade400;
    return InputChip(
      label: Text(tag),
      avatar: checking
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            )
          : invalid
          ? Icon(Icons.error_outline, size: 18, color: red)
          : null,
      tooltip: invalid ? "No wallpapers found. Tap to check again" : null,
      onPressed: checking ? null : onRecheck,
      deleteIcon: Icon(Icons.close, color: scheme.onSurfaceVariant),
      onDeleted: onDelete,
      backgroundColor: invalid
          ? Colors.red.withValues(alpha: 0.1)
          : scheme.surfaceContainerHighest,
      shape: StadiumBorder(
        side: invalid
            ? BorderSide(color: red, width: 2)
            : BorderSide(color: scheme.outlineVariant),
      ),
    );
  }
}

/// Confirmation dialog with an optional "include API keys" checkbox. Pops
/// null when cancelled, otherwise whether keys should be included.
class _IncludeKeysDialog extends StatefulWidget {
  final String title;
  final String message;

  /// Checkbox label, or null to hide the checkbox.
  final String? keysLabel;
  final String keysWarning;
  final String confirmLabel;

  const _IncludeKeysDialog({
    required this.title,
    required this.message,
    required this.keysLabel,
    required this.keysWarning,
    required this.confirmLabel,
  });

  @override
  State<_IncludeKeysDialog> createState() => _IncludeKeysDialogState();
}

class _IncludeKeysDialogState extends State<_IncludeKeysDialog> {
  bool _includeKeys = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message),
            if (widget.keysLabel != null) ...[
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _includeKeys,
                onChanged: (v) => setState(() => _includeKeys = v ?? false),
                title: Text(widget.keysLabel!),
                subtitle: Text(
                  widget.keysWarning,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, widget.keysLabel != null && _includeKeys),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}


final _testPexelsKey = WallpaperApiService.testPexelsKey;
final _testPixabayKey = WallpaperApiService.testPixabayKey;
final _testUnsplashKey = WallpaperApiService.testUnsplashKey;
final _testGeminiKey = WallpaperApiService.testGeminiKey;

class _ApiKeyCaption extends StatelessWidget {
  final String text;
  final ColorScheme scheme;

  const _ApiKeyCaption({required this.text, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3, left: 12, right: 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ApiKeyGuideRow extends StatelessWidget {
  final String text;
  final String url;
  final ColorScheme scheme;

  const _ApiKeyGuideRow({
    required this.text,
    required this.url,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        SizedBox(
          width: 28,
          height: 28,
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(Icons.open_in_new, size: 14, color: scheme.primary),
            onPressed: () async {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            tooltip: "Open link",
          ),
        ),
      ],
    );
  }
}

class _ApiKeyField extends StatefulWidget {
  final String label;
  final String hint;
  final bool isSecret;
  final Future<String?> Function() load;
  final Future<void> Function(String?) save;
  final Future<bool> Function(String key) test;
  final ColorScheme scheme;

  const _ApiKeyField({
    super.key,
    required this.label,
    required this.hint,
    required this.isSecret,
    required this.load,
    required this.save,
    required this.test,
    required this.scheme,
  });

  @override
  State<_ApiKeyField> createState() => _ApiKeyFieldState();
}

class _ApiKeyFieldState extends State<_ApiKeyField> {
  final TextEditingController _controller = TextEditingController();
  bool _obscured = true;
  bool _loaded = false;

  bool _testing = false;
  bool? _testPassed;
  String? _testMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      widget.load().then((v) {
        if (!mounted) return;
        if (v != null && v.isNotEmpty) {
          _controller.text = v;
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _runTest() async {
    final key = _controller.text.trim();
    if (key.isEmpty) {
      setState(() {
        _testPassed = false;
        _testMessage = "Enter an API key first";
      });
      return;
    }
    setState(() {
      _testing = true;
      _testPassed = null;
      _testMessage = null;
    });
    bool ok = false;
    String message = "Request failed";
    try {
      ok = await widget.test(key);
      message = ok ? "Key is working" : "Invalid key or API rejected it";
    } catch (e) {
      message = "Request failed: $e";
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testPassed = ok;
      _testMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Color? tintColor = _testPassed == true
        ? Colors.green
        : _testPassed == false
            ? Colors.red
            : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: tintColor == null
            ? widget.scheme.surfaceContainerHighest
            : tintColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: tintColor == null
            ? null
            : Border.all(color: tintColor.withValues(alpha: 0.7), width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              obscureText: widget.isSecret && _obscured,
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: widget.hint,
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: TextStyle(fontSize: 14),
              onChanged: (v) {
                if (_testPassed != null || _testing) {
                  setState(() {
                    _testPassed = null;
                    _testing = false;
                    _testMessage = null;
                  });
                }
                widget.save(v.trim());
              },
            ),
          ),
          IconButton(
            icon: _testing
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: widget.scheme.primary,
                    ),
                  )
                : Icon(
                    _testPassed == true
                        ? Icons.check_circle
                        : _testPassed == false
                            ? Icons.cancel
                            : Icons.bolt,
                    size: 20,
                    color: _testPassed == true
                        ? Colors.green
                        : _testPassed == false
                            ? Colors.red
                            : widget.scheme.primary,
                  ),
            tooltip: _testMessage ?? "Test API key",
            onPressed: _testing ? null : _runTest,
            visualDensity: VisualDensity.compact,
          ),
          if (widget.isSecret)
            IconButton(
              icon: Icon(
                _obscured ? Icons.visibility_off : Icons.visibility,
                size: 20,
              ),
              onPressed: () => setState(() => _obscured = !_obscured),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

