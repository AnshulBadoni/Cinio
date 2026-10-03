import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../downloads/downloads_screen.dart';
import '../home/desktop/desktop_home_screen.dart';
import '../home/my_list_screen.dart';
import '../home/search_screen.dart';
import '../settings/settings_screen.dart';
import 'desktop_nav_bar.dart';

/// Top-level shell for desktop platforms (Windows, macOS, Linux).
/// Features a cinematic transparent navbar sitting directly over the hero,
/// reactive scroll compaction, and fast mouse/keyboard interactions.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  DesktopNavCategory _category = DesktopNavCategory.home;
  bool _isScrolled = false;
  final ValueNotifier<int> _searchFocusSignal = ValueNotifier<int>(0);
  String? _pendingSearchQuery;

  void _onCategorySelected(DesktopNavCategory category) {
    setState(() => _category = category);
  }

  void _onSearchSubmitted(String query) {
    setState(() {
      _pendingSearchQuery = query;
      _category = DesktopNavCategory.collections; // routing to search
    });
    _searchFocusSignal.value++;
  }

  int get _tabIndex {
    return switch (_category) {
      DesktopNavCategory.home => 0,
      DesktopNavCategory.tvShows => 0,
      DesktopNavCategory.movies => 0,
      DesktopNavCategory.newAndPopular => 0,
      DesktopNavCategory.myList => 2,
      DesktopNavCategory.collections => 4,
    };
  }

  @override
  void dispose() {
    _searchFocusSignal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Non-home screens need top padding so their headers aren't overlapped
    // by the floating top navbar.
    const topInset = EdgeInsets.only(top: 68);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis == Axis.vertical) {
            final scrolled = notification.metrics.pixels > 25;
            if (scrolled != _isScrolled) {
              setState(() => _isScrolled = scrolled);
            }
          }
          return false;
        },
        child: Stack(
          children: [
            // ── Tab Views (IndexedStack preserves scroll and state) ──
            Positioned.fill(
              child: IndexedStack(
                index: _pendingSearchQuery != null ? 1 : _tabIndex,
                children: [
                  DesktopHomeScreen(selectedCategory: _category),
                  Padding(
                    padding: topInset,
                    child: SearchScreen(
                      showBack: false,
                      focusSignal: _searchFocusSignal,
                      initialQuery: _pendingSearchQuery,
                    ),
                  ),
                  const Padding(
                    padding: topInset,
                    child: MyListScreen(),
                  ),
                  const Padding(
                    padding: topInset,
                    child: DownloadsScreen(showBack: false),
                  ),
                  const Padding(
                    padding: topInset,
                    child: SettingsScreen(),
                  ),
                ],
              ),
            ),

            // ── Top Cinematic Floating Desktop Navigation Bar ───────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: DesktopNavBar(
                currentCategory: _category,
                onCategorySelected: (cat) {
                  if (_pendingSearchQuery != null) {
                    setState(() => _pendingSearchQuery = null);
                  }
                  _onCategorySelected(cat);
                },
                onSearchSubmitted: _onSearchSubmitted,
                isScrolled: _isScrolled,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
