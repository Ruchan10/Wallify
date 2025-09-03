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
  final Set<String> selectedSources = {"wallhaven", "unsplash", "pixabay"};
  String tag = 'nature';
  StreamSubscription<BatteryState>? _batterySubscription;

  @override
  void initState() {
    super.initState();
    _initialize();
    _checkCharging();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final size = MediaQuery.of(context).size;
      deviceWidth = size.width.toInt();
      deviceHeight = size.height.toInt();

      final pendingTag = await UserSharedPrefs.getPendingAction();

      if (pendingTag != null) {
        _addStatus("Resuming pending lock wallpaper...");
        await _setWallpaperForLocation(
          pendingTag,
          WallpaperManagerFlutter.lockScreen,
        );
        await UserSharedPrefs.clearPendingAction();
      }
    });
    WidgetsBinding.instance.addObserver(this);
  }

  void _initialize() async {
    savedTags = await UserSharedPrefs.getTags();
    wallpaperLocation =
        await UserSharedPrefs.getWallpaperLocation() ??
        WallpaperManagerFlutter.bothScreens;
    statusHistory = await UserSharedPrefs.getStatusHistory();
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
    _tagController.clear();
  }

  BatteryState? _lastBatteryState;

  Future<void> _checkCharging() async {
    _lastBatteryState = await _battery.batteryState;

    // if (_lastBatteryState == BatteryState.charging) {
    //   _addStatus('Device is charging');
    //   fetchAndSetWallpaper();
    // }

    _batterySubscription = _battery.onBatteryStateChanged.listen((state) {
      if (_lastBatteryState != BatteryState.charging &&
          state == BatteryState.charging) {
        _addStatus('Device is charging');
        debugPrint("Device plugged in - changing wallpaper once");
        fetchAndSetWallpaper();
      }

      _lastBatteryState = state;
    });
  }

  Future<void> setWallFromBackground() async {
    savedTags = await UserSharedPrefs.getTags();
    wallpaperLocation =
        await UserSharedPrefs.getWallpaperLocation() ??
        WallpaperManagerFlutter.bothScreens;
    await fetchAndSetWallpaper();
  }

  Future<void> fetchAndSetWallpaper() async {
    _addStatus("Getting and setting wallpaper");

    final random = Random();
    tag = savedTags.isNotEmpty
        ? savedTags[random.nextInt(savedTags.length)]
        : "nature";

    try {
      if (wallpaperLocation == WallpaperManagerFlutter.bothScreens) {
        // _saveToUsp();
        _addStatus(
          "Home wallpaper setting. Lock wallpaper will be applied after restart (if needed).",
        );
        await _setWallpaperForLocation(tag, WallpaperManagerFlutter.homeScreen);
      } else {
        await _setWallpaperForLocation(tag, wallpaperLocation);
      }
    } catch (e) {
      _addStatus("Error: $e");
    }
  }

  Future<void> _setWallpaperForLocation(String tag, int location) async {
    final random = Random();
    final selectedSource = sources[random.nextInt(sources.length)];

    String? imageUrl;

    if (selectedSource == "wallhaven") {
      final res = await http.get(
        Uri.parse(
          "https://wallhaven.cc/api/v1/search?q=$tag"
          "&categories=100&purity=100"
          "&ratios=portrait"
          "&atleast=${deviceWidth}x$deviceHeight"
          "&sorting=random",
        ),
      );
      final data = jsonDecode(res.body);
      if (data["data"].isNotEmpty) {
        imageUrl = data["data"][0]["path"];
      }
    } else if (selectedSource == "unsplash") {
      final res = await http.get(
        Uri.parse(
          "https://api.unsplash.com/photos/random"
          "?query=$tag"
          "&orientation=portrait"
          "&content_filter=high",
        ),
        headers: {
          "Authorization":
              "Client-ID yTBcYNAtnRHbrYMn2p4DrBiqzOAfdH9nyexQQtJWO-E",
        },
      );
      final data = jsonDecode(res.body);
      imageUrl = data["urls"]["regular"];
    } else if (selectedSource == "pixabay") {
      final res = await http.get(
        Uri.parse(
          "https://pixabay.com/api/"
          "?key=52028006-a7e910370a5d0158c371bb06a"
          "&q=$tag"
          "&image_type=photo"
          "&orientation=vertical"
          "&min_width=$deviceWidth&min_height=$deviceHeight"
          "&per_page=50&safesearch=true",
        ),
      );
      final data = jsonDecode(res.body);
      final filtered = data["hits"] as List;
      if (filtered.isNotEmpty) {
        final idx = random.nextInt(filtered.length);
        imageUrl = filtered.elementAt(idx)["largeImageURL"];
      }
    }

    if (imageUrl == null) {
      _addStatus(
        "No wallpaper found for $tag in $selectedSource. Trying again",
      );
      fetchAndSetWallpaper();
      return;
    }

    final response = await http.get(Uri.parse(imageUrl));
    final bytes = response.bodyBytes;

    final dir = await getTemporaryDirectory();
    final filePath =
        "${dir.path}/wallpaper_${DateTime.now().millisecondsSinceEpoch}_$location.jpg";
    final file = await File(filePath).writeAsBytes(bytes);

    await WallpaperManagerFlutter().setWallpaper(file, location);

    _addStatus(
      "Wallpaper set for ${location == WallpaperManagerFlutter.homeScreen ? "Home" : "Lock"} from $selectedSource ($tag)",
    );
  }

  void _addStatus(String message) {
    final entry = {"title": message, "date": DateTime.now().toString()};
    setState(() {
      statusHistory.insert(0, entry);
    });
    // UserSharedPrefs.saveStatusHistory(statusHistory);
  }

  void _saveToUsp() {
    // Save all current state to SharedPreferences
    debugPrint('SAVING...=============================================');

    UserSharedPrefs.saveTags(savedTags);
    UserSharedPrefs.saveWallpaperLocation(wallpaperLocation);
    UserSharedPrefs.saveStatusHistory(statusHistory);
    UserSharedPrefs.savePendingAction(tag);
  }

  @override
  void dispose() {
    _batterySubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _saveToUsp();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
        _saveToUsp();
        break;
      default:
        break;
    }
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
                    // UserSharedPrefs.saveWallpaperLocation(wallpaperLocation);
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
                    // UserSharedPrefs.saveWallpaperLocation(wallpaperLocation);
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
                    // UserSharedPrefs.saveWallpaperLocation(wallpaperLocation);
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),

            // --- Tag Input + Add button ---
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagController,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: scheme.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      labelText: "Enter a tag",
                    ),
                    onSubmitted: (value) => _addTag(_tagController.text),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _addTag(_tagController.text),
                  icon: const Icon(Icons.add),
                  label: const Text("Add"),
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
                      // UserSharedPrefs.saveTags(savedTags);
                    },
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 24),

            // --- Info card ---
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: scheme.secondaryContainer,
              child: ListTile(
                leading: Icon(Icons.bolt, color: scheme.onSecondaryContainer),
                title: Text(
                  "Next wallpaper change: when device is charging ⚡",
                  style: TextStyle(color: scheme.onSecondaryContainer),
                ),
              ),
            ),
            const SizedBox(height: 24),

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
        onPressed: fetchAndSetWallpaper,
        icon: const Icon(Icons.refresh),
        label: const Text("Change Now"),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
