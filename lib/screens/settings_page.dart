import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:wallify/core/config.dart';
import 'package:wallify/core/snackbar.dart';
import 'package:wallify/core/theme_provider.dart';
import 'package:wallify/core/update_manager.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/functions/backup_function.dart';
import 'package:wallify/functions/wallpaper_manager.dart';
import 'package:wallpaper_manager_flutter/wallpaper_manager_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage>
    with WidgetsBindingObserver {
  final TextEditingController _tagController = TextEditingController();

  List<String> savedTags = [];
  int wallpaperLocation = WallpaperManagerFlutter.bothScreens;

  int _intervalMinutes = 60;
  final TextEditingController _intervalController = TextEditingController(
    text: "60",
  );
  static const platform = MethodChannel('wallpaper_channel');
  bool _autoWallpaperEnabled = false;

  @override
  void initState() {
    super.initState();
    _initialize();
    UpdateManager.checkForUpdates();
    WidgetsBinding.instance.addObserver(this);
  }

  void _initialize() async {
    _autoWallpaperEnabled = await UserSharedPrefs.getAutoWallpaperEnabled();
    savedTags = await UserSharedPrefs.getTags();
    wallpaperLocation = await UserSharedPrefs.getWallpaperLocation();
    _intervalMinutes = await UserSharedPrefs.getInterval();
    _intervalController.text = _intervalMinutes.toString();

    setState(() {});
    if (_autoWallpaperEnabled) {
      await platform.invokeMethod("scheduleBackgroundWallpaperWorker");
    }
  }

  Future<void> changeWallpaper({bool changeNow = false}) async {
    try {
      await Workmanager().cancelAll();
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

  String _formatDate(String dateStr) {
    final date = DateTime.tryParse(dateStr);
    if (date == null) return dateStr;
    return DateFormat("MMM d, h:mm a").format(date);
  }

  void resetAutoWallpaper() async {
    await Workmanager().cancelAll();
    await platform.invokeMethod("scheduleBackgroundWallpaperWorker");
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text("Apply To", style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text("Home"),
                selected:
                    wallpaperLocation == WallpaperManagerFlutter.homeScreen,
                onSelected: (_) {
                  setState(
                    () =>
                        wallpaperLocation = WallpaperManagerFlutter.homeScreen,
                  );
                  UserSharedPrefs.saveWallpaperLocation(wallpaperLocation);
                  resetAutoWallpaper();
                },
                selectedColor: scheme.primary.withValues(alpha: 0.2),
                backgroundColor: scheme.surfaceContainerHighest,
              ),
              ChoiceChip(
                label: const Text("Lock"),
                selected:
                    wallpaperLocation == WallpaperManagerFlutter.lockScreen,
                onSelected: (_) {
                  setState(
                    () =>
                        wallpaperLocation = WallpaperManagerFlutter.lockScreen,
                  );
                  UserSharedPrefs.saveWallpaperLocation(wallpaperLocation);
                  resetAutoWallpaper();
                },
                selectedColor: scheme.primary.withValues(alpha: 0.2),
                backgroundColor: scheme.surfaceContainerHighest,
              ),
              ChoiceChip(
                label: const Text("Both"),
                selected:
                    wallpaperLocation == WallpaperManagerFlutter.bothScreens,
                onSelected: (_) {
                  setState(
                    () =>
                        wallpaperLocation = WallpaperManagerFlutter.bothScreens,
                  );
                  UserSharedPrefs.saveWallpaperLocation(wallpaperLocation);
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
                    }
                    _tagController.clear();
                    final urls =
                        await WallpaperManager.fetchImagesFromAllSources();
                    await UserSharedPrefs.saveWallpapers(urls);
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
                    setState(() => savedTags.add(_tagController.text));
                    UserSharedPrefs.saveTags(savedTags);
                  }
                  _tagController.clear();
                  final urls =
                      await WallpaperManager.fetchImagesFromAllSources();
                  await UserSharedPrefs.saveWallpapers(urls);
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
                return Chip(
                  label: Text(tag),
                  deleteIcon: Icon(Icons.close, color: scheme.onSurfaceVariant),
                  backgroundColor: scheme.surfaceContainerHighest,
                  onDeleted: () async {
                    setState(() => savedTags.remove(tag));
                    UserSharedPrefs.saveTags(savedTags);
                    final urls =
                        await WallpaperManager.fetchImagesFromAllSources();
                    await UserSharedPrefs.saveWallpapers(urls);
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
                  final urls =
                      await WallpaperManager.fetchImagesFromAllSources();
                  await UserSharedPrefs.saveWallpapers(urls);
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
                      await Workmanager().cancelAll();
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
          if (_autoWallpaperEnabled) _buildWallpaperSettings(context, scheme),
          const Divider(),
          // ========== THEME TOGGLE ==========
          Text("Appearance", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.brightness_6, color: scheme.primary),
            title: const Text("Theme"),
            subtitle: const Text("Switch between light and dark mode"),
            trailing: Switch(
              value: isDark,
              onChanged: (val) {
                ref.read(themeProvider.notifier).toggleTheme(val);
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
              await SettingsBackup.exportSettings();
              if (mounted) {
                showSnackBar(
                  context: context,
                  message: "Settings file exported to Downloads folder",
                );
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.download, color: scheme.primary),
            title: const Text("Import Settings"),
            onTap: () async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['json'],
              );
              if (result != null && result.files.single.path != null) {
                final file = File(result.files.single.path!);
                await SettingsBackup.importSettings(file);

                if (mounted) {
                  setState(() {});
                  showSnackBar(
                    context: context,
                    message: "Settings imported successfully",
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
              Config.getUpdateAvailable() ? Icons.update : Icons.system_update,
              color: scheme.primary,
            ),
            title: Config.getUpdateAvailable()
                ? Text("Update Available")
                : Text("Check for Updates"),
            onTap: () {
              UpdateManager.checkForUpdates();
              if (Config.getUpdateAvailable()) {
                UpdateManager.showUpdateDialog(context);
              } else {
                showSnackBar(
                  context: context,
                  message: "You're on the latest version",
                );
              }
            },
          ),

          const SizedBox(height: 20),
        ],
      ),
      floatingActionButton: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
        ),
        onPressed: () => changeWallpaper(changeNow: true),
        icon: const Icon(Icons.refresh),
        label: const Text("Change Now"),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
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
        const SizedBox(height: 8),

        // const SizedBox(height: 20),
        // Text(
        //   "Automation Constraints",
        //   style: Theme.of(context).textTheme.titleMedium,
        // ),
        // const SizedBox(height: 8),

        // Container(
        //   decoration: BoxDecoration(
        //     color: scheme.surfaceContainerHighest,
        //     borderRadius: BorderRadius.circular(16),
        //   ),
        //   padding: const EdgeInsets.all(12),
        //   child: Column(
        //     children: [
        //       _buildConstraintTile(
        //         context,
        //         icon: Icons.bolt,
        //         title: "Only when charging",
        //         subtitle: "Run wallpaper updates only while plugged in",
        //         prefKey: "constraint_charging",
        //       ),
        //       _buildConstraintTile(
        //         context,
        //         icon: Icons.battery_6_bar,
        //         title: "Battery not low",
        //         subtitle: "Skip wallpaper change if battery is below 15%",
        //         prefKey: "constraint_battery",
        //       ),
        //       _buildConstraintTile(
        //         context,
        //         icon: Icons.storage,
        //         title: "Storage not low",
        //         subtitle: "Avoid running when storage is almost full",
        //         prefKey: "constraint_storage",
        //       ),
        //       _buildConstraintTile(
        //         context,
        //         icon: Icons.wifi,
        //         title: "Require Wi-Fi",
        //         subtitle: "Fetch wallpapers only on Wi-Fi connection",
        //         prefKey: "constraint_wifi",
        //       ),
        //       _buildConstraintTile(
        //         context,
        //         icon: Icons.face_retouching_off,
        //         title: "No human faces",
        //         subtitle: "Skip wallpapers that include people",
        //         prefKey: "constraint_no_faces",
        //       ),
        //       _buildConstraintTile(
        //         context,
        //         icon: Icons.nightlight,
        //         title: "When device is idle",
        //         subtitle: "Only update wallpaper when not actively used",
        //         prefKey: "constraint_idle",
        //       ),
        //     ],
        //   ),
        // ),
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
                          lastChange != null
                              ? "Next change after ${DateFormat("MMM d, h:mm a").format(lastChange.add(Duration(minutes: _intervalMinutes)))} when charging ⚡"
                              : "Next change when device is charging ⚡",
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

  Widget _buildConstraintTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String prefKey,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<bool>(
      future: UserSharedPrefs.getBool(prefKey),
      builder: (context, snapshot) {
        final value = snapshot.data ?? false;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: Icon(icon, color: scheme.primary),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: Switch(
            value: value,
            activeColor: scheme.secondary,
            onChanged: (val) async {
              await UserSharedPrefs.setBool(prefKey, val);
              setState(() {});
              showSnackBar(
                context: context,
                message: val ? "$title enabled" : "$title disabled",
              );
            },
          ),
        );
      },
    );
  }
}
