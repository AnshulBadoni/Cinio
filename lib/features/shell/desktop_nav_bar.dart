import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/di/injector.dart';
import '../../core/state/active_source_cubit.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/source_switcher.dart';
import '../auth/auth_cubit.dart';
import '../auth/auth_screens.dart';
import '../notify/subscriptions_screen.dart';

/// Navigation categories matching premium streaming services (Netflix/Apple).
enum DesktopNavCategory {
  home,
  tvShows,
  movies,
  newAndPopular,
  myList,
  collections,
}

/// Cinematic, backgroundless desktop navbar that sits directly over the hero artwork.
/// Follows modern streaming design: transparent atmospheric gradient, crisp typography,
/// minimal thin-stroke line icons, and smooth hover interactions.
class DesktopNavBar extends StatefulWidget {
  const DesktopNavBar({
    super.key,
    required this.currentCategory,
    required this.onCategorySelected,
    this.onSearchSubmitted,
    this.isScrolled = false,
  });

  final DesktopNavCategory currentCategory;
  final ValueChanged<DesktopNavCategory> onCategorySelected;
  final ValueChanged<String>? onSearchSubmitted;
  final bool isScrolled;

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
    _searchFocus.unfocus();
  }

  void _openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SubscriptionsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final navHeight = widget.isScrolled ? 60.0 : 70.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      height: navHeight,
      padding: const EdgeInsets.symmetric(horizontal: 56),
      decoration: BoxDecoration(
        // Atmospheric gradient that feels invisible as a distinct element,
        // letting hero artwork shine through while keeping text crisp.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: widget.isScrolled
              ? [
                  Colors.black.withValues(alpha: 0.88),
                  Colors.black.withValues(alpha: 0.45),
                  Colors.transparent,
                ]
              : [
                  Colors.black.withValues(alpha: 0.58),
                  Colors.black.withValues(alpha: 0.16),
                  Colors.transparent,
                ],
          stops: const [0.0, 0.65, 1.0],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Left: Cinio Wordmark Logo ─────────────────────────────
          _brand(),

          const SizedBox(width: 38),

          // ── Center: Clean Navigation Links ────────────────────────
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _navigationLinks(),
            ),
          ),

          const SizedBox(width: 24),

          // ── Right: Search · Notifications · Profile ───────────────
          _utilities(context),
        ],
      ),
    );
  }

  Widget _brand() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onCategorySelected(DesktopNavCategory.home),
        child: Image.asset(
          'assets/icon/wordmark.png',
          height: 22,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _navigationLinks() {
    const categories = <(DesktopNavCategory, String)>[
      (DesktopNavCategory.home, 'Home'),
      (DesktopNavCategory.tvShows, 'TV Shows'),
      (DesktopNavCategory.movies, 'Movies'),
      (DesktopNavCategory.newAndPopular, 'New & Popular'),
      (DesktopNavCategory.myList, 'My List'),
      (DesktopNavCategory.collections, 'Collections'),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (category, label) in categories)
          _DesktopNavLink(
            label: label,
            active: widget.currentCategory == category,
            onTap: () => widget.onCategorySelected(category),
          ),
      ],
    );
  }

  Widget _utilities(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Expandable / Minimal Search Action
        _searchBar(),

        const SizedBox(width: 14),

        // Notifications minimal line icon
        _DesktopIconButton(
          icon: HugeIcons.strokeRoundedNotification02,
          tooltip: 'Notifications',
          onTap: _openNotifications,
        ),

        const SizedBox(width: 12),

        // Source switcher pill
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

        const SizedBox(width: 14),

        // Profile Avatar
        _DesktopProfileAvatar(
          onTap: () {
            final auth = sl<AuthCubit>().state;
            if (auth.isLoggedIn) {
              widget.onCategorySelected(DesktopNavCategory.collections);
            } else {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
              );
            }
          },
        ),
      ],
    );
  }

  Widget _searchBar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: _searchExpanded ? 240 : 36,
      height: 36,
      decoration: BoxDecoration(
        color: _searchExpanded
            ? Colors.black.withValues(alpha: 0.35)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: _searchExpanded
            ? Border.all(
                color: Colors.white.withValues(alpha: 0.14),
                width: 1,
              )
            : null,
      ),
      child: Row(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() => _searchExpanded = true);
                _searchFocus.requestFocus();
              },
              child: SizedBox(
                width: 36,
                height: 36,
                child: Center(
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedSearch01,
                    size: 19.5,
                    color: _searchExpanded
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.76),
                  ),
                ),
              ),
            ),
          ),
          if (_searchExpanded) ...[
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                autofocus: true,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
                decoration: InputDecoration(
                  hintText: 'Search or paste link',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.42),
                    fontSize: 12.5,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: _submitSearch,
              ),
            ),
            if (_searchCtrl.text.isNotEmpty)
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    _searchCtrl.clear();
                    _searchFocus.unfocus();
                    setState(() => _searchExpanded = false);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      Icons.close_rounded,
                      size: 15,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              )
            else
              const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Subcomponents
// ─────────────────────────────────────────────────────────────────────────────

class _DesktopNavLink extends StatefulWidget {
  const _DesktopNavLink({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_DesktopNavLink> createState() => _DesktopNavLinkState();
}

class _DesktopNavLinkState extends State<_DesktopNavLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final textColor = active
        ? Colors.white
        : (_hovered
            ? Colors.white
            : Colors.white.withValues(alpha: 0.68));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              color: textColor,
              fontSize: 13.5,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              letterSpacing: -0.1,
            ),
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}

class _DesktopIconButton extends StatefulWidget {
  const _DesktopIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final List<List<dynamic>> icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_DesktopIconButton> createState() => _DesktopIconButtonState();
}

class _DesktopIconButtonState extends State<_DesktopIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            scale: _hovered ? 1.06 : 1.0,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: HugeIcon(
                icon: widget.icon,
                size: 20,
                color: _hovered
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.72),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopProfileAvatar extends StatefulWidget {
  const _DesktopProfileAvatar({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_DesktopProfileAvatar> createState() => _DesktopProfileAvatarState();
}

class _DesktopProfileAvatarState extends State<_DesktopProfileAvatar> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      bloc: sl<AuthCubit>(),
      builder: (context, auth) {
        final loggedIn = auth.isLoggedIn;
        final name = loggedIn ? auth.displayName : '';
        final initial = (loggedIn && name.isNotEmpty) ? name[0].toUpperCase() : null;
        final avatar = auth.avatarUrl;

        return Tooltip(
          message: loggedIn ? (name.isNotEmpty ? name : 'Profile') : 'Sign in',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: widget.onTap,
              child: AnimatedScale(
                scale: _hovered ? 1.04 : 1.0,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                child: Container(
                  width: 35,
                  height: 35,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _hovered
                          ? Colors.white.withValues(alpha: 0.40)
                          : Colors.white.withValues(alpha: 0.14),
                      width: 1.2,
                    ),
                  ),
                  child: ClipOval(
                    child: (avatar != null && avatar.isNotEmpty)
                        ? Image.network(
                            avatar,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _fallback(initial),
                          )
                        : _fallback(initial),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _fallback(String? initial) {
    return Container(
      color: AppColors.surface2,
      alignment: Alignment.center,
      child: initial != null
          ? Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            )
          : HugeIcon(
              icon: HugeIcons.strokeRoundedUserCircle02,
              size: 20,
              color: Colors.white.withValues(alpha: 0.75),
            ),
    );
  }
}
