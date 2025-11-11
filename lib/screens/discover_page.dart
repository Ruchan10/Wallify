import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:wallify/core/config.dart' as app_config;
import 'package:wallify/core/performance_config.dart';
import 'package:wallify/core/update_manager.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/functions/image_card.dart';
import 'package:wallify/model/wallpaper_model.dart';

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  final TextEditingController _searchController = TextEditingController();
  // List<String> _images = Config.getImageUrls();
  List<Wallpaper> _images = [];
  bool _isLoading = false;
  int count = 1;
  final ScrollController _scrollController = ScrollController();

  String? _lastQuery;
  final Set<String> favorites = {};
  String? _selectedSorting;
  String? _selectedPurity;
  String? _selectedOrientation;
  String? _selectedCategory;
  String? _selectedRange;
  bool _showTopBar = true;
  double _lastOffset = 0;

  // Memory management - limit total images in memory
  static const int maxImages = PerformanceConfig.maxImagesInMemory;

  @override
  void initState() {
    super.initState();
    // if (app_config.Config.getImageUrls().isEmpty) {
      _fetchImages();
    // }
    UpdateManager.checkForUpdates();
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 5), () {
        if (app_config.Config.getUpdateAvailable()) {
          UpdateManager.showUpdateDialog(context);
        }
      });
    });
  }

  void _onScroll() {
    if (!mounted) return;

    final offset = _scrollController.position.pixels;

    if (offset > _lastOffset && _showTopBar) {
      setState(() => _showTopBar = false);
    } else if (offset < _lastOffset && !_showTopBar) {
      setState(() => _showTopBar = true);
    }

    _lastOffset = offset;

    // Load more images when near bottom
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        _images.length < maxImages) {
      // Prevent unlimited growth
      count++;
      _fetchImages(
        query: _searchController.text.isNotEmpty
            ? _searchController.text
            : null,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchImages({String? query, bool isSearch = false}) async {
    setState(() {
      _isLoading = true;
      if (query != null && isSearch) _lastQuery = query;
    });

    final List<Wallpaper> results = [];
    try {
      /// 🔹 Wallhaven
      final wallRes = await http.get(
        Uri.parse(
          "https://wallhaven.cc/api/v1/search?"
          "page=$count"
          "${_selectedCategory == null ? "" : "&categories=${_selectedCategory == "general"
                    ? "100"
                    : _selectedCategory == "anime"
                    ? "101"
                    : "110"}"}"
          "${_selectedPurity == null ? "" : "&purity=${_selectedPurity == "SFW"
                    ? "100"
                    : _selectedPurity == "Sketchy"
                    ? "110"
                    : "111"}"}"
          "${_selectedSorting == null ? "" : "&sorting=${_selectedRange == null ? _selectedSorting : "toplist"}"}"
          "${_selectedRange == null ? "" : "&topRange=$_selectedRange"}"
          "${query == null ? "" : "&q=$query"}",
        ),
      );
      final wallData = jsonDecode(wallRes.body);
      for (var item in wallData["data"]) {
        results.add(Wallpaper(id: item["id"], url: item["path"]));
      }

      /// 🔹 Unsplash
      final unsplashRes = await http.get(
        Uri.parse(
          "${query == null ? "https://api.unsplash.com/photos" : "https://api.unsplash.com/search/photos"}"
          "?order_by=relevant"
          "${query == null ? "" : "&query=$query"}"
          "${_selectedSorting == null ? "" : "&order_by=${_selectedSorting == "dater_added" ? "latest" : "relevant"}"}"
          "${_selectedPurity == null ? "" : "&content_filter=${_selectedPurity == "NSFW" ? "high" : "low"}"}"
          "${_selectedOrientation == null ? "" : "&orientation=$_selectedOrientation"}"
          "&page=$count",
        ),
        headers: {
          "Authorization":
              "Client-ID yTBcYNAtnRHbrYMn2p4DrBiqzOAfdH9nyexQQtJWO-E",
        },
      );
      final unsplashData = jsonDecode(unsplashRes.body);

      for (var item in query == null ? unsplashData : unsplashData["results"]) {
        results.add(Wallpaper(id: item["id"], url: item["urls"]["regular"]));
      }

      /// 🔹 Pixabay
      final pixabayRes = await http.get(
        Uri.parse(
          "https://pixabay.com/api/"
          "?key=52028006-a7e910370a5d0158c371bb06a"
          "${query == null ? "" : "&q=$query"}"
          "&image_type=photo"
          "${_selectedPurity == null ? "" : "&safesearch=${_selectedPurity == "NSFW" ? "false" : "true"}"}"
          "${_selectedSorting == null ? "" : "&order=${_selectedSorting == "dater_added" ? "latest" : "popular"}"}"
          "${_selectedOrientation == null ? "" : "&orientation=$_selectedOrientation"}"
          "&page=$count",
        ),
      );
      final pixabayData = jsonDecode(pixabayRes.body);
      for (var item in pixabayData["hits"]) {
        results.add(
          Wallpaper(id: item["id"].toString(), url: item["largeImageURL"]),
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
        if (_images.length > maxImages) {
          _images = _images.sublist(_images.length - maxImages);
        }
      }
      _isLoading = false;
    });
    app_config.Config.setImageUrls(_images);
    // UserSharedPrefs.saveWallpapers(_images);
  }

  void _showFilters(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Text(
                    "Filters",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 16),

                  // 🔹 Sorting
                  const Text(
                    "Sorting",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Wrap(
                    spacing: 8,
                    children:
                        [
                          "date_added",
                          "relevance",
                          "random",
                          "views",
                          "favorites",
                          "toplist",
                        ].map((e) {
                          return ChoiceChip(
                            label: Text(e),
                            selected: _selectedSorting == e,
                            onSelected: (_) {
                              setModalState(() => _selectedSorting = e);
                            },
                          );
                        }).toList(),
                  ),

                  const SizedBox(height: 16),

                  // 🔹 Purity
                  const Text(
                    "Purity",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Wrap(
                    spacing: 8,
                    children: ["SFW", "Sketchy", "NSFW"].map((e) {
                      return ChoiceChip(
                        label: Text(e),
                        selected: _selectedPurity == e,
                        onSelected: (_) {
                          setModalState(() => _selectedPurity = e);
                        },
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 16),

                  // 🔹 Orientation
                  const Text(
                    "Orientation",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Wrap(
                    spacing: 8,
                    children: ["landscape", "portrait", "squarish"].map((e) {
                      return ChoiceChip(
                        label: Text(e),
                        selected: _selectedOrientation == e,
                        onSelected: (_) {
                          setModalState(() => _selectedOrientation = e);
                        },
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 16),

                  // 🔹 Category
                  const Text(
                    "Category",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Wrap(
                    spacing: 8,
                    children: ["general", "anime", "people"].map((e) {
                      return ChoiceChip(
                        label: Text(e),
                        selected: _selectedCategory == e,
                        onSelected: (_) {
                          setModalState(() => _selectedCategory = e);
                        },
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 16),

                  // 🔹 Range
                  const Text(
                    "Range",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Wrap(
                    spacing: 8,
                    children: ["1D", "3D", "1W", "1M", "3M", "6M", "1Y"].map((
                      e,
                    ) {
                      return ChoiceChip(
                        label: Text(e),
                        selected: _selectedRange == e,
                        onSelected: (_) {
                          setModalState(() => _selectedRange = e);
                        },
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 24),

                  // 🔹 Buttons aligned bottom-right
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedSorting = null;
                            _selectedPurity = null;
                            _selectedOrientation = null;
                            _selectedCategory = null;
                            _selectedRange = null;
                          });
                          Navigator.pop(context);
                          _fetchImages(isSearch: true);
                        },
                        child: const Text("Clear"),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _fetchImages(
                            query: _searchController.text.isNotEmpty
                                ? _searchController.text
                                : null,
                            isSearch: true,
                          );
                        },
                        child: const Text("Apply"),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: const Text("Discover"),
        elevation: 0,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SizedBox(height: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height: _showTopBar ? 120 : 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _showTopBar
                  ? Column(
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.filter_list),
                              label: const Text("Filters"),
                              onPressed: () => _showFilters(context),
                            ),
                          ],
                        ),
                      ],
                    )
                  : null,
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
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                      itemCount: _images.length,
                      // Performance optimizations
                      addAutomaticKeepAlives:
                          PerformanceConfig.addAutomaticKeepAlives,
                      addRepaintBoundaries:
                          PerformanceConfig.addRepaintBoundaries,
                      addSemanticIndexes: false, // Reduce overhead
                      cacheExtent: PerformanceConfig.gridCacheExtent.toDouble(),
                      itemBuilder: (context, index) {
                        final img = _images[index];
                        final isFav = favorites.contains(img);

                        return RepaintBoundary(
                          child: ImageTile(
                            wallpaper: img,
                            isFav: isFav,
                            onFavToggle: () {
                              setState(() {
                                if (isFav) {
                                  favorites.remove(img.url);
                                  UserSharedPrefs.removeFavWallpaper(img);
                                } else {
                                  favorites.add(img.url);
                                  UserSharedPrefs.saveFavWallpaper(img);
                                }
                              });
                            },
                          ),
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
