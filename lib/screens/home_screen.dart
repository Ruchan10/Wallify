import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/core/wallpaper_manager.dart';
import 'package:wallpaper_manager_flutter/wallpaper_manager_flutter.dart';

class WallpaperScreen extends StatefulWidget {
  const WallpaperScreen({super.key});

  @override
  State<WallpaperScreen> createState() => _WallpaperScreenState();
}

class _WallpaperScreenState extends State<WallpaperScreen>
    with WidgetsBindingObserver {
  final TextEditingController _tagController = TextEditingController();
  final Battery _battery = Battery();

  final List<String> sources = ["wallhaven", "unsplash", "pixabay"];
  List<String> savedTags = [];
  int wallpaperLocation = WallpaperManagerFlutter.bothScreens;

  List<Map<String, String>> statusHistory = [];
  int deviceWidth = 0;
  int deviceHeight = 0;
  final usp = UserSharedPrefs();
  Set<String> selectedSources = {"wallhaven", "unsplash", "pixabay"};
  String? tag;
  StreamSubscription<BatteryState>? _batterySubscription;

  @override
  void initState() {
    super.initState();
    _initialize();
    _checkCharging();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final size = MediaQuery.of(context).size;
      UserSharedPrefs.saveDeviceWidth(size.width.toInt());
      UserSharedPrefs.saveDeviceHeight(size.height.toInt());

      final pendingTag = await UserSharedPrefs.getPendingAction();

      if (pendingTag) {
        _addStatus("Changing lock screen wallpaper...");
        await UserSharedPrefs.savePendingAction(false);
    
        final res = await WallpaperManager.fetchAndSetWallpaper(
            wallpaperLocation: WallpaperManagerFlutter.lockScreen);
        _addStatus(res);
      }
    });
    WidgetsBinding.instance.addObserver(this);
  }

  void _initialize() async {
    final selectedSource = await UserSharedPrefs.getSelectedSources();
    selectedSources = selectedSource.toSet();
    savedTags = await UserSharedPrefs.getTags();
    wallpaperLocation = await UserSharedPrefs.getWallpaperLocation();
    statusHistory = await UserSharedPrefs.getStatusHistory();
    deviceWidth = (await UserSharedPrefs.getDeviceWidth()) ?? 0;
    deviceHeight = (await UserSharedPrefs.getDeviceHeight()) ?? 0;
    setState(() {});
  }

  String _formatDate(String dateStr) {
    final date = DateTime.tryParse(dateStr);
    if (date == null) return dateStr;
    return DateFormat("MMM d, h:mm a").format(date);
  }

  void _addTag(String tag) {
    if (tag.isNotEmpty && !savedTags.contains(tag)) {
      setState(() {
        savedTags.add(tag);
      });
    }
    UserSharedPrefs.saveTags(savedTags);

    _tagController.clear();
  }

  BatteryState? _lastBatteryState;

  Future<void> _checkCharging() async {
// final lastChange = await UserSharedPrefs.getLastWallpaperChange();
// if(lastChange != null){
//   final diff = DateTime.now().difference(lastChange);
//   if(diff.inHours < 1){
//     return;
//   }
// }
    _lastBatteryState = await _battery.batteryState;
    // if (_lastBatteryState == BatteryState.charging) {
    //   _addStatus('Device is charging');
    //   fetchAndSetWallpaper();
    // }

    _batterySubscription = _battery.onBatteryStateChanged.listen((state) {
      if (_lastBatteryState != BatteryState.charging &&
          state == BatteryState.charging) {
        debugPrint("Device plugged in - changing wallpaper");
        _addStatus("Device plugged in - changing wallpaper");
        changeWallpaper();
      }

      _lastBatteryState = state;
    });
  }


  Future<void> changeWallpaper() async {
    debugPrint("Started wallpaper change ==============================================");
    _addStatus("Started wallpaper change");
    UserSharedPrefs.saveLastWallpaperChange(DateTime.now());

    try {
      if (wallpaperLocation == WallpaperManagerFlutter.bothScreens) {
      
    UserSharedPrefs.savePendingAction(true);

        final res = await WallpaperManager.fetchAndSetWallpaper(
            wallpaperLocation: WallpaperManagerFlutter.homeScreen);
        _addStatus(res);
      } else {
        final res = await WallpaperManager.fetchAndSetWallpaper(
            wallpaperLocation: wallpaperLocation);
        _addStatus(res);
      }
    } catch (e) {
      _addStatus("Error: $e");

    }
  }


  void _addStatus(String message) {
    final entry = {"title": message, "date": DateTime.now().toString()};
    setState(() {
      statusHistory.insert(0, entry);
    });
    UserSharedPrefs.saveStatusHistory(statusHistory);
  }



  @override
  void dispose() {
    _batterySubscription?.cancel();
    debugPrint("Disposing==================================================");
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }



  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text("Auto Wallpaper"),
        elevation: 0,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            // --- Sources Selector ---
            Text("Sources", style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: sources.map((src) {
                return FilterChip(
                  label: Text(src),
                  selected: selectedSources.contains(src),
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        selectedSources.add(src);
                      } else {
                        selectedSources.remove(src);
                      }
                    });
                    UserSharedPrefs.saveSelectedSources(selectedSources.toList());
                  },
                  selectedColor: scheme.primaryContainer,
                  checkmarkColor: scheme.onPrimaryContainer,
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // --- Wallpaper location selector ---
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
                      () => wallpaperLocation =
                          WallpaperManagerFlutter.homeScreen,
                    );
                    UserSharedPrefs.saveWallpaperLocation(wallpaperLocation);
                  },
                ),
                ChoiceChip(
                  label: const Text("Lock"),
                  selected:
                      wallpaperLocation == WallpaperManagerFlutter.lockScreen,
                  onSelected: (_) {
                    setState(
                      () => wallpaperLocation =
                          WallpaperManagerFlutter.lockScreen,
                    );
                    UserSharedPrefs.saveWallpaperLocation(wallpaperLocation);
                  },
                ),
                ChoiceChip(
                  label: const Text("Both"),
                  selected:
                      wallpaperLocation == WallpaperManagerFlutter.bothScreens,
                  onSelected: (_) {
                    setState(
                      () => wallpaperLocation =
                          WallpaperManagerFlutter.bothScreens,
                    );
                    UserSharedPrefs.saveWallpaperLocation(wallpaperLocation);
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),

            // --- Tag Input + Add button ---
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 50,
                   
                    child: TextField(
                      controller: _tagController,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: scheme.surfaceContainerHigh,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        labelText: "Enter a tag",
                      ),
                      onSubmitted: (value) {
                        _addTag(_tagController.text);
                        UserSharedPrefs.saveTags(savedTags);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 50,
                
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () {
                      _addTag(_tagController.text);
                      UserSharedPrefs.saveTags(savedTags);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text("Add"),
                  ),
                ),
              ],
            ),
            if (savedTags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: -8,
                children: savedTags.map((tag) {
                  return Chip(
                    label: Text(tag),
                    deleteIcon: const Icon(Icons.close),
                    onDeleted: () {
                      setState(() => savedTags.remove(tag));
                      UserSharedPrefs.saveTags(savedTags);
                    },
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 24),

            // --- Info card ---
// --- Last & Next wallpaper info ---
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
              Icon(Icons.history, size: 18, color: scheme.onSurfaceVariant),
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
              Icon(Icons.bolt, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
  child: Text(
    lastChange != null
        ? "Next change after ${DateFormat("MMM d, h:mm a").format(lastChange.add(const Duration(hours: 1)))} when charging ⚡"
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



            // --- Status history ---
            Text("History", style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (statusHistory.isEmpty)
              Text(
                "No history yet",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else
              ...statusHistory.map((entry) {
                return Card(
                  child: ListTile(
                    leading: Icon(Icons.wallpaper, color: scheme.primary),
                    title: Text(entry["title"] ?? ""),
                    subtitle: Text(_formatDate(entry["date"] ?? "")),
                  ),
                );
              }),
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FilledButton.icon(
        onPressed: changeWallpaper,
        icon: const Icon(Icons.refresh),
        label: const Text("Change Now"),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
