import 'package:flutter/material.dart';
import 'package:wallify/screens/settings_page.dart';
import 'package:wallify/screens/discover_page.dart';
import 'package:wallify/screens/recents_page.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;

  final List<Widget> _pages = [
    const DiscoverPage(),
    const FavoritesHistoryPage(),
    const SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.15, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: AnimatedSwitcher(
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
      bottomNavigationBar: NavigationBar(
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
            icon: Icon(Icons.history_rounded, color: colorScheme.onSurface),
            selectedIcon: Icon(Icons.history, color: colorScheme.primary),
            label: "Recents",
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined, color: colorScheme.onSurface),
            selectedIcon: Icon(Icons.settings, color: colorScheme.primary),
            label: "Settings",
          ),
        ],
      ),
    );
  }
}
