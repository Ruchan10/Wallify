class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  final TextEditingController _searchController = TextEditingController();
  final List<String> _images = Config.getImageUrls();
  final bool _isLoading = false;
  int count = 1;
  final ScrollController _scrollController = ScrollController();

  String? _lastQuery;
  final Set<String> favorites = {};
  String? _selectedSorting;
  String? _selectedPurity;
  String? _selectedOrientation;
  String? _selectedCategory;
  String? _selectedRange;

  bool _showTopBar = true; // 👈 track visibility
  double _lastOffset = 0;  // 👈 track last scroll position

  @override
  void initState() {
    super.initState();
    if (Config.getImageUrls().isEmpty) {
      _fetchImages();
    }

    _scrollController.addListener(() {
      final offset = _scrollController.position.pixels;

      // Hide when scrolling down, show when scrolling up
      if (offset > _lastOffset && _showTopBar) {
        setState(() => _showTopBar = false);
      } else if (offset < _lastOffset && !_showTopBar) {
        setState(() => _showTopBar = true);
      }

      _lastOffset = offset;

      // Pagination
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200 &&
          !_isLoading) {
        count++;
        _fetchImages(query: _searchController.text.isNotEmpty
            ? _searchController.text
            : null);
      }
    });
  }

  // ... keep your _fetchImages and _showFilters methods ...

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            /// 🔹 Animated Top Bar (Search + Filter)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height: _showTopBar ? 100 : 0, // 👈 collapse height
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _showTopBar
                  ? Column(
                      spacing: 8,
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

            if (_lastQuery != null && _showTopBar)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 8),
                  child: Text(
                    "Showing results for \"$_lastQuery\"",
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),

            /// 🔹 Images Grid
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
