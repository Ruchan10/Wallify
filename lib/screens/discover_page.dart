import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:wallify/core/config.dart' as app_config;
import 'package:wallify/core/performance_config.dart';
import 'package:wallify/core/update_manager.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/functions/image_card.dart';
import 'package:wallify/functions/shimmer_widget.dart';
import 'package:wallify/main.dart';
import 'package:wallify/model/wallpaper_model.dart';
import 'package:wallify/core/navigation_service.dart';
import 'package:wallify/core/snackbar.dart';
import 'package:wallify/services/wallpaper_api_service.dart';

/// What the Discover grid is showing.
enum _Feed { browse, search, forYou, topPicks }

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ValueNotifier<List<Wallpaper>> _imagesNotifier = ValueNotifier(
    app_config.Config.getImageUrls(),
  );
  bool _isLoading = false;

  /// Set when the sources have nothing more for the current feed.
  bool _exhausted = false;
  int _emptyPages = 0;
  final ScrollController _scrollController = ScrollController();

  _Feed _feed = _Feed.browse;

  /// The query of the current search feed.
  String? _query;

  /// Identifies the latest load; results of older ones are dropped, so a new
  /// search never shows (or waits behind) a previous one.
  int _requestId = 0;

  final ValueNotifier<Set<String>> _favoritesNotifier = ValueNotifier({});
  final ValueNotifier<bool> _showTopBarNotifier = ValueNotifier(true);
  String? _selectedSorting;
  String? _selectedPurity;
  String? _selectedOrientation;
  String? _selectedCategory;
  String _selectedRange = "1M";
  double _lastOffset = 0;
  List<String> _userTags = [];
  Set<String> _invalidTags = {};
  List<String> _recentSearches = [];
  int _deviceWidth = 1080;
  int _deviceHeight = 2400;

  /// Top Picks period, in Wallhaven's toplist ranges.
  String _topRange = "1w";
  static const _topRanges = [
    (value: "1d", label: "Today"),
    (value: "1w", label: "This week"),
    (value: "1M", label: "This month"),
    (value: "1y", label: "This year"),
  ];

  /// For You searches at most this many tags per page, rotating through all
  /// of them as the user scrolls, to keep each page to a few requests.
  static const _tagsPerPage = 3;
  int _forYouPage = 0;

  static const int maxImages = PerformanceConfig.maxImagesInMemory;

  static const int _initialPerSource = 10;
  static const int _scrollPerSource = 5;

  /// Next page per source (and per tag in For You).
  final Map<String, int> _sourcePages = {};
  static const List<String> _popularTags = [
    "Nature",
    "Landscape",
    "Minimal",
    "Dark",
    "Anime",
    "Abstract",
    "Space",
    "City",
    "Art",
    "Cyberpunk",
    "Neon",
    "Vintage",
    "Gradient",
    "Ocean",
    "Mountains",
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchFocus.addListener(() => setState(() {}));
    initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && app_config.Config.getUpdateAvailable()) {
          UpdateManager.showUpdateDialog(context);
        }
      });
    });
  }

  Future<void> initialize() async {
    UserSharedPrefs.getFavWallpapers().then((value) {
      _favoritesNotifier.value = {...value.map((e) => e.url)};
    });
    final results = await Future.wait<Object?>([
      UserSharedPrefs.getTags(),
      UserSharedPrefs.getInvalidTags(),
      UserSharedPrefs.getRecentSearches(),
      UserSharedPrefs.getDeviceWidth(),
      UserSharedPrefs.getDeviceHeight(),
      UserSharedPrefs.getFilterSorting(),
      UserSharedPrefs.getFilterPurity(),
      UserSharedPrefs.getFilterOrientation(),
      UserSharedPrefs.getFilterCategory(),
      UserSharedPrefs.getFilterRange(),
    ]);
    if (!mounted) return;
    setState(() {
      _userTags = results[0] as List<String>;
      _invalidTags = results[1] as Set<String>;
      _recentSearches = results[2] as List<String>;
      _deviceWidth = results[3] as int;
      _deviceHeight = results[4] as int;
      _selectedSorting = results[5] as String?;
      _selectedPurity = results[6] as String?;
      _selectedOrientation = results[7] as String?;
      _selectedCategory = results[8] as String?;
      _selectedRange = (results[9] as String?) ?? _selectedRange;
    });
    // Load only once the saved filters are known, so they apply from the start.
    if (_imagesNotifier.value.isEmpty) _load(reset: true);
  }

  void _onScroll() {
    if (!mounted) return;

    final offset = _scrollController.position.pixels;
    final delta = (offset - _lastOffset).abs();
    if (delta < 15) return;

    if (offset > _lastOffset && _showTopBarNotifier.value && offset > 50) {
      _showTopBarNotifier.value = false;
      _searchFocus.unfocus();
    } else if (offset < _lastOffset && !_showTopBarNotifier.value) {
      _showTopBarNotifier.value = true;
    }

    _lastOffset = offset;

    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300 &&
        _imagesNotifier.value.length < maxImages) {
      _load();
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
    _imagesNotifier.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- loading

  /// Loads the next page of the current feed, or the first page when [reset].
  Future<void> _load({bool reset = false}) async {
    if (!reset && (_isLoading || _exhausted)) return;
    final requestId = ++_requestId;

    if (reset) {
      _sourcePages.clear();
      _forYouPage = 0;
      _exhausted = false;
      _emptyPages = 0;
      _imagesNotifier.value = [];
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    }
    setState(() => _isLoading = true);

    try {
      final perSource = _imagesNotifier.value.isEmpty
          ? _initialPerSource
          : _scrollPerSource;

      final existing = _imagesNotifier.value;
      final seen = existing.map((e) => e.url).toSet();
      var fresh = <Wallpaper>[];
      // A page can come back empty while later ones aren't: For You drops
      // images that don't fit the screen, and rotates to other tags next
      // page. Only two empty pages in a row mean the feed is done.
      for (var attempt = 0; attempt < 3 && fresh.isEmpty; attempt++) {
        final page = await switch (_feed) {
          _Feed.browse => _fetchBrowse(perSource),
          _Feed.search => _fetchSearch(perSource),
          _Feed.forYou => _fetchForYou(perSource),
          _Feed.topPicks => _fetchTopPicks(perSource),
        };
        if (requestId != _requestId || !mounted) return;
        _emptyPages = page.isEmpty ? _emptyPages + 1 : 0;
        fresh = page.where((w) => seen.add(w.url)).toList();
        if (_emptyPages >= 2) {
          _exhausted = true;
          break;
        }
      }

      if (existing.isEmpty && fresh.isEmpty && _feed == _Feed.browse) {
        final online = ref.read(connectivityProvider).value;
        showSnackBar(
          context: context,
          message: online
              ? "Could not fetch wallpapers — try again later"
              : "You're offline — browse favorites or history",
          color: online ? Colors.red : Colors.orange,
        );
      }

      _imagesNotifier.value = [...existing, ...fresh];
      if (_feed == _Feed.browse) {
        app_config.Config.setImageUrls(_imagesNotifier.value);
      }
      // For You doubles as the auto-change pool: it is the user's tags,
      // fitted to their screen.
      if (_feed == _Feed.forYou && _imagesNotifier.value.isNotEmpty) {
        UserSharedPrefs.saveWallpapers(_imagesNotifier.value);
      }
    } finally {
      if (requestId == _requestId && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Pages through [sources] using one page counter per source and [key].
  Future<List<Wallpaper>> _fetchPage({
    required List<String> sources,
    required FetchOptions Function(String source, int page) optionsFor,
    String key = "",
    bool Function(Wallpaper)? keep,
  }) async {
    final results = await WallpaperApiService.fetchEach(
      sources: sources,
      optionsFor: (source) {
        final pageKey = "$source|$key";
        final page = _sourcePages[pageKey] ?? 1;
        _sourcePages[pageKey] = page + 1;
        return optionsFor(source, page);
      },
    );
    return WallpaperApiService.interleave([
      for (final list in results.values)
        if (list != null) keep == null ? list : list.where(keep).toList(),
    ]);
  }

  FetchOptions _filteredOptions(int page, int perSource, {String? query}) {
    return FetchOptions(
      query: query,
      page: page,
      perPage: perSource,
      sorting: _selectedSorting,
      purity: _selectedPurity,
      orientation: _selectedOrientation,
      category: _selectedCategory,
      range: _selectedRange,
    );
  }

  Future<List<Wallpaper>> _fetchBrowse(int perSource) {
    return _fetchPage(
      sources: [...WallpaperApiService.searchableSources, "lorempicsum"],
      optionsFor: (_, page) => _filteredOptions(page, perSource),
    );
  }

  Future<List<Wallpaper>> _fetchSearch(int perSource) {
    return _fetchPage(
      sources: WallpaperApiService.searchableSources,
      optionsFor: (_, page) =>
          _filteredOptions(page, perSource, query: _query),
    );
  }

  /// The user's tags (or popular wallpapers when there are none), limited to
  /// portrait images large enough for this screen.
  Future<List<Wallpaper>> _fetchForYou(int perSource) async {
    final tags = _userTags.where((t) => !_invalidTags.contains(t)).toList();
    final List<String?> pageTags;
    if (tags.isEmpty) {
      pageTags = [null];
    } else if (tags.length <= _tagsPerPage) {
      pageTags = tags;
    } else {
      final start = (_forYouPage * _tagsPerPage) % tags.length;
      pageTags = [
        for (var i = 0; i < _tagsPerPage; i++) tags[(start + i) % tags.length],
      ];
    }
    _forYouPage++;

    // Ask the sources for images that can fill the screen with little
    // upscaling; [_fitsDevice] then catches sources that ignore the hint.
    final minWidth = (_deviceWidth * 0.75).round();
    final minHeight = (_deviceHeight * 0.75).round();
    final perTag = max(3, (perSource * 1.5 / pageTags.length).ceil());

    final pages = await Future.wait([
      for (final tag in pageTags)
        _fetchPage(
          sources: WallpaperApiService.searchableSources,
          key: tag ?? "",
          keep: _fitsDevice,
          optionsFor: (_, page) => FetchOptions(
            query: tag,
            page: page,
            perPage: perTag,
            sorting: _selectedSorting,
            purity: _selectedPurity ?? "SFW",
            category: _selectedCategory,
            range: _selectedRange,
            orientation: "portrait",
            minWidth: minWidth,
            minHeight: minHeight,
          ),
        ),
    ]);
    return WallpaperApiService.interleave(pages);
  }

  /// Whether [w] can cover this screen: tall enough in shape, and needing at
  /// most ~35% upscaling. Images of unknown size are kept.
  bool _fitsDevice(Wallpaper w) {
    final ratio = w.aspectRatio;
    if (ratio == null) return true;
    if (ratio > 0.8) return false;
    final width = w.width;
    final height = w.height;
    if (width == null || height == null) return true;
    final upscale = max(_deviceWidth / width, _deviceHeight / height);
    return upscale <= 1.35;
  }

  /// Each source's best wallpapers for [_topRange]. Wallhaven ranks by the
  /// period; the others offer their popular / editor's choice / curated feeds.
  Future<List<Wallpaper>> _fetchTopPicks(int perSource) {
    return _fetchPage(
      sources: WallpaperApiService.searchableSources,
      key: _topRange,
      optionsFor: (_, page) => FetchOptions(
        page: page,
        perPage: perSource,
        sorting: "toplist",
        range: _topRange,
        purity: _selectedPurity ?? "SFW",
        category: _selectedCategory,
        orientation: _selectedOrientation,
        bestOf: true,
      ),
    );
  }

  // --------------------------------------------------------------- feeds

  Future<void> _switchFeed(_Feed feed) async {
    if (feed == _Feed.forYou) {
      // Tags and invalid tags may have changed in Settings since Discover
      // was opened.
      final tags = await UserSharedPrefs.getTags();
      final invalid = await UserSharedPrefs.getInvalidTags();
      if (!mounted) return;
      _userTags = tags;
      _invalidTags = invalid;
    }
    setState(() {
      _feed = feed;
      if (feed != _Feed.search) {
        _query = null;
        _searchController.clear();
      }
    });
    _searchFocus.unfocus();
    _load(reset: true);
  }

  void _toggleFeed(_Feed feed) =>
      _switchFeed(_feed == feed ? _Feed.browse : feed);

  /// Searches for [raw], tidied up. An empty query goes back to browsing.
  void _search(String raw) {
    final query = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (query.isEmpty) {
      _switchFeed(_Feed.browse);
      return;
    }
    _searchController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    setState(() {
      _feed = _Feed.search;
      _query = query;
    });
    _searchFocus.unfocus();
    UserSharedPrefs.addRecentSearch(query).then((list) {
      if (mounted) setState(() => _recentSearches = list);
    });
    _load(reset: true);
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
            return SingleChildScrollView(
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
                          _load(reset: true);
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
                        _load(reset: true);
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

  // ---------------------------------------------------------- search UI

  Widget _suggestionChip(
    String label,
    ColorScheme colors, {
    IconData? icon,
    bool active = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        avatar: icon == null
            ? null
            : Icon(icon, size: 16, color: colors.onSurfaceVariant),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        backgroundColor: active
            ? colors.primary.withValues(alpha: 0.25)
            : colors.surfaceContainerHighest.withValues(alpha: 0.5),
        labelStyle: TextStyle(
          color: active ? colors.primary : colors.onSurfaceVariant,
          fontWeight: active ? FontWeight.w600 : FontWeight.normal,
        ),
        onPressed: () => _search(label),
        shape: StadiumBorder(
          side: BorderSide(
            color: active ? colors.primary : colors.outlineVariant,
          ),
        ),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  /// Ranks [candidates] for [query]: prefix matches, then word-start
  /// matches, then any match.
  static List<String> _rankMatches(String query, Iterable<String> candidates) {
    int score(String c) {
      final l = c.toLowerCase();
      if (l == query) return -1; // already typed in full; not useful
      if (l.startsWith(query)) return 0;
      if (l.split(RegExp(r'[\s,]+')).any((w) => w.startsWith(query))) return 1;
      if (l.contains(query)) return 2;
      return 3;
    }

    final seen = <String>{};
    final ranked = [
      for (final c in candidates)
        if (seen.add(c.toLowerCase()) && score(c) >= 0 && score(c) < 3) c,
    ]..sort((a, b) => score(a).compareTo(score(b)));
    return ranked;
  }

  Widget _searchSuggestions(ColorScheme colors) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _searchController,
      builder: (context, value, _) {
        final query = value.text.trim().toLowerCase();
        final List<Widget> chips;

        if (query.isEmpty || query == _query?.toLowerCase()) {
          // Recent searches while typing a new one, popular tags otherwise.
          final recent = _searchFocus.hasFocus ? _recentSearches : <String>[];
          chips = [
            for (final q in recent) _suggestionChip(q, colors, icon: Icons.history),
            if (recent.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ActionChip(
                  label: const Text("Clear", style: TextStyle(fontSize: 12)),
                  onPressed: () {
                    UserSharedPrefs.clearRecentSearches();
                    setState(() => _recentSearches = []);
                  },
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            if (recent.isEmpty)
              for (final tag in _popularTags)
                _suggestionChip(
                  tag,
                  colors,
                  active: _query?.toLowerCase() == tag.toLowerCase(),
                ),
          ];
        } else {
          final matches = _rankMatches(query, [
            ..._recentSearches,
            ..._userTags,
            ..._popularTags,
          ]).take(10);
          chips = [
            for (final m in matches)
              _suggestionChip(
                m,
                colors,
                icon: _recentSearches.contains(m) ? Icons.history : null,
              ),
          ];
        }

        if (chips.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 36,
          child: ListView(scrollDirection: Axis.horizontal, children: chips),
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

  Widget _feedButton({
    required _Feed feed,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final active = _feed == feed;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: TextButton.icon(
        icon: Icon(active ? activeIcon : icon, size: 20),
        label: Text(label),
        style: active
            ? TextButton.styleFrom(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.12),
              )
            : null,
        onPressed: () => _toggleFeed(feed),
      ),
    );
  }

  String? _feedCaption() {
    return switch (_feed) {
      _Feed.browse => null,
      _Feed.search => "Showing results for \"$_query\"",
      _Feed.forYou =>
        "${_userTags.isEmpty ? "Popular wallpapers" : "Your tags"}, "
            "sized for your $_deviceWidth×$_deviceHeight screen",
      _Feed.topPicks =>
        "Top wallpapers from every source — "
            "${_topRanges.firstWhere((r) => r.value == _topRange).label.toLowerCase()}",
    };
  }

  Widget _buildOfflineFallback({required ColorScheme scheme}) {
    return MasonryGridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      padding: const EdgeInsets.only(top: 8),
      itemCount: 1,
      itemBuilder: (_, _) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_off,
              size: 48,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              "You're offline",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Browse your favorites or history below",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => NavigationService.tabNotifier.value = 1,
              icon: const Icon(Icons.favorite, size: 18),
              label: const Text("Favorites"),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => NavigationService.tabNotifier.value = 2,
              icon: const Icon(Icons.history, size: 18),
              label: const Text("History"),
            ),
          ],
        ),
      ),
    );
  }

  /// Shown when an online feed came back empty.
  Widget _buildNoResults(ColorScheme scheme) {
    final message = switch (_feed) {
      _Feed.search => "No wallpapers found for \"$_query\"",
      _Feed.forYou => "Nothing matched your tags at this screen size",
      _ => "No wallpapers found",
    };
    final hint = switch (_feed) {
      _Feed.search => "Try a broader or differently spelled term, "
          "or loosen the filters.",
      _Feed.forYou => "Add broader tags in Settings, or loosen the filters.",
      _ => "Pull down to try again.",
    };
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 48, left: 24, right: 24),
      children: [
        Icon(
          Icons.image_search,
          size: 48,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          hint,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final online = ref.watch(connectivityProvider).value;
    final caption = _feedCaption();

    return Scaffold(
      extendBody: true,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 16.0, left: 16.0, right: 16.0),
          child: Column(
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: _showTopBarNotifier,
                builder: (context, showTopBar, child) {
                  return AnimatedSize(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeInOutCubic,
                    child: showTopBar ? child : const SizedBox.shrink(),
                  );
                },
                child: Column(
                  children: [
                    SizedBox(
                      height: 48,
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocus,
                        textInputAction: TextInputAction.search,
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
                                        if (_feed == _Feed.search) {
                                          _switchFeed(_Feed.browse);
                                        } else {
                                          _searchController.clear();
                                        }
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
                        onSubmitted: _search,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _searchSuggestions(colorScheme),
                    Row(
                      children: [
                        _feedButton(
                          feed: _Feed.forYou,
                          icon: Icons.bookmark_border,
                          activeIcon: Icons.bookmark,
                          label: "For You",
                        ),
                        const SizedBox(width: 4),
                        _feedButton(
                          feed: _Feed.topPicks,
                          icon: Icons.local_fire_department_outlined,
                          activeIcon: Icons.local_fire_department,
                          label: "Top Picks",
                        ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: TextButton.icon(
                            icon: const Icon(Icons.filter_list, size: 20),
                            label: const Text("Filters"),
                            onPressed: () => _showFilters(context),
                          ),
                        ),
                      ],
                    ),
                    if (_feed == _Feed.topPicks)
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final range in _topRanges)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(range.label),
                                  selected: _topRange == range.value,
                                  onSelected: (_) {
                                    if (_topRange == range.value) return;
                                    setState(() => _topRange = range.value);
                                    _load(reset: true);
                                  },
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              if (caption != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      caption,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),

              if (!online)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.wifi_off,
                        size: 16,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Offline — showing saved wallpapers",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ),
                ),

              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _load(reset: true),
                  child: ValueListenableBuilder<List<Wallpaper>>(
                    valueListenable: _imagesNotifier,
                    builder: (context, images, _) {
                      if (images.isEmpty && _isLoading) {
                        return MasonryGridView.count(
                          crossAxisCount: 2,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          itemCount: 6,
                          itemBuilder: (context, index) => ShimmerLoading(
                            height: 150 + (index % 3) * 50,
                            borderRadius: 12,
                          ),
                        );
                      }
                      if (images.isEmpty && !_isLoading) {
                        return online
                            ? _buildNoResults(colorScheme)
                            : _buildOfflineFallback(scheme: colorScheme);
                      }
                      final itemCount =
                          images.length + (_isLoading ? 4 : 0);
                      return MasonryGridView.builder(
                        key: const PageStorageKey("discover_grid"),
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverSimpleGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                            ),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        cacheExtent: PerformanceConfig.gridCacheExtent
                            .toDouble(),
                        itemCount: itemCount,
                        itemBuilder: (context, index) {
                          if (index >= images.length) {
                            return ShimmerLoading(
                              height: 150 + (index % 3) * 50,
                              borderRadius: 12,
                            );
                          }
                          final img = images[index];
                          final isFav = _favoritesNotifier.value.contains(
                            img.url,
                          );
                          return ImageTile(
                            wallpaper: img,
                            isFav: isFav,
                            allWallpapers: images,
                            index: index,
                            onFavToggle: () {
                              final updated = Set<String>.from(
                                _favoritesNotifier.value,
                              );
                              if (isFav) {
                                updated.remove(img.url);
                                UserSharedPrefs.removeFavWallpaper(img);
                              } else {
                                updated.add(img.url);
                                UserSharedPrefs.saveFavWallpaper(img);
                              }
                              _favoritesNotifier.value = updated;
                              setState(() {});
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
