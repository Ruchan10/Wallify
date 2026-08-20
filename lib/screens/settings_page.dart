import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' hide Config;
import 'package:http/http.dart' as http;
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
import 'package:wallpaper_manager_flutter/wallpaper_manager_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsPage extends ConsumerStatefulWidget {
  final bool isNavBarVisible;
  const SettingsPage({super.key, required this.isNavBarVisible});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage>
    with WidgetsBindingObserver {
  final TextEditingController _tagController = TextEditingController();

  List<String> savedTags = [];
  Set<String> _invalidTags = {};
  int wallpaperLocation = WallpaperManagerFlutter.bothScreens;

  int _intervalMinutes = 60;
  final TextEditingController _intervalController = TextEditingController(
    text: "60",
  );
  static const platform = MethodChannel('wallpaper_channel');
  bool _autoWallpaperEnabled = false;
  List<String> _wallpaperSources = ["internet"];
  bool _scheduleEnabled = false;
  List<int> _scheduleDays = [1, 2, 3, 4, 5, 6, 7];
  int _scheduleStartHour = 6;
  int _scheduleEndHour = 22;

  List<String> _folderPaths = [];
  bool _updateAvailable = false;
  bool _checkingUpdate = true;

  List<Map<String, String>> _workerLogs = [];
  bool _logsExpanded = false;

  int _cacheSize = 0;
  bool _batteryOptimized = false;

  @override
  void initState() {
    super.initState();
    _initialize();
    _checkUpdateStatus();
    WidgetsBinding.instance.addObserver(this);
    _loadWorkerLogs();
    _loadCacheSize();
    _loadBatteryStatus();
  }

  Future<int> _dirSize(Directory dir) async {
    if (!dir.existsSync()) return 0;
    int total = 0;
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) total += entity.statSync().size;
      }
    } catch (_) {}
    return total;
  }

  Future<void> _loadCacheSize() async {
    try {
      final temp = await getTemporaryDirectory();
      final sizes = await Future.wait([
        _dirSize(Directory('${temp.path}/libCachedImageData')),
        _dirSize(Directory('${temp.path}/wallify_cache')),
        WallpaperCacheManager.getCacheSizeBytes(),
      ]);
      if (mounted) {
        setState(() => _cacheSize = sizes.fold(0, (a, b) => a + b));
      }
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
      await DefaultCacheManager().emptyCache();
      await PerformanceConfig.cacheManager.emptyCache();
      await WallpaperCacheManager.clearCache();
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

  Future<void> _loadWorkerLogs() async {
    try {
      final logs = await platform.invokeMethod("getWorkerLogs");
      if (logs is List) {
        setState(() {
          _workerLogs = logs.map((e) => Map<String, String>.from(e as Map)).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _clearWorkerLogs() async {
    try {
      await platform.invokeMethod("clearWorkerLogs");
      setState(() => _workerLogs.clear());
    } catch (_) {}
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
    _autoWallpaperEnabled = await UserSharedPrefs.getAutoWallpaperEnabled();
    savedTags = await UserSharedPrefs.getTags();
    _invalidTags = await UserSharedPrefs.getInvalidTags();
    wallpaperLocation = await UserSharedPrefs.getWallpaperLocation();
    _intervalMinutes = await UserSharedPrefs.getInterval();
    _intervalController.text = _intervalMinutes.toString();
    _wallpaperSources = await UserSharedPrefs.getWallpaperSources();
    _folderPaths = await UserSharedPrefs.getFolderPaths();
    _scheduleEnabled = await UserSharedPrefs.getScheduleEnabled();
    _scheduleDays = await UserSharedPrefs.getScheduleDays();
    _scheduleStartHour = await UserSharedPrefs.getScheduleStartHour();
    _scheduleEndHour = await UserSharedPrefs.getScheduleEndHour();

    setState(() {});
    if (_autoWallpaperEnabled) {
      await platform.invokeMethod("scheduleBackgroundWallpaperWorker");
    }
  }

  Future<void> changeWallpaper({bool changeNow = false}) async {
    try {
      // Pre-cache wallpapers from selected sources before triggering native change.
      if (_wallpaperSources.contains("internet") ||
          _wallpaperSources.contains("favorites")) {
        final fetched = await WallpaperManager.fetchImagesFromAllSources(
          sources: _wallpaperSources,
        );
        await UserSharedPrefs.saveWallpapers(fetched);
        WallpaperCacheManager.cacheWallpapers(fetched);
      }
      await platform.invokeMethod("scheduleBackgroundWallpaperWorkerNow");
      await updateWidget();
      if (mounted) {
        showSnackBar(
          context: context,
          color: Colors.green,
          message: "Wallpaper changed",
        );
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context: context, color: Colors.red, message: "Error: $e");
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void resetAutoWallpaper() async {
    await platform.invokeMethod("scheduleBackgroundWallpaperWorker");
  }

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
                    ChoiceChip(
                      label: const Text("Home"),
                      selected:
                          wallpaperLocation ==
                          WallpaperManagerFlutter.homeScreen,
                      onSelected: (_) {
                        setState(
                          () => wallpaperLocation =
                              WallpaperManagerFlutter.homeScreen,
                        );
                        UserSharedPrefs.saveWallpaperLocation(
                          wallpaperLocation,
                        );
                        resetAutoWallpaper();
                        updateWidget();
                      },
                      selectedColor: scheme.primary.withValues(alpha: 0.2),
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                    ChoiceChip(
                      label: const Text("Lock"),
                      selected:
                          wallpaperLocation ==
                          WallpaperManagerFlutter.lockScreen,
                      onSelected: (_) {
                        setState(
                          () => wallpaperLocation =
                              WallpaperManagerFlutter.lockScreen,
                        );
                        UserSharedPrefs.saveWallpaperLocation(
                          wallpaperLocation,
                        );
                        resetAutoWallpaper();
                        updateWidget();
                      },
                      selectedColor: scheme.primary.withValues(alpha: 0.2),
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                    ChoiceChip(
                      label: const Text("Both"),
                      selected:
                          wallpaperLocation ==
                          WallpaperManagerFlutter.bothScreens,
                      onSelected: (_) {
                        setState(
                          () => wallpaperLocation =
                              WallpaperManagerFlutter.bothScreens,
                        );
                        UserSharedPrefs.saveWallpaperLocation(
                          wallpaperLocation,
                        );
                        resetAutoWallpaper();
                        updateWidget();
                      },
                      selectedColor: scheme.primary.withValues(alpha: 0.2),
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                    ChoiceChip(
                      label: const Text("Auto"),
                      selected: wallpaperLocation == 4,
                      onSelected: (_) {
                        setState(() => wallpaperLocation = 4);
                        UserSharedPrefs.saveWallpaperLocation(
                          wallpaperLocation,
                        );
                        resetAutoWallpaper();
                        updateWidget();
                      },
                      selectedColor: scheme.primary.withValues(alpha: 0.2),
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tagController,
                        decoration: InputDecoration(
                          labelText: "Enter a tag",
                          fillColor: scheme.surfaceContainerHighest,
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onSubmitted: (value) async {
                          if (value.isNotEmpty && !savedTags.contains(value)) {
                            setState(() => savedTags.add(value));
                            UserSharedPrefs.saveTags(savedTags);
                            final valid = await WallpaperManager.validateTag(
                              value,
                            );
                            if (!valid) {
                              setState(() => _invalidTags.add(value));
                              UserSharedPrefs.saveInvalidTags(_invalidTags);
                            }
                          }
                          _tagController.clear();
                          final fetched =
                              await WallpaperManager.fetchImagesFromAllSources(
                                sources: _wallpaperSources,
                              );
                          await UserSharedPrefs.saveWallpapers(fetched);
                          WallpaperCacheManager.cacheWallpapers(fetched);
                          resetAutoWallpaper();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                      ),
                      onPressed: () async {
                        if (_tagController.text.isNotEmpty &&
                            !savedTags.contains(_tagController.text)) {
                          final tag = _tagController.text;
                          setState(() => savedTags.add(tag));
                          UserSharedPrefs.saveTags(savedTags);
                          final valid = await WallpaperManager.validateTag(tag);
                          if (!valid) {
                            setState(() => _invalidTags.add(tag));
                            UserSharedPrefs.saveInvalidTags(_invalidTags);
                          }
                        }
                        _tagController.clear();
                        final fetched =
                            await WallpaperManager.fetchImagesFromAllSources(
                              sources: _wallpaperSources,
                            );
                        await UserSharedPrefs.saveWallpapers(fetched);
                        WallpaperCacheManager.cacheWallpapers(fetched);
                        resetAutoWallpaper();
                      },
                      child: const Text("Add"),
                    ),
                  ],
                ),
                if (savedTags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    children: savedTags.map((tag) {
                      final isInvalid = _invalidTags.contains(tag);
                      return Chip(
                        label: Text(tag),
                        deleteIcon: Icon(
                          Icons.close,
                          color: scheme.onSurfaceVariant,
                        ),
                        backgroundColor: isInvalid
                            ? Colors.red.withValues(alpha: 0.1)
                            : scheme.surfaceContainerHighest,
                        shape: isInvalid
                            ? StadiumBorder(
                                side: BorderSide(
                                  color: Colors.red.shade300,
                                  width: 2,
                                ),
                              )
                            : null,
                        onDeleted: () async {
                          setState(() {
                            savedTags.remove(tag);
                            _invalidTags.remove(tag);
                          });
                          UserSharedPrefs.saveTags(savedTags);
                          UserSharedPrefs.saveInvalidTags(_invalidTags);
                          final fetched =
                              await WallpaperManager.fetchImagesFromAllSources(
                                sources: _wallpaperSources,
                              );
                          await UserSharedPrefs.saveWallpapers(fetched);
                          WallpaperCacheManager.cacheWallpapers(fetched);
                          resetAutoWallpaper();
                        },
                      );
                    }).toList(),
                  ),
                ],
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
                      onChanged: (value) async {
                        if (_wallpaperSources.contains("internet")) {
                          final fetched =
                              await WallpaperManager.fetchImagesFromAllSources(
                                sources: _wallpaperSources,
                              );
                          await UserSharedPrefs.saveWallpapers(fetched);
                          WallpaperCacheManager.cacheWallpapers(fetched);
                        }
                        setState(() => _autoWallpaperEnabled = value);

                        if (value) {
                          try {
                            await platform.invokeMethod(
                              "scheduleBackgroundWallpaperWorker",
                            );
                            showSnackBar(
                              context: context,
                              message: "Auto wallpaper enabled ✅",
                            );
                          } catch (e) {
                            showSnackBar(
                              context: context,
                              color: Colors.red,
                              message: "Failed to enable auto wallpaper: $e",
                            );
                          }
                        } else {
                          try {
                            await platform.invokeMethod(
                              "cancelBackgroundWallpaperWorker",
                            );
                            showSnackBar(
                              color: Colors.red,
                              context: context,
                              message: "Auto wallpaper disabled 🚫",
                            );
                          } catch (e) {
                            showSnackBar(
                              color: Colors.red,
                              context: context,
                              message: "Failed to disable automation: $e",
                            );
                          }
                        }
                        await UserSharedPrefs.setAutoWallpaperEnabled(value);
                        updateWidget();
                      },
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
                    onChanged: (val) async {
                      await UserSharedPrefs.setUseMonetTheme(val);
                      ref.invalidate(monetThemeProvider);
                      ref.invalidate(wallpaperThemeProvider);
                    },
                    activeThumbColor: scheme.secondary,
                  ),
                ),

                // ========== ERROR REPORTING ==========
                FutureBuilder<bool>(
                  future: UserSharedPrefs.getErrorReportingEnabled(),
                  builder: (context, snapshot) {
                    final isEnabled = snapshot.data ?? false;
                    return ListTile(
                      leading: Icon(Icons.bug_report, color: scheme.primary),
                      title: const Text("Error Reporting"),
                      subtitle: const Text(
                        "Send crash reports to help improve the app",
                      ),
                      trailing: Switch(
                        value: isEnabled,
                        onChanged: (val) async {
                          await UserSharedPrefs.setErrorReportingEnabled(val);
                          setState(() {});
                          if (mounted) {
                            showSnackBar(
                              context: context,
                              message: val
                                  ? "Error reporting enabled"
                                  : "Error reporting disabled",
                            );
                          }
                        },
                        activeThumbColor: scheme.secondary,
                      ),
                    );
                  },
                ),
                const Divider(),

                // ========== EXPORT / IMPORT ==========
                SizedBox(height: 16),
                Text("Data", style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                ListTile(
                  leading: Icon(Icons.upload_file, color: scheme.primary),
                  title: const Text("Export Settings"),
                  onTap: () async {
                    try {
                      final file = await SettingsBackup.exportSettings();
                      if (mounted) {
                        showSnackBar(
                          context: context,
                          color: Colors.green,
                          message: "Exported to ${file.path}",
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        print("Export failed: $e");
                        showSnackBar(
                          context: context,
                          color: Colors.red,
                          message: "Export failed: $e",
                        );
                      }
                    }
                  },
                ),
                ListTile(
                  leading: Icon(Icons.download, color: scheme.primary),
                  title: const Text("Import Settings"),
                  onTap: () async {
                    try {
                      final result = await FilePicker.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['json'],
                      );
                      if (result != null && result.files.single.path != null) {
                        final file = File(result.files.single.path!);
                        final count = await SettingsBackup.importSettings(file);

                        await _initialize();

                        if (mounted) {
                          showSnackBar(
                            context: context,
                            color: Colors.green,
                            message: "Imported $count settings successfully",
                          );
                        }
                      }
                    } catch (e) {
                      if (mounted) {
                        showSnackBar(
                          context: context,
                          color: Colors.red,
                          message: "Import failed: $e",
                        );
                      }
                    }
                  },
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
                  text: "Get a free Pexels API key at pexels.com/api",
                  url: "https://www.pexels.com/api/",
                  scheme: scheme,
                ),
                const SizedBox(height: 4),
                _ApiKeyField(
                  label: "Pexels API Key",
                  hint: "API key from pexels.com/api",
                  isSecret: true,
                  load: () => UserSharedPrefs.getPexelsApiKey(),
                  save: (v) => UserSharedPrefs.setPexelsApiKey(v),
                  test: _testPexelsKey,
                  scheme: scheme,
                ),
                _ApiKeyCaption(
                  text: "Adds Pexels photos to the Discover tab.",
                  scheme: scheme,
                ),
                const SizedBox(height: 12),
                _ApiKeyGuideRow(
                  text: "Get a free Pixabay API key at pixabay.com/api",
                  url: "https://pixabay.com/api/docs/",
                  scheme: scheme,
                ),
                const SizedBox(height: 4),
                _ApiKeyField(
                  label: "Pixabay API Key",
                  hint: "API key from pixabay.com/api",
                  isSecret: true,
                  load: () => UserSharedPrefs.getPixabayApiKey(),
                  save: (v) => UserSharedPrefs.setPixabayApiKey(v),
                  test: _testPixabayKey,
                  scheme: scheme,
                ),
                _ApiKeyCaption(
                  text:
                      "Provides wallpapers for Discover, automatic wallpaper "
                      "changes, and image info.",
                  scheme: scheme,
                ),
                const SizedBox(height: 12),
                _ApiKeyGuideRow(
                  text: "Get a free Unsplash API key at unsplash.com/oauth/applications",
                  url: "https://unsplash.com/oauth/applications",
                  scheme: scheme,
                ),
                const SizedBox(height: 4),
                _ApiKeyField(
                  label: "Unsplash Access Key",
                  hint: "Use the Access Key, not the Secret Key",
                  isSecret: true,
                  load: () => UserSharedPrefs.getUnsplashApiKey().then((v) =>
                      v == UserSharedPrefs.defaultUnsplashKey ? null : v),
                  save: (v) => UserSharedPrefs.setUnsplashApiKey(v),
                  test: _testUnsplashKey,
                  scheme: scheme,
                ),
                _ApiKeyCaption(
                  text:
                      "Provides wallpapers for Discover, automatic wallpaper "
                      "changes, and image info. A built-in demo key works, "
                      "but adding your own is unlimited.",
                  scheme: scheme,
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    "Paste the Access Key from your Unsplash app "
                    "(under the \"Keys\" tab). The Secret Key is only for "
                    "OAuth login and should never be shared.",
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _ApiKeyGuideRow(
                  text: "Get a free Gemini API key at aistudio.google.com",
                  url: "https://aistudio.google.com/apikey",
                  scheme: scheme,
                ),
                const SizedBox(height: 4),
                _ApiKeyField(
                  label: "Google Gemini API Key",
                  hint: "Free key from aistudio.google.com (vision analysis)",
                  isSecret: true,
                  load: () => UserSharedPrefs.getGeminiApiKey(),
                  save: (v) => UserSharedPrefs.setGeminiApiKey(v),
                  test: _testGeminiKey,
                  scheme: scheme,
                ),
                _ApiKeyCaption(
                  text:
                      "Enables AI Magic in the wallpaper preview to redesign "
                      "wallpapers with Gemini.",
                  scheme: scheme,
                ),
                const SizedBox(height: 8),

                const Divider(),
                SizedBox(height: 16),

                // ========== CHECK UPDATE ==========
                ListTile(
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
                _buildLogViewer(scheme),
                const SizedBox(height: 80),
              ],
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: widget.isNavBarVisible ? 20 : 4,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => changeWallpaper(changeNow: true),
                icon: const Icon(Icons.wallpaper),
                label: const Text("Change Now"),
              ),
            ),
          ],
        ),
      ),
    );
  }


  static const _dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

  Widget _buildScheduleSection(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text("Schedule", style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            Switch(
              value: _scheduleEnabled,
              onChanged: (v) async {
                setState(() => _scheduleEnabled = v);
                await UserSharedPrefs.setScheduleEnabled(v);
              },
            ),
          ],
        ),
        if (_scheduleEnabled) ...[
          const SizedBox(height: 8),
          Text("Active Days", style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: List.generate(7, (i) {
              final day = i + 1;
              final selected = _scheduleDays.contains(day);
              return ChoiceChip(
                label: Text(_dayLabels[i], style: const TextStyle(fontSize: 12)),
                selected: selected,
                selectedColor: scheme.primary.withValues(alpha: 0.25),
                backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                onSelected: (v) async {
                  setState(() {
                    if (v) {
                      _scheduleDays.add(day);
                    } else {
                      _scheduleDays.remove(day);
                    }
                    if (_scheduleDays.isEmpty) _scheduleDays.add(day);
                  });
                  await UserSharedPrefs.setScheduleDays(_scheduleDays);
                  resetAutoWallpaper();
                },
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              );
            }),
          ),
          const SizedBox(height: 12),
          Text("Time Range", style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Row(
            children: [
              Text("From", style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: _TimePickerChip(
                  value: _scheduleStartHour,
                  onChanged: (v) async {
                    setState(() => _scheduleStartHour = v);
                    await UserSharedPrefs.setScheduleStartHour(v);
                    resetAutoWallpaper();
                  },
                  scheme: scheme,
                ),
              ),
              const Spacer(),
              Text("To", style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: _TimePickerChip(
                  value: _scheduleEndHour,
                  onChanged: (v) async {
                    setState(() => _scheduleEndHour = v);
                    await UserSharedPrefs.setScheduleEndHour(v);
                    resetAutoWallpaper();
                  },
                  scheme: scheme,
                ),
              ),
            ],
          ),
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
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) {
                  final minutes = int.tryParse(value);
                  if (minutes != null && minutes >= 15) {
                    setState(() => _intervalMinutes = minutes);
                    UserSharedPrefs.saveInterval(minutes);
                    updateWidget();
                    resetAutoWallpaper();
                  } else if (minutes != null && minutes > 0 && minutes < 15) {
                    showSnackBar(
                      context: context,
                      color: Colors.orange,
                      message:
                          "Minimum interval is 15 minutes (set to $minutes, will be adjusted)",
                    );
                    setState(() => _intervalMinutes = 15);
                    _intervalController.text = "15";
                    UserSharedPrefs.saveInterval(15);
                    updateWidget();
                    resetAutoWallpaper();
                  } else {
                    _intervalController.text = _intervalMinutes.toString();
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildScheduleSection(scheme),
        const SizedBox(height: 16),
        Text(
          "Wallpaper Source",
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final source in ["internet", "folder", "favorites"])
              FilterChip(
                label: Text(
                  source == "internet"
                      ? "Internet"
                      : source == "folder"
                      ? "Folder"
                      : "Favorites",
                ),
                selected: _wallpaperSources.contains(source),
                onSelected: (selected) async {
                  setState(() {
                    if (selected) {
                      _wallpaperSources.add(source);
                    } else {
                      _wallpaperSources.remove(source);
                    }
                    // Always keep at least one source selected.
                    if (_wallpaperSources.isEmpty) {
                      _wallpaperSources.add("internet");
                    }
                  });
                  await UserSharedPrefs.saveWallpaperSources(_wallpaperSources);
                  resetAutoWallpaper();
                },
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
                  onPressed: () async {
                    setState(() => _folderPaths.remove(path));
                    await UserSharedPrefs.setFolderPaths(_folderPaths);
                    resetAutoWallpaper();
                  },
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
                setState(() => _folderPaths.add(path));
                await UserSharedPrefs.setFolderPaths(_folderPaths);
                resetAutoWallpaper();
              }
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text("Add Folder"),
          ),
        ],
        const SizedBox(height: 8),
        _buildConstraintsChipSection(context),
        const SizedBox(height: 20),
        FutureBuilder<DateTime?>(
          future: UserSharedPrefs.getLastWallpaperChange(),
          builder: (context, snapshot) {
            final lastChange = snapshot.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (lastChange != null)
                  Row(
                    children: [
                      Icon(
                        Icons.history,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "Last changed: ${DateFormat("MMM d, h:mm a").format(lastChange)}",
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
                          "Next change approx. after ${DateFormat("MMM d, h:mm a").format((lastChange ?? DateTime.now()).add(Duration(minutes: _intervalMinutes)))} when device meets constraints",
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
          },
        ),
      ],
    );
  }

  Future<Map<String, bool>> _loadAllConstraintValues(
    List<Map<String, String>> constraints,
  ) async {
    final map = <String, bool>{};
    for (final c in constraints) {
      map[c["key"]!] = await UserSharedPrefs.getBool(c["key"]!);
    }
    return map;
  }

  Widget _buildConstraintsChipSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final constraints = [
      {"key": "constraint_charging", "label": "Charging"},
      {"key": "constraint_battery_not_low", "label": "Battery Not Low"},
      {"key": "constraint_storage_not_low", "label": "Storage Not Low"},
      {"key": "constraint_no_faces", "label": "No Faces"},
    ];

    return FutureBuilder<Map<String, bool>>(
      future: _loadAllConstraintValues(constraints),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final values = snapshot.data!;

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
              children: constraints.map((c) {
                final key = c["key"]!;
                final label = c["label"]!;
                final isSelected = values[key] ?? false;

                return ChoiceChip(
                  label: Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? scheme.onPrimary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: scheme.primary,
                  backgroundColor: scheme.surfaceContainerHighest,
                  onSelected: (selected) async {
                    await UserSharedPrefs.setBool(key, selected);
                    resetAutoWallpaper();
                    setState(() {});
                  },
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
              "Auto wallpaper change runs every time the device is plugged in or on interval if all enabled constraints are met.",
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
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
                  "Cached wallpapers & images: ${_cacheSize > 0 ? _formatBytes(_cacheSize) : "…"}",
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

  Widget _buildLogViewer(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() => _logsExpanded = !_logsExpanded);
            if (_logsExpanded) _loadWorkerLogs();
          },
          child: Row(
            children: [
              Icon(
                _logsExpanded ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Icon(Icons.terminal, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                "Worker Logs (${_workerLogs.length})",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              if (_logsExpanded)
                IconButton(
                  icon: Icon(Icons.refresh, size: 18),
                  onPressed: _loadWorkerLogs,
                  tooltip: "Refresh logs",
                  visualDensity: VisualDensity.compact,
                ),
              if (_logsExpanded && _workerLogs.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 18),
                  onPressed: _clearWorkerLogs,
                  tooltip: "Clear logs",
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
        if (_logsExpanded) ...[
          const SizedBox(height: 8),
          Container(
            height: 250,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _workerLogs.isEmpty
              ? Center(
                  child: Text(
                    "No logs yet.\nLogs appear here when the\nbackground worker runs.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _workerLogs.length,
                  itemBuilder: (context, index) {
                    final log = _workerLogs[index];
                    final level = log["level"] ?? "";
                    final ts = log["ts"] ?? "";
                    final tag = log["tag"] ?? "";
                    final msg = log["msg"] ?? "";
                    final color = switch (level) {
                      "E" => Colors.red.shade300,
                      "W" => Colors.orange.shade300,
                      _ => scheme.onSurface,
                    };
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: "[$level]",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: color,
                                fontFamily: 'monospace',
                              ),
                            ),
                            TextSpan(
                              text: " $ts ",
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                                fontFamily: 'monospace',
                              ),
                            ),
                            TextSpan(
                              text: msg,
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurface,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          ),
        ],
      ],
    );
  }
}

Future<bool> _testPexelsKey(String key) async {
  try {
    final res = await http
        .get(
          Uri.parse(
            "https://api.pexels.com/v1/search?query=nature&per_page=1&orientation=portrait",
          ),
          headers: {"Authorization": key},
        )
        .timeout(const Duration(seconds: 12));
    return res.statusCode == 200;
  } catch (_) {
    return false;
  }
}

Future<bool> _testPixabayKey(String key) async {
  try {
    final res = await http
        .get(
          Uri.parse(
            "https://pixabay.com/api/?key=$key&q=nature&per_page=3&orientation=vertical",
          ),
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return false;
    final body = jsonDecode(res.body);
    return body is Map && body["hits"] is List;
  } catch (_) {
    return false;
  }
}

Future<bool> _testUnsplashKey(String key) async {
  try {
    final res = await http
        .get(
          Uri.parse(
            "https://api.unsplash.com/search/photos?query=nature&per_page=1&orientation=portrait",
          ),
          headers: {"Authorization": "Client-ID $key"},
        )
        .timeout(const Duration(seconds: 12));
    return res.statusCode == 200;
  } catch (_) {
    return false;
  }
}

Future<bool> _testGeminiKey(String key) async {
  try {
    final res = await http
        .get(
          Uri.parse(
            "https://generativelanguage.googleapis.com/v1beta/models?key=$key",
          ),
        )
        .timeout(const Duration(seconds: 12));
    return res.statusCode == 200;
  } catch (_) {
    return false;
  }
}

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

class _TimePickerChip extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final ColorScheme scheme;

  const _TimePickerChip({
    required this.value,
    required this.onChanged,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final t = TimeOfDay(hour: value, minute: 0);
        final picked = await showTimePicker(context: context, initialTime: t);
        if (picked != null) onChanged(picked.hour);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          "${value.toString().padLeft(2, '0')}:00",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: scheme.onSurface),
        ),
      ),
    );
  }
}
