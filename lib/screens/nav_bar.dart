import 'package:flutter/material.dart';
import 'package:wallify/screens/settings_page.dart';
import 'package:wallify/screens/discover_page.dart';
import 'package:wallify/screens/recents_page.dart';
import 'package:wallify/screens/favorites_page.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  bool _isNavBarVisible = true;
  late AnimationController _animController;

  final List<Widget> _pages = [
    const DiscoverPage(),
    const FavoritesPage(),
    const HistoryPage(),
    const SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      final metrics = notification.metrics;
      final delta = notification.scrollDelta ?? 0;
      final offset = metrics.pixels;

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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBody: true,
      body: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.08, 0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                )),
                child: child,
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey(_selectedIndex),
            child: _pages[_selectedIndex],
          ),
        ),
      ),
      bottomNavigationBar: AnimatedSlide(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
        offset: _isNavBarVisible ? Offset.zero : const Offset(0, 1),
        child: NavigationBar(
          elevation: 4,
          selectedIndex: _selectedIndex,
          backgroundColor: colorScheme.surface,
          indicatorColor: colorScheme.primary.withValues(alpha: 0.2),
          animationDuration: const Duration(milliseconds: 300),
          onDestinationSelected: (index) {
            setState(() {
              _selectedIndex = index;
              _animController.reset();
              _animController.forward();
            });
          },
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.explore_outlined, color: colorScheme.onSurface),
              selectedIcon: Icon(Icons.explore, color: colorScheme.primary),
              label: "Discover",
            ),
            NavigationDestination(
              icon: Icon(Icons.favorite_border, color: colorScheme.onSurface),
              selectedIcon: Icon(Icons.favorite, color: colorScheme.primary),
              label: "Favorites",
            ),
            NavigationDestination(
              icon: Icon(Icons.history_rounded, color: colorScheme.onSurface),
              selectedIcon: Icon(Icons.history, color: colorScheme.primary),
              label: "History",
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined, color: colorScheme.onSurface),
              selectedIcon: Icon(Icons.settings, color: colorScheme.primary),
              label: "Settings",
            ),
          ],
        ),
      ),
    );
  }
}
