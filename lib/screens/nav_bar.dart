import 'package:flutter/material.dart';
import 'package:wallify/core/user_shared_prefs.dart';
import 'package:wallify/screens/settings_page.dart';
import 'package:wallify/screens/discover_page.dart';
import 'package:wallify/screens/recents_page.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const DiscoverPage(),
    const FavoritesHistoryPage(),
    const SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: _pages[_selectedIndex],

      /// Material 3 NavigationBar
      bottomNavigationBar: NavigationBar(
        elevation:4,
        selectedIndex: _selectedIndex,
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primary.withValues(alpha: 0.2),
        onDestinationSelected: (index) async {

          setState(() => _selectedIndex = index);
      
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
