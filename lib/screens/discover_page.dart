import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/functions/image_card.dart';
import 'package:wallify/screens/wallpaper_preview.dart';

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}
class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  final TextEditingController _searchController = TextEditingController();
  List<String> _images = [];
  bool _isLoading = false;
  int count = 1;
  final ScrollController _scrollController = ScrollController();

  String? _lastQuery; // ✅ Track last searched query
  final Set<String> favorites = {};
  final List<String> _filters = ["Nature", "Animals", "Abstract", "City", "Space"];
  String? _selectedFilter;

  @override
  void initState() {
    super.initState();
    _fetchImages();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          !_isLoading) {
        count++;
        _fetchImages(
          query: _searchController.text.isNotEmpty
              ? _searchController.text
              : null,
          count: count,
        );
      }
    });
    _configureImageCache();
  }

  void _configureImageCache() {
    PaintingBinding.instance.imageCache.maximumSize = 150;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 150 * 1024 * 1024;
  }

  Future<void> _fetchImages({
    String? query,
    int count = 1,
    bool isSearch = false,
  }) async {
    setState(() {
      _isLoading = true;
      if (query != null && isSearch) _lastQuery = query; // ✅ Save last search
    });

    final List<String> results = [];

    try {
      /// 🔹 Wallhaven
      final wallRes = await http.get(
        Uri.parse(
          "https://wallhaven.cc/api/v1/search?page=$count"
          "${query == null ? "" : "&q=$query"}",
        ),
      );
      final wallData = jsonDecode(wallRes.body);
      for (var item in wallData["data"]) {
        results.add(item["path"]);
        precacheImage(CachedNetworkImageProvider(item["path"]), context);
      }

      /// 🔹 Unsplash
      final unsplashRes = await http.get(
        Uri.parse(
          "https://api.unsplash.com/photos"
          "${query == null ? "?" : "?query=$query&"}"
          "page=$count",
        ),
        headers: {
          "Authorization":
              "Client-ID yTBcYNAtnRHbrYMn2p4DrBiqzOAfdH9nyexQQtJWO-E",
        },
      );
      final unsplashData = jsonDecode(unsplashRes.body);
      for (var item in unsplashData) {
        results.add(item["urls"]["regular"]);
        precacheImage(
          CachedNetworkImageProvider(item["urls"]["regular"]),
          context,
        );
      }

      /// 🔹 Pixabay
      final pixabayRes = await http.get(
        Uri.parse(
          "https://pixabay.com/api/"
          "?key=52028006-a7e910370a5d0158c371bb06a"
          "${query == null ? "" : "&q=$query"}"
          "&image_type=photo"
          "&page=$count",
        ),
      );
      final pixabayData = jsonDecode(pixabayRes.body);
      for (var item in pixabayData["hits"]) {
        results.add(item["largeImageURL"]);
        precacheImage(
          CachedNetworkImageProvider(item["largeImageURL"]),
          context,
        );
      }
    } catch (e) {
      debugPrint("❌ Error fetching images: $e ====================");
    }
    setState(() {
      if (isSearch) {
        _images = results;
      } else {
        _images.addAll(results);
      }
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Discover"),
        elevation: 0,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          spacing: 12,
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Search...",
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _lastQuery = null;
                            _images.clear();
                          });
                          _fetchImages();
                        },
                      )
                    : null,
              ),
              onSubmitted: (value) {
                if (value.isNotEmpty) {
                  _fetchImages(query: value.trim(), isSearch: true);
                }
              },
              onChanged: (_) => setState(() {}), 
            ),

            if (_lastQuery != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Showing results for \"$_lastQuery\"",
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),

            Expanded(
              child: _images.isEmpty
                  ? Center(
                      child: Text(
                        _isLoading ? "Loading..." : "No wallpapers",
                        style: TextStyle(color: colorScheme.onSurface),
                      ),
                    )
                  : MasonryGridView.builder(
                      key: const PageStorageKey("discover_grid"),
                      controller: _scrollController,
                      gridDelegate:
                          SliverSimpleGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                      ),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      itemCount: _images.length,
                      itemBuilder: (context, index) {
                        final img = _images[index];
                        final isFav = favorites.contains(img);

                        return ImageTile(
                          img: img,
                          isFav: isFav,
                          onFavToggle: () {
                            setState(() {
                              if (isFav) {
                                favorites.remove(img);
                                UserSharedPrefs.removeFavWallpaper(img);
                              } else {
                                favorites.add(img);
                                UserSharedPrefs.saveFavWallpaper(img);
                              }
                            });
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
