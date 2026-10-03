import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../auth/auth_cubit.dart';
import '../../core/di/injector.dart';
import '../../core/state/active_source_cubit.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/source_switcher.dart';
import '../auth/auth_screens.dart';
import '../notify/subscriptions_screen.dart';

/// Desktop-only top navigation. Phone and TV navigation are separate widgets.
///
/// The desktop treatment intentionally follows the visual language of the
/// supplied reference: a dark cinematic bar, centered text navigation, and a
/// small cluster of circular utilities on the right.
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
  void initState() {
    super.initState();
    _searchFocus.addListener(_handleSearchFocus);
    _searchCtrl.addListener(_handleSearchText);
  }

  @override
  void dispose() {
    _searchFocus
      ..removeListener(_handleSearchFocus)
      ..dispose();
    _searchCtrl
      ..removeListener(_handleSearchText)
      ..dispose();
    super.dispose();
  }

  void _handleSearchFocus() {
    if (!mounted) return;
    setState(() => _searchExpanded = _searchFocus.hasFocus || _searchCtrl.text.isNotEmpty);
  }

  void _handleSearchText() {
    if (!mounted) return;
    if (_searchCtrl.text.isNotEmpty && !_searchExpanded) {
      setState(() => _searchExpanded = true);
    } else {
      setState(() {});
    }
  }

  void _submitSearch(String query) {
    final clean = query.trim();
    if (clean.isEmpty) return;
    widget.onSearchSubmitted?.call(clean);
    widget.onTabSelected(DesktopNavTab.search);
    _searchFocus.unfocus();
  }

  void _openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SubscriptionsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 42),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.70),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.055),
                ),
              ),
            ),
            child: Row(
              children: [
                _brand(),
                const SizedBox(width: 44),
                Expanded(
                  child: Center(
                    child: _navigationLinks(),
                  ),
                ),
                const SizedBox(width: 28),
                _utilities(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _brand() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onTabSelected(DesktopNavTab.home),
        child: Image.asset(
          'assets/icon/wordmark.png',
          height: 22,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _navigationLinks() {
    const links = <(DesktopNavTab, String)>[
      (DesktopNavTab.home, 'Home'),
      (DesktopNavTab.search, 'Search'),
      (DesktopNavTab.myList, 'My List'),
      (DesktopNavTab.downloads, 'Downloads'),
      (DesktopNavTab.settings, 'Settings'),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (tab, label) in links) _navLink(tab, label),
      ],
    );
  }

  Widget _navLink(DesktopNavTab tab, String label) {
    final active = widget.currentTab == tab;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => widget.onTabSelected(tab),
          behavior: HitTestBehavior.opaque,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 150),
            style: TextStyle(
              color: active ? Colors.white : Colors.white.withValues(alpha: 0.68),
              fontSize: 13,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              letterSpacing: -0.05,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(label),
            ),
          ),
        ),
      ),
    );
  }

  Widget _utilities() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _searchButton(),
        const SizedBox(width: 9),
        _circleButton(
          icon: Icons.notifications_none_rounded,
          tooltip: 'Notifications',
          onTap: _openNotifications,
        ),
        const SizedBox(width: 9),
        BlocBuilder<ActiveSourceCubit, String>(
          bloc: sl<ActiveSourceCubit>(),
          builder: (context, activeSource) {
            return SourceSwitcher(
              currentId: activeSource,
              compact: true,
              onChanged: (id) => sl<ActiveSourceCubit>().setSource(id),
            );
          },
        ),
        const SizedBox(width: 9),
        _avatarButton(context),
      ],
    );
  }

  Widget _searchButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: _searchExpanded ? 220 : 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: _searchExpanded ? 0.10 : 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _searchExpanded
              ? Colors.white.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 11),
          GestureDetector(
            onTap: () {
              setState(() => _searchExpanded = true);
              _searchFocus.requestFocus();
            },
            child: Icon(
              Icons.search_rounded,
              size: 19,
              color: _searchExpanded ? Colors.white : Colors.white.withValues(alpha: 0.82),
            ),
          ),
          if (_searchExpanded) ...[
            const SizedBox(width: 7),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                autofocus: false,
                style: AppText.body.copyWith(
                  color: Colors.white,
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  hintText: 'Search titles...',
                  hintStyle: AppText.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: _submitSearch,
              ),
            ),
            if (_searchCtrl.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchCtrl.clear();
                  _searchFocus.unfocus();
                },
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: _HoverCircleButton(icon: icon, onTap: onTap),
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

        return Tooltip(
          message: loggedIn ? 'Profile' : 'Sign in',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                if (loggedIn) {
                  widget.onTabSelected(DesktopNavTab.settings);
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
                  );
                }
              },
              child: Container(
                width: 40,
                height: 40,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
                child: CircleAvatar(
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
                              size: 19,
                            ))
                      : null,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HoverCircleButton extends StatefulWidget {
  const _HoverCircleButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_HoverCircleButton> createState() => _HoverCircleButtonState();
}

class _HoverCircleButtonState extends State<_HoverCircleButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.08),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: _hovered ? 0.15 : 0.07),
            ),
          ),
          child: Icon(
            widget.icon,
            size: 19,
            color: Colors.white.withValues(alpha: 0.86),
          ),
        ),
      ),
    );
  }
}
