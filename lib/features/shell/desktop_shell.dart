import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../downloads/downloads_screen.dart';
import '../home/home_screen.dart';
import '../home/my_list_screen.dart';
import '../home/search_screen.dart';
import '../settings/settings_screen.dart';
import 'desktop_nav_bar.dart';

/// Top-level shell for desktop platforms (Windows, macOS, Linux).
/// Adopts a modern widescreen streaming desktop layout inspired by the
/// Netflix desktop concept: translucent glass top navigation bar,
/// responsive content area, and instant keyboard/mouse navigation.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  DesktopNavTab _tab = DesktopNavTab.home;
  final ValueNotifier<int> _searchFocusSignal = ValueNotifier<int>(0);
  String? _pendingSearchQuery;

  void _onTabSelected(DesktopNavTab tab) {
    if (tab == _tab) {
      if (tab == DesktopNavTab.search) {
        _searchFocusSignal.value++;
      }
      return;
    }
    setState(() => _tab = tab);
    if (tab == DesktopNavTab.search) {
      _searchFocusSignal.value++;
    }
  }

  void _onSearchSubmitted(String query) {
    setState(() {
      _pendingSearchQuery = query;
      _tab = DesktopNavTab.search;
    });
    _searchFocusSignal.value++;
  }

  int get _tabIndex {
    return switch (_tab) {
      DesktopNavTab.home => 0,
      DesktopNavTab.search => 1,
      DesktopNavTab.myList => 2,
      DesktopNavTab.downloads => 3,
      DesktopNavTab.settings => 4,
    };
  }

  @override
  void dispose() {
    _searchFocusSignal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // ── Tab Views (IndexedStack preserves scroll and state) ──
          Positioned.fill(
            child: IndexedStack(
              index: _tabIndex,
              children: [
                const HomeScreen(),
                SearchScreen(
                  showBack: false,
                  focusSignal: _searchFocusSignal,
                  initialQuery: _pendingSearchQuery,
                ),
                const MyListScreen(),
                const DownloadsScreen(showBack: false),
                const SettingsScreen(),
              ],
            ),
          ),

          // ── Top Glassmorphic Navigation Bar ─────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: DesktopNavBar(
              currentTab: _tab,
              onTabSelected: _onTabSelected,
              onSearchSubmitted: _onSearchSubmitted,
            ),
          ),
        ],
      ),
    );
  }
}
