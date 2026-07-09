import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/functions/shimmer_widget.dart';
import 'package:wallify/model/wallpaper_model.dart';
import 'package:wallify/screens/wallpaper_preview.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Wallpaper> _historyWalls = [];
  Set<String> _favIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    _historyWalls = await UserSharedPrefs.getWallpaperHistory();
    await _loadFavorites();
    setState(() => _isLoading = false);
  }

  Future<void> _loadFavorites() async {
    final favs = await UserSharedPrefs.getFavWallpapers();
    _favIds = favs.map((w) => w.id).toSet();
  }

  Future<void> _refresh() async {
    await _initialize();
  }

  Future<void> _toggleFavorite(Wallpaper wallpaper) async {
    final isFav = _favIds.contains(wallpaper.id);
    setState(() {
      if (isFav) {
        _favIds.remove(wallpaper.id);
      } else {
        _favIds.add(wallpaper.id);
      }
    });

    if (isFav) {
      await UserSharedPrefs.removeFavWallpaper(wallpaper);
    } else {
      await UserSharedPrefs.saveFavWallpaper(wallpaper);
    }
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
      body: _isLoading
          ? Padding(
              padding: const EdgeInsets.all(8.0),
              child: MasonryGridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                itemCount: 6,
                itemBuilder: (context, index) {
                  return ShimmerLoading(
                    height: 150 + (index % 3) * 50,
                    borderRadius: 12,
                  );
                },
              ),
            )
          : _historyWalls.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.history,
                        size: 64,
                        color: colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "No history yet",
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Wallpapers you set will appear here",
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.7),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: MasonryGridView.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      itemCount: _historyWalls.length,
                      itemBuilder: (context, index) {
                        final wallpaper = _historyWalls[index];
                        final isFav = _favIds.contains(wallpaper.id);

                        return ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            children: [
                              GestureDetector(
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    PageRouteBuilder(
                                      pageBuilder: (context, animation,
                                              secondaryAnimation) =>
                                          FadeTransition(
                                        opacity: animation,
                                        child: WallpaperPreviewPage(
                                          wallpapers: _historyWalls,
                                          initialIndex: index,
                                          isFavorite: isFav,
                                        ),
                                      ),
                                      transitionsBuilder: (context, animation,
                                              secondaryAnimation, child) =>
                                          FadeTransition(
                                        opacity: animation,
                                        child: child,
                                      ),
                                      transitionDuration:
                                          const Duration(milliseconds: 300),
                                    ),
                                  );
                                  // Favorite state may have changed inside the
                                  // preview page, so refresh it on return.
                                  await _loadFavorites();
                                  if (mounted) setState(() {});
                                },
                                child: Hero(
                                  tag: 'wallpaper_${wallpaper.url}',
                                  child: CachedNetworkImage(
                                    key: ValueKey(wallpaper.url),
                                    imageUrl: wallpaper.url,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) =>
                                        ShimmerLoading(
                                      height: 200,
                                      borderRadius: 12,
                                    ),
                                    errorWidget: (context, url, error) =>
                                        Container(
                                      height: 200,
                                      color: colorScheme.surface
                                          .withValues(alpha: 0.2),
                                      child: Icon(
                                        Icons.broken_image,
                                        color: colorScheme.onSurface
                                            .withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surface
                                        .withValues(alpha: 0.7),
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                    ),
                                    icon: AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      child: Icon(
                                        isFav
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        key: ValueKey(isFav),
                                        color: isFav
                                            ? Colors.red
                                            : colorScheme.onSurface,
                                      ),
                                    ),
                                    onPressed: () => _toggleFavorite(wallpaper),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 8,
                                left: 8,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      minimumSize: const Size(28, 28),
                                      padding: EdgeInsets.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    icon: Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                      color: Colors.red,
                                    ),
                                    onPressed: () async {
                                      await UserSharedPrefs.removeWallpaperHistory(wallpaper);
                                      setState(() {
                                        _historyWalls.removeAt(index);
                                      });
                                    },
                                  ),
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
