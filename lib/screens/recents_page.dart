import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/functions/shimmer_widget.dart';
import 'package:wallify/model/wallpaper_model.dart';
import 'package:wallify/screens/wallpaper_preview.dart';

class FavoritesHistoryPage extends StatefulWidget {
  const FavoritesHistoryPage({super.key});

  @override
  State<FavoritesHistoryPage> createState() => _FavoritesHistoryPageState();
}

class _FavoritesHistoryPageState extends State<FavoritesHistoryPage>
    with SingleTickerProviderStateMixin {
  List<Wallpaper> historyWalls = [];
  List<Wallpaper> favWalls = [];
  bool _isLoading = true;
  late AnimationController _tabAnimController;

  @override
  void initState() {
    super.initState();
    _tabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _initialize();
  }

  @override
  void dispose() {
    _tabAnimController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    _tabAnimController.forward();

    favWalls = await UserSharedPrefs.getFavWallpapers();

    historyWalls = await UserSharedPrefs.getWallpaperHistory();

    setState(() => _isLoading = false);
  }

  Future<void> _refresh() async {
    await _initialize();
  }

  Widget _buildGrid(List<Wallpaper> images, {required bool isHistory}) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Padding(
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
      );
    }

    if (images.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isHistory ? Icons.history : Icons.favorite_border,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              isHistory ? "No history yet" : "No favorites yet",
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isHistory
                  ? "Wallpapers you set will appear here"
                  : "Tap the heart icon to save wallpapers",
              style: TextStyle(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: MasonryGridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          itemCount: images.length,
          itemBuilder: (context, index) {
            final wallpaper = images[index];
            final isFav = favWalls.any((w) => w.id == wallpaper.id);

            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder:
                              (context, animation, secondaryAnimation) =>
                                  FadeTransition(
                            opacity: animation,
                            child: WallpaperPreviewPage(
                              wallpaper: wallpaper,
                              isFavorite: isFav,
                            ),
                          ),
                          transitionsBuilder:
                              (context, animation, secondaryAnimation, child) {
                            return FadeTransition(
                              opacity: animation,
                              child: child,
                            );
                          },
                          transitionDuration:
                              const Duration(milliseconds: 300),
                        ),
                      );
                    },
                    child: Hero(
                      tag: 'wallpaper_${wallpaper.url}',
                      child: CachedNetworkImage(
                        key: ValueKey(wallpaper.url),
                        imageUrl: wallpaper.url,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => ShimmerLoading(
                          height: 200,
                          borderRadius: 12,
                        ),
                        errorWidget: (context, url, error) => Container(
                          height: 200,
                          color: colorScheme.surface.withValues(alpha: 0.2),
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
                        color: colorScheme.surface.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.transparent,
                        ),
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            isFav
                                ? Icons.favorite
                                : Icons.favorite_border,
                            key: ValueKey(isFav),
                            color: isFav
                                ? colorScheme.secondary
                                : colorScheme.onSurface,
                          ),
                        ),
                        onPressed: () {
                          setState(() {
                            if (isFav) {
                              favWalls.removeWhere(
                                (w) => w.id == wallpaper.id,
                              );
                              UserSharedPrefs.removeFavWallpaper(wallpaper);
                            } else {
                              favWalls.add(wallpaper);
                              UserSharedPrefs.saveFavWallpaper(wallpaper);
                            }
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
            indicatorColor: colorScheme.secondary,
            indicatorWeight: 3,
            labelColor: colorScheme.onPrimary,
            unselectedLabelColor:
                colorScheme.onPrimary.withValues(alpha: 0.7),
            labelStyle: const TextStyle(fontWeight: FontWeight.w600),
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.favorite, size: 18),
                    const SizedBox(width: 6),
                    const Text("Favorites"),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.history, size: 18),
                    const SizedBox(width: 6),
                    const Text("History"),
                  ],
                ),
              ),
            ],
          ),
        ),
        body: FadeTransition(
          opacity: _tabAnimController,
          child: TabBarView(
            children: [
              _buildGrid(favWalls, isHistory: false),
              _buildGrid(historyWalls, isHistory: true),
            ],
          ),
        ),
      ),
    );
  }
}
