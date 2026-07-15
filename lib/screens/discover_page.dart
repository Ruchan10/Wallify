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
import 'package:wallify/functions/shimmer_widget.dart';
import 'package:wallify/model/wallpaper_model.dart';
import 'package:wallify/core/snackbar.dart';

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<Wallpaper> _images = app_config.Config.getImageUrls();
  bool _isLoading = false;
  int count = 1;
  final ScrollController _scrollController = ScrollController();

  String? _lastQuery;
  final ValueNotifier<Set<String>> _favoritesNotifier = ValueNotifier({});
  final ValueNotifier<bool> _showTopBarNotifier = ValueNotifier(true);
  String? _selectedSorting;
  String? _selectedPurity;
  String? _selectedOrientation;
  String? _selectedCategory;
  String _selectedRange = "1M";
  double _lastOffset = 0;
  List<String> _userTags = [];
  bool _tagFilterActive = false;

  static const int maxImages = PerformanceConfig.maxImagesInMemory;

  @override
  void initState() {
    super.initState();
    if (app_config.Config.getImageUrls().isEmpty) {
      _fetchImages();
    }
    _scrollController.addListener(_onScroll);
    initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 5), () {
        if (app_config.Config.getUpdateAvailable()) {
          UpdateManager.showUpdateDialog(context);
        }
      });
    });
  }

  void initialize() async {
    UserSharedPrefs.getFavWallpapers().then((value) {
      _favoritesNotifier.value = {...value.map((e) => e.url)};
    });
    UserSharedPrefs.getTags().then((tags) {
      setState(() => _userTags = tags);
    });
    final sorting = await UserSharedPrefs.getFilterSorting();
    final purity = await UserSharedPrefs.getFilterPurity();
    final orientation = await UserSharedPrefs.getFilterOrientation();
    final category = await UserSharedPrefs.getFilterCategory();
    final range = await UserSharedPrefs.getFilterRange();
    if (mounted) {
      _selectedSorting = sorting;
      _selectedPurity = purity;
      _selectedOrientation = orientation;
      _selectedCategory = category;
      if (range != null) _selectedRange = range;
    }
  }

  void _onScroll() {
    if (!mounted) return;

    final offset = _scrollController.position.pixels;

    if (offset > _lastOffset && _showTopBarNotifier.value && offset > 50) {
      _showTopBarNotifier.value = false;
      _searchFocus.unfocus();
    } else if (offset < _lastOffset && !_showTopBarNotifier.value) {
      _showTopBarNotifier.value = true;
    }

    _lastOffset = offset;

    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300 &&
        !_isLoading &&
        _images.length < maxImages) {
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
    _searchFocus.dispose();
    _favoritesNotifier.dispose();
    _showTopBarNotifier.dispose();
    super.dispose();
  }

  Future<void> _fetchImages({String? query, bool isSearch = false}) async {
    setState(() {
      _isLoading = true;
      if (query != null && isSearch) _lastQuery = query;
    });

    final List<Wallpaper> results = [];

    Future<List<Wallpaper>> _fetchWallhaven() async {
      final res = await http
          .get(
            Uri.parse(
              "https://wallhaven.cc/api/v1/search?"
              "page=$count"
              "${"&topRange=$_selectedRange"}"
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
              "&sorting=${_selectedSorting == null ? "toplist" : "${_selectedRange == "1M" ? _selectedSorting : "toplist"}"}"
              "${query == null ? "" : "&q=$query"}"
              "&order=asc",
            ),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body);
      final list = <Wallpaper>[];
      if (data["data"] is List)
        for (var item in data["data"]) {
          list.add(
            Wallpaper(
              id: item["id"],
              url: item["path"],
              timestamp: DateTime.now(),
            ),
          );
        }
      return list;
    }

    Future<List<Wallpaper>> _fetchUnsplash() async {
      final res = await http
          .get(
            Uri.parse(
              "${query == null ? "https://api.unsplash.com/photos" : "https://api.unsplash.com/search/photos"}"
              "${query == null ? "" : "&query=$query"}"
              "${query == null
                  ? "?order_by=popular"
                  : _selectedSorting == null
                  ? ""
                  : "&order_by=${_selectedSorting == "dater_added" ? "latest" : "relevant"}"}"
              "${_selectedPurity == null ? "" : "&content_filter=${_selectedPurity == "NSFW" ? "high" : "low"}"}"
              "${_selectedOrientation == null ? "" : "&orientation=$_selectedOrientation"}"
              "&page=$count",
            ),
            headers: {
              "Authorization":
                  "Client-ID yTBcYNAtnRHbrYMn2p4DrBiqzOAfdH9nyexQQtJWO-E",
            },
          )
          .timeout(const Duration(seconds: 15));
      final unsplashData = jsonDecode(res.body);
      final list = <Wallpaper>[];
      if (query == null) {
        if (unsplashData is List)
          for (var item in unsplashData) {
            list.add(
              Wallpaper(
                id: item["id"],
                url: item["urls"]["regular"],
                timestamp: DateTime.now(),
              ),
            );
          }
      } else {
        if (unsplashData["results"] is List)
          for (var item in unsplashData["results"]) {
            list.add(
              Wallpaper(
                id: item["id"],
                url: item["urls"]["regular"],
                timestamp: DateTime.now(),
              ),
            );
          }
      }
      return list;
    }

    Future<List<Wallpaper>> _fetchPixabay() async {
      final pixabayQuery = query != null && query!.length > 99 ? query!.substring(0, 99) : query;
      final res = await http
          .get(
            Uri.parse(
              "https://pixabay.com/api/"
              "?key=52028006-a7e910370a5d0158c371bb06a"
              "${pixabayQuery == null ? "" : "&q=$pixabayQuery"}"
              "&image_type=photo"
              "${_selectedPurity == null ? "" : "&safesearch=${_selectedPurity == "NSFW" ? "false" : "true"}"}"
              "${_selectedSorting == null ? "&order=popular" : "&order=${_selectedSorting == "dater_added" ? "latest" : "popular"}"}"
              "${_selectedOrientation == null ? "" : "&orientation=$_selectedOrientation"}"
              "&page=$count",
            ),
          )
          .timeout(const Duration(seconds: 15));
      final pixabayData = jsonDecode(res.body);
      final list = <Wallpaper>[];
      if (pixabayData["hits"] is List)
        for (var item in pixabayData["hits"]) {
          list.add(
            Wallpaper(
              id: item["id"].toString(),
              url: item["largeImageURL"],
              timestamp: DateTime.now(),
            ),
          );
        }
      return list;
    }

    final apiResults = await Future.wait([
      _fetchWallhaven().catchError((e) {
        debugPrint("Wallhaven failed: $e");
        return <Wallpaper>[];
      }),
      _fetchUnsplash().catchError((e) {
        debugPrint("Unsplash failed: $e");
        return <Wallpaper>[];
      }),
      _fetchPixabay().catchError((e) {
        debugPrint("Pixabay failed: $e");
        return <Wallpaper>[];
      }),
    ]);
    for (final apiList in apiResults) {
      results.addAll(apiList);
    }
    results.shuffle();
    if (results.isEmpty && mounted) {
      showSnackBar(
        context: context,
        message: "Could not fetch wallpapers — check your connection",
        color: Colors.red,
      );
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
    if (_tagFilterActive) {
      UserSharedPrefs.saveWallpapers(_images);
    }
  }

  void _showFilters(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Filters",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          UserSharedPrefs.setFilterSorting(null);
                          UserSharedPrefs.setFilterPurity(null);
                          UserSharedPrefs.setFilterOrientation(null);
                          UserSharedPrefs.setFilterCategory(null);
                          UserSharedPrefs.setFilterRange(null);
                          setState(() {
                            _selectedSorting = null;
                            _selectedPurity = null;
                            _selectedOrientation = null;
                            _selectedCategory = null;
                            _selectedRange = "1M";
                          });
                          Navigator.pop(context);
                          count = 1;
                          _fetchImages(isSearch: true);
                        },
                        child: const Text("Reset"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildFilterSection(
                    "Sorting",
                    [
                      "date_added",
                      "relevance",
                      "random",
                      "views",
                      "favorites",
                      "toplist",
                    ],
                    _selectedSorting,
                    (val) => setModalState(() => _selectedSorting = val),
                  ),
                  const SizedBox(height: 16),
                  _buildFilterSection(
                    "Purity",
                    ["SFW", "Sketchy", "NSFW"],
                    _selectedPurity,
                    (val) => setModalState(() => _selectedPurity = val),
                  ),
                  const SizedBox(height: 16),
                  _buildFilterSection(
                    "Orientation",
                    ["landscape", "portrait", "squarish"],
                    _selectedOrientation,
                    (val) => setModalState(() => _selectedOrientation = val),
                  ),
                  const SizedBox(height: 16),
                  _buildFilterSection(
                    "Category",
                    ["general", "anime", "people"],
                    _selectedCategory,
                    (val) => setModalState(() => _selectedCategory = val),
                  ),
                  const SizedBox(height: 16),
                  _buildFilterSection(
                    "Range",
                    ["1D", "3D", "1W", "1M", "3M", "6M", "1Y"],
                    _selectedRange,
                    (val) => setModalState(() => _selectedRange = val),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        UserSharedPrefs.setFilterSorting(_selectedSorting);
                        UserSharedPrefs.setFilterPurity(_selectedPurity);
                        UserSharedPrefs.setFilterOrientation(
                          _selectedOrientation,
                        );
                        UserSharedPrefs.setFilterCategory(_selectedCategory);
                        UserSharedPrefs.setFilterRange(_selectedRange);
                        Navigator.pop(context);
                        count = 1;
                        _fetchImages(
                          query: _searchController.text.isNotEmpty
                              ? _searchController.text
                              : null,
                          isSearch: true,
                        );
                      },
                      child: const Text("Apply Filters"),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterSection(
    String title,
    List<String> options,
    String? selected,
    ValueChanged<String> onSelected,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: options.map((e) {
            final isSelected = selected == e;
            return ChoiceChip(
              label: Text(e),
              selected: isSelected,
              backgroundColor: colorScheme.surfaceContainerHighest,
              selectedColor: colorScheme.primary.withValues(alpha: 0.2),
              labelStyle: TextStyle(
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
              onSelected: (_) => onSelected(e),
              shape: StadiumBorder(
                side: BorderSide(
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.outlineVariant,
                ),
              ),
            );
          }).toList(),
        ),
      ],
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
            ValueListenableBuilder<bool>(
              valueListenable: _showTopBarNotifier,
              builder: (context, showTopBar, child) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeInOutCubic,
                  height: showTopBar ? 120 : 0,
                  child: Column(
                    children: [
                      SizedBox(
                        height: 48,
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocus,
                          decoration: InputDecoration(
                            hintText: "Search wallpapers...",
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _searchController,
                              builder: (context, value, child) {
                                return value.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          _searchController.clear();
                                          _lastQuery = null;
                                          _images.clear();
                                          _tagFilterActive = false;
                                          _fetchImages();
                                        },
                                      )
                                    : const SizedBox.shrink();
                              },
                            ),
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                          ),
                          onSubmitted: (value) {
                            if (value.isNotEmpty) {
                              setState(() => _tagFilterActive = false);
                              _fetchImages(query: value.trim(), isSearch: true);
                            }
                          },
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (_userTags.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: TextButton.icon(
                              icon: Icon(
                                _tagFilterActive
                                    ? Icons.bookmark
                                    : Icons.bookmark_border,
                                size: 20,
                              ),
                              label: Text(
                                _tagFilterActive
                                    ? "Your Wallpapers (on)"
                                    : "Your Wallpapers",
                              ),
                              onPressed: () {
                                if (_tagFilterActive) {
                                  setState(() {
                                    _tagFilterActive = false;
                                    _searchController.clear();
                                    _lastQuery = null;
                                    _images.clear();
                                  });
                                  _fetchImages();
                                  _scrollController.animateTo(
                                    0,
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                } else {
                                  final tags = _userTags.join(",");
                                  _searchController.text = tags;
                                  setState(() {
                                    _images.clear();
                                    _isLoading = true;
                                  });
                                  _fetchImages(query: tags, isSearch: true);
                                  setState(() => _tagFilterActive = true);
                                  _scrollController.animateTo(
                                    0,
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                }
                              },
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: TextButton.icon(
                            icon: const Icon(Icons.filter_list, size: 20),
                            label: const Text("Filters"),
                            onPressed: () => _showFilters(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),

            if (_lastQuery != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Showing results for \"$_lastQuery\"",
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),

            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  count = 1;
                  _images.clear();
                  await _fetchImages(
                    query: _searchController.text.isNotEmpty
                        ? _searchController.text
                        : null,
                  );
                },
                child: _images.isEmpty
                    ? MasonryGridView.count(
                        crossAxisCount: 2,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        itemCount: 6,
                        itemBuilder: (context, index) => ShimmerLoading(
                          height: 150 + (index % 3) * 50,
                          borderRadius: 12,
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
                        itemCount: _images.length + (_isLoading ? 4 : 0),
                        addAutomaticKeepAlives:
                            PerformanceConfig.addAutomaticKeepAlives,
                        addRepaintBoundaries:
                            PerformanceConfig.addRepaintBoundaries,
                        addSemanticIndexes: false,
                        cacheExtent: PerformanceConfig.gridCacheExtent
                            .toDouble(),
                        itemBuilder: (context, index) {
                          if (index >= _images.length) {
                            return ShimmerLoading(
                              height: 150 + (index % 3) * 50,
                              borderRadius: 12,
                            );
                          }

                          final img = _images[index];
                          final isFav = _favoritesNotifier.value.contains(img.url);

                          return RepaintBoundary(
                            child: ImageTile(
                              wallpaper: img,
                              isFav: isFav,
                              allWallpapers: _images,
                              index: index,
                              onFavToggle: () {
                                final updated = Set<String>.from(_favoritesNotifier.value);
                                if (isFav) {
                                  updated.remove(img.url);
                                  UserSharedPrefs.removeFavWallpaper(img);
                                } else {
                                  updated.add(img.url);
                                  UserSharedPrefs.saveFavWallpaper(img);
                                }
                                _favoritesNotifier.value = updated;
                              },
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
