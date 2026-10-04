import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../detail/detail_screen.dart';
import '../downloads/downloads_screen.dart';
import '../home/desktop/desktop_discover_screen.dart';
import '../home/desktop/desktop_home_screen.dart';
import '../home/my_list_screen.dart';
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
  final TextEditingController _searchCtrl = TextEditingController();

  void _onCategorySelected(DesktopNavCategory category) {
    setState(() => _category = category);
  }

  int get _tabIndex {
    return switch (_category) {
      DesktopNavCategory.home => 0,
      DesktopNavCategory.discover => 1,
      DesktopNavCategory.library => 2,
      DesktopNavCategory.downloads => 3,
      DesktopNavCategory.profile => 4,
    };
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
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
                index: _tabIndex,
                children: [
                  DesktopHomeScreen(selectedCategory: _category),
                  DesktopDiscoverScreen(
                    searchController: _searchCtrl,
                    onOpenDetail: (item) {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => DetailScreen(item: item),
                        ),
                      );
                    },
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
                onCategorySelected: _onCategorySelected,
                searchController: _searchCtrl,
                isScrolled: _isScrolled,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

