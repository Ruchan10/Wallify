import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/screens/wallpaper_preview.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<String> historyWalls = [];
  List<String> favWalls = [];
  @override
  initState() {
    super.initState();
    _initialize();
  }

  void _initialize() async {
    historyWalls = await UserSharedPrefs.getWallpaperHistory();
    favWalls = await UserSharedPrefs.getFavWallpaper();
    setState(() {});
  }


  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("History"),
        elevation: 0,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: historyWalls.isEmpty
            ? const Center(child: Text("No wallpapers found"))
            : Expanded(
              child: MasonryGridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  itemCount: historyWalls.length,
                  itemBuilder: (context, index) {
                    final url = historyWalls[index];
                    final isFav = favWalls.contains(url);
              
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                  children: [
                    
                    GestureDetector(
                              onTap: () {
                                Navigator.push(context, MaterialPageRoute(builder: (context) => WallpaperPreviewPage(imageUrl: url, isFavorite: isFav)));
                              },
                              child: CachedNetworkImage(
                                imageUrl: url,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  height: 200,
                                  color: Colors.grey[300],
                                  child: const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  height: 200,
                                  color: Colors.grey[200],
                                  child: const Icon(Icons.broken_image, color: Colors.grey),
                                ),
                              ),
                            ),
              
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black45,
                          foregroundColor: isFav
                              ? colorScheme.secondary
                              : colorScheme.onPrimary,
                        ),
                        icon: Icon(
                            isFav ? Icons.favorite : Icons.favorite_border),
                        onPressed: () {
                          setState(() {
                            if (isFav) {
                              favWalls.remove(url);
                              UserSharedPrefs.removeFavWallpaper(url);
                            } else {
                              favWalls.add(url);
                              UserSharedPrefs.saveFavWallpaper(url);
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
              );
                        },
                      ),
            ),
      ),
    );
  }
}
