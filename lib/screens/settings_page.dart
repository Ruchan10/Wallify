import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:wallify/core/config.dart';
import 'package:wallify/core/snackbar.dart';
import 'package:wallify/core/theme_provider.dart';
import 'package:wallify/core/update_manager.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/core/wallpaper_theme_provider.dart';
import 'package:wallify/functions/backup_function.dart';
import 'package:wallify/functions/wallpaper_cache_manager.dart';
import 'package:wallify/functions/wallpaper_manager.dart';
import 'package:wallpaper_manager_flutter/wallpaper_manager_flutter.dart';
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
  String? _folderPath;
  bool _updateAvailable = false;
  bool _checkingUpdate = true;

  @override
  void initState() {
    super.initState();
    _initialize();
    _checkUpdateStatus();
    WidgetsBinding.instance.addObserver(this);
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

  Future<void> _initialize() async {
    _autoWallpaperEnabled = await UserSharedPrefs.getAutoWallpaperEnabled();
    savedTags = await UserSharedPrefs.getTags();
    _invalidTags = await UserSharedPrefs.getInvalidTags();
    wallpaperLocation = await UserSharedPrefs.getWallpaperLocation();
    _intervalMinutes = await UserSharedPrefs.getInterval();
    _intervalController.text = _intervalMinutes.toString();
    _wallpaperSources = await UserSharedPrefs.getWallpaperSources();
    _folderPath = await UserSharedPrefs.getFolderPath();

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
    } catch (e) {
      showSnackBar(context: context, color: Colors.red, message: "Error: $e");
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
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                if (_autoWallpaperEnabled)
                  _buildWallpaperSettings(context, scheme),
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
                const SizedBox(height: 20),
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
                  if (minutes != null && minutes > 0) {
                    setState(() => _intervalMinutes = minutes);
                    UserSharedPrefs.saveInterval(minutes);
                  } else {
                    _intervalController.text = _intervalMinutes.toString();
                  }
                  resetAutoWallpaper();
                },
              ),
            ),
          ],
        ),
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
                selectedColor: scheme.primary,
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _folderPath ?? "No folder selected",
                    style: TextStyle(
                      fontSize: 13,
                      color: _folderPath != null
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final path = await FilePicker.getDirectoryPath();
                    if (path != null) {
                      setState(() => _folderPath = path);
                      await UserSharedPrefs.setFolderPath(path);
                      resetAutoWallpaper();
                    }
                  },
                  child: const Text("Browse"),
                ),
              ],
            ),
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
      {"key": "constraint_battery", "label": "Battery Not Low"},
      {"key": "constraint_storage", "label": "Storage Not Low"},
      {"key": "constraint_wifi", "label": "Wi-Fi Only"},
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
          ],
        );
      },
    );
  }
}
