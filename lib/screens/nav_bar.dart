import 'package:flutter/material.dart';
import 'package:wallify/screens/discover_page.dart';
import 'package:wallify/screens/favorites_page.dart';
import 'package:wallify/screens/recents_page.dart';
import 'package:wallify/screens/settings_page.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _selectedIndex = 0;
  bool _isNavBarVisible = true;

  List<Widget> get _pages => [
    const DiscoverPage(),
    const FavoritesPage(),
    const HistoryPage(),
    SettingsPage(isNavBarVisible: _isNavBarVisible),
  ];

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      final offset = notification.metrics.pixels;

      if (delta > 0 && offset > 80 && _isNavBarVisible) {
        setState(() => _isNavBarVisible = false);
      } else if (delta < 0 && !_isNavBarVisible) {
        setState(() => _isNavBarVisible = true);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    const navBarHeight = 44.0;

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(
              bottom: _isNavBarVisible ? navBarHeight : 0,
            ),
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: IndexedStack(index: _selectedIndex, children: _pages),
            ),
          ),

          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            left: 12,
            right: 12,
            bottom: _isNavBarVisible ? -8 : -68,
            child: CustomBottomNavBar(
              currentIndex: _selectedIndex,
              onTap: (index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const CustomBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final items = [
      (Icons.explore_outlined, Icons.explore, "Discover"),
      (Icons.favorite_border, Icons.favorite, "Favorites"),
      (Icons.history_rounded, Icons.history, "History"),
      (Icons.settings_outlined, Icons.settings, "Settings"),
    ];

    return Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(24),
      color: colorScheme.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(items.length, (index) {
              final selected = currentIndex == index;

              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => onTap(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? colorScheme.primary.withOpacity(.18)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            selected ? items[index].$2 : items[index].$1,
                            size: 22,
                            color: selected
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          items[index].$3,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: selected
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
