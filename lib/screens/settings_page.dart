import 'dart:async';
import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wallify/core/config.dart';
import 'package:wallify/core/theme_provider.dart';
import 'package:wallify/core/update_manager.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/functions/backup_function.dart';
import 'package:wallify/functions/wallpaper_manager.dart';
import 'package:wallpaper_manager_flutter/wallpaper_manager_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> with WidgetsBindingObserver {
  final TextEditingController _tagController = TextEditingController();
  final Battery _battery = Battery();

  List<String> savedTags = [];
  int wallpaperLocation = WallpaperManagerFlutter.bothScreens;
  List<Map<String, String>> statusHistory = [];

  StreamSubscription<BatteryState>? _batterySubscription;
  int _intervalHours = 1;
  TextEditingController _intervalController = TextEditingController(text: "1");

  BatteryState? _lastBatteryState;

  @override
  void initState() {
    super.initState();
    _initialize();
    _checkCharging();
    UpdateManager.checkForUpdates();
    WidgetsBinding.instance.addObserver(this);
  }

  void _initialize() async {
    savedTags = await UserSharedPrefs.getTags();
    wallpaperLocation = await UserSharedPrefs.getWallpaperLocation();
    statusHistory = await UserSharedPrefs.getStatusHistory();
    _intervalHours = await UserSharedPrefs.getInterval() ?? 1;
    _intervalController.text = _intervalHours.toString();

    setState(() {});
  }

  Future<void> _checkCharging() async {
    _lastBatteryState = await _battery.batteryState;
    _batterySubscription = _battery.onBatteryStateChanged.listen((state) {
      if (_lastBatteryState != BatteryState.charging &&
          state == BatteryState.charging) {
        _addStatus("Device plugged in - changing wallpaper");
        changeWallpaper();
      }
      _lastBatteryState = state;
    });
  }

  Future<void> changeWallpaper({bool changeNow = false}) async {
    try {
      final res = await WallpaperManager.fetchAndSetWallpaper(
        wallpaperLocation: wallpaperLocation,
        changeNow: changeNow,
      );
      _addStatus(res);
    } catch (e) {
      _addStatus("Error: $e");
    }
  }

  void _addStatus(String message) {
    final entry = {"title": message, "date": DateTime.now().toString()};
    setState(() => statusHistory.insert(0, entry));
    UserSharedPrefs.saveStatusHistory(statusHistory);
  }

  @override
  void dispose() {
    _batterySubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _formatDate(String dateStr) {
    final date = DateTime.tryParse(dateStr);
    if (date == null) return dateStr;
    return DateFormat("MMM d, h:mm a").format(date);
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
          // ========== THEME TOGGLE ==========
          Text("Appearance", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ListTile(
            leading:  Icon(Icons.brightness_6, color: scheme.primary),
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
          const Divider(),

          // ========== EXPORT / IMPORT ==========
          SizedBox(height: 16),
          Text("Data", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.upload_file, color: scheme.primary),
            title: const Text("Export Settings"),
            onTap: () async {
              final file = await SettingsBackup.exportSettings();
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

      setState(() {}); 
      SnackBar(
                  content: Text("Settings imported successfully"),
                );
    }
            },
          ),
          const Divider(),
          SizedBox(height: 16),

          // ========== CHECK UPDATE ==========
          ListTile(
            leading:  Icon(Icons.system_update, color: scheme.primary),
            title: const Text("Check for Updates"),
            onTap: () {
              UpdateManager.checkForUpdates();
              if (Config.getUpdateAvailable()) {
                UpdateManager.showUpdateDialog(context);
              } else {
                SnackBar(
                  content: Text("You're on the latest version"),
                );
              }
            },
          ),
          const Divider(),
          SizedBox(height: 16),

          // ========== AUTOMATE WALLPAPER ==========
          Text("Automate Wallpaper",
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),

          _buildWallpaperSettings(context, scheme),

          const SizedBox(height: 20),

          // --- History ---
          Text("History", style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (statusHistory.isEmpty)
            Text("No history yet",
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant))
          else
            ...statusHistory.map((entry) {
              return Card(
                 color: scheme.surface,
                child: ListTile(
                  leading: Icon(Icons.wallpaper, color: scheme.primary),
                  title: Text(entry["title"] ?? "", style: TextStyle(color: scheme.onSurface)),
                  subtitle: Text(_formatDate(entry["date"] ?? ""), style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              );
            }),

          const SizedBox(height: 80),
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
        Text("Apply To", style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text("Home"),
              selected: wallpaperLocation == WallpaperManagerFlutter.homeScreen,
              onSelected: (_) {
                setState(() =>
                    wallpaperLocation = WallpaperManagerFlutter.homeScreen);
                UserSharedPrefs.saveWallpaperLocation(wallpaperLocation);
              },
              selectedColor: scheme.primary.withValues(alpha: 0.2),
              backgroundColor: scheme.surfaceContainerHighest,
            ),
            ChoiceChip(
              label: const Text("Lock"),
              selected: wallpaperLocation == WallpaperManagerFlutter.lockScreen,
              onSelected: (_) {
                setState(() =>
                    wallpaperLocation = WallpaperManagerFlutter.lockScreen);
                UserSharedPrefs.saveWallpaperLocation(wallpaperLocation);
              },
              selectedColor: scheme.primary.withValues(alpha: 0.2),
              backgroundColor: scheme.surfaceContainerHighest,
            ),
            ChoiceChip(
              label: const Text("Both"),
              selected: wallpaperLocation == WallpaperManagerFlutter.bothScreens,
              onSelected: (_) {
                setState(() =>
                    wallpaperLocation = WallpaperManagerFlutter.bothScreens);
                UserSharedPrefs.saveWallpaperLocation(wallpaperLocation);
              },
              selectedColor: scheme.primary.withValues(alpha: 0.2),
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ],
        ),
        const SizedBox(height: 20),

        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                "Auto Change Interval (hours):",
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
                onSubmitted: (value) {
                  final hours = int.tryParse(value);
                  if (hours != null && hours > 0) {
                    setState(() => _intervalHours = hours);
                    UserSharedPrefs.saveInterval(hours);
                  } else {
                    _intervalController.text = _intervalHours.toString();
                  }
                },
              ),
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
                onSubmitted: (value) {
                  if (value.isNotEmpty && !savedTags.contains(value)) {
                    setState(() => savedTags.add(value));
                    UserSharedPrefs.saveTags(savedTags);
                  }
                  _tagController.clear();
                },
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
              ),
              onPressed: () {
                if (_tagController.text.isNotEmpty &&
                    !savedTags.contains(_tagController.text)) {
                  setState(() => savedTags.add(_tagController.text));
                  UserSharedPrefs.saveTags(savedTags);
                }
                _tagController.clear();
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
                onDeleted: () {
                  setState(() => savedTags.remove(tag));
                  UserSharedPrefs.saveTags(savedTags);
                },
              );
            }).toList(),
          ),
        ],
        
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
                                  ? "Next change after ${DateFormat("MMM d, h:mm a").format(lastChange.add(Duration(hours: _intervalHours)))} when charging ⚡"
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
}
