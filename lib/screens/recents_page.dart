import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/screens/wallpaper_preview.dart';

class FavoritesHistoryPage extends StatefulWidget {
  const FavoritesHistoryPage({super.key});

  @override
  State<FavoritesHistoryPage> createState() => _FavoritesHistoryPageState();
}

class _FavoritesHistoryPageState extends State<FavoritesHistoryPage> {
  List<String> historyWalls = [];
  List<String> favWalls = [];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  void _initialize() async {
    historyWalls = await UserSharedPrefs.getWallpaperHistory();
    favWalls = await UserSharedPrefs.getFavWallpaper();
    setState(() {});
  }

  Widget _buildGrid(List<String> images, {required bool isHistory}) {
    final colorScheme = Theme.of(context).colorScheme;

    if (images.isEmpty) {
      return Center(child: Text("No wallpapers found",
      style: TextStyle(color: colorScheme.onSurface), ));
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: MasonryGridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        itemCount: images.length,
        itemBuilder: (context, index) {
          final url = images[index];
          final isFav = favWalls.contains(url);
      
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            WallpaperPreviewPage(imageUrl: url, isFavorite: isFav),
                      ),
                    );
                  },
                  child: CachedNetworkImage(
                    key: ValueKey(url),
                    imageUrl: url,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      height: 200,
                       color: colorScheme.surface.withValues(alpha: 0.3),
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      height: 200,
                                           color: colorScheme.surface.withValues(alpha: 0.2),

                      child: Icon(Icons.broken_image,  color: colorScheme.onSurface.withValues(alpha: 0.5), ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    style: IconButton.styleFrom(
                       backgroundColor: colorScheme.surface.withValues(alpha: 0.6),
                    ),
                    icon: Icon(
                      isFav ? Icons.favorite : Icons.favorite_border,
                      color: isFav ? colorScheme.secondary : colorScheme.onSurface,
                    ),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 2,
      initialIndex: 0, 
      child: Scaffold(
        appBar: AppBar(
          title: const Text("My Wallpapers"),
          elevation: 0,
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          bottom: TabBar(
            indicatorColor: colorScheme.secondary.withValues(alpha: 0.8),
            labelColor: colorScheme.secondary,
            unselectedLabelColor: colorScheme.onSurface.withValues(alpha: 0.7),
            tabs: [
              Tab(text: "Favorites"),
              Tab(text: "History"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildGrid(favWalls, isHistory: false),
            _buildGrid(historyWalls, isHistory: true),
          ],
        ),
      ),
    );
  }
}
