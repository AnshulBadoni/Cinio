import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/state/active_source_cubit.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/source_switcher.dart';
import '../auth/auth_cubit.dart';
import '../auth/auth_screens.dart';

enum DesktopNavTab {
  home,
  search,
  myList,
  downloads,
  settings,
}

class DesktopNavBar extends StatefulWidget {
  const DesktopNavBar({
    super.key,
    required this.currentTab,
    required this.onTabSelected,
    this.onSearchSubmitted,
  });

  final DesktopNavTab currentTab;
  final ValueChanged<DesktopNavTab> onTabSelected;
  final ValueChanged<String>? onSearchSubmitted;

  @override
  State<DesktopNavBar> createState() => _DesktopNavBarState();
}

class _DesktopNavBarState extends State<DesktopNavBar> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _searchExpanded = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _submitSearch(String query) {
    final clean = query.trim();
    if (clean.isNotEmpty) {
      widget.onSearchSubmitted?.call(clean);
      widget.onTabSelected(DesktopNavTab.search);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: 28),
          decoration: BoxDecoration(
            color: AppColors.bg.withValues(alpha: 0.82),
            border: Border(
              bottom: BorderSide(
                color: AppColors.hairline.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // ── Brand Logo & Wordmark ─────────────────────────
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => widget.onTabSelected(DesktopNavTab.home),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          'assets/icon/app_icon.png',
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Image.asset(
                        'assets/icon/wordmark.png',
                        height: 20,
                        fit: BoxFit.contain,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 40),

              // ── Navigation Links ──────────────────────────────
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _navLink(DesktopNavTab.home, 'Home', Icons.home_rounded),
                  _navLink(DesktopNavTab.search, 'Search', Icons.search_rounded),
                  _navLink(DesktopNavTab.myList, 'My List', Icons.bookmark_rounded),
                  _navLink(DesktopNavTab.downloads, 'Downloads', Icons.download_rounded),
                  _navLink(DesktopNavTab.settings, 'Settings', Icons.settings_rounded),
                ],
              ),

              const Spacer(),

              // ── Right Utilities ───────────────────────────────
              // 1. Expandable Search Input
              _searchBar(),
              const SizedBox(width: 16),

              // 2. Active Source Pill
              BlocBuilder<ActiveSourceCubit, String>(
                bloc: sl<ActiveSourceCubit>(),
                builder: (context, activeSource) {
                  return SourceSwitcher(
                    currentId: activeSource,
                    onChanged: (id) => sl<ActiveSourceCubit>().setSource(id),
                  );
                },
              ),
              const SizedBox(width: 16),

              // 3. User Profile Avatar
              _avatarButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navLink(DesktopNavTab tab, String label, IconData icon) {
    final isActive = widget.currentTab == tab;

    return _DesktopNavButton(
      label: label,
      icon: icon,
      isActive: isActive,
      onTap: () => widget.onTabSelected(tab),
    );
  }

  Widget _searchBar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: _searchExpanded ? 240 : 160,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _searchExpanded
              ? AppColors.accent.withValues(alpha: 0.8)
              : AppColors.hairline,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: 18,
            color: _searchExpanded ? AppColors.accent : AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              style: AppText.body.copyWith(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Titles, genres...',
                hintStyle: AppText.caption.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 13,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onTap: () {
                if (!_searchExpanded) {
                  setState(() => _searchExpanded = true);
                }
              },
              onSubmitted: _submitSearch,
            ),
          ),
          if (_searchCtrl.text.isNotEmpty)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  _searchCtrl.clear();
                  setState(() {});
                },
                child: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _avatarButton(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      bloc: sl<AuthCubit>(),
      builder: (context, auth) {
        final loggedIn = auth.isLoggedIn;
        final name = loggedIn ? auth.displayName : '';
        final initial = (loggedIn && name.isNotEmpty)
            ? name[0].toUpperCase()
            : null;
        final avatar = auth.avatarUrl;

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {
              if (loggedIn) {
                widget.onTabSelected(DesktopNavTab.settings);
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LoginScreen(),
                  ),
                );
              }
            },
            child: CircleAvatar(
              radius: 17,
              backgroundColor: AppColors.surface2,
              backgroundImage: (avatar != null && avatar.isNotEmpty)
                  ? NetworkImage(avatar)
                  : null,
              child: (avatar == null || avatar.isEmpty)
                  ? (initial != null
                      ? Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : const Icon(
                          Icons.person_rounded,
                          color: AppColors.textSecondary,
                          size: 20,
                        ))
                  : null,
            ),
          ),
        );
      },
    );
  }
}

class _DesktopNavButton extends StatefulWidget {
  const _DesktopNavButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_DesktopNavButton> createState() => _DesktopNavButtonState();
}

class _DesktopNavButtonState extends State<_DesktopNavButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.isActive
        ? AppColors.textPrimary
        : (_hovered ? AppColors.textPrimary : AppColors.textSecondary);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.icon,
                    size: 16,
                    color: color,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight:
                          widget.isActive ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                height: 2,
                width: widget.isActive ? 24 : (_hovered ? 12 : 0),
                decoration: BoxDecoration(
                  color: widget.isActive
                      ? AppColors.accent
                      : (_hovered ? AppColors.textTertiary : Colors.transparent),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
