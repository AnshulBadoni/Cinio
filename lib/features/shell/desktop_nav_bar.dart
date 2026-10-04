import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/di/injector.dart';
import '../../core/state/active_source_cubit.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/source_switcher.dart';
import '../auth/auth_cubit.dart';
import '../auth/auth_screens.dart';

/// Navigation categories for desktop: Home, Discover (Search), Library (My List), Downloads, Profile.
enum DesktopNavCategory {
  home,
  discover,
  library,
  downloads,
  profile,
}

/// Cinematic, backgroundless desktop navbar that sits directly over the hero artwork.
/// Features centered navigation links: Home · Discover · Library · Downloads.
/// Minimal right-side utilities: Source switcher + Profile avatar.
class DesktopNavBar extends StatelessWidget {
  const DesktopNavBar({
    super.key,
    required this.currentCategory,
    required this.onCategorySelected,
    this.searchController,
    this.onSearchChanged,
    this.onSearchSubmitted,
    this.isScrolled = false,
  });

  final DesktopNavCategory currentCategory;
  final ValueChanged<DesktopNavCategory> onCategorySelected;
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<String>? onSearchSubmitted;
  final bool isScrolled;

  @override
  Widget build(BuildContext context) {
    final navHeight = isScrolled ? 60.0 : 70.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      height: navHeight,
      padding: const EdgeInsets.symmetric(horizontal: 56),
      decoration: BoxDecoration(
        // Atmospheric transparent gradient that lets hero artwork remain the visual focus
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isScrolled
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
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _brand(),
            ),
          ),

          // ── Center: Clean Navigation Links ────────────────────────
          _navigationLinks(),

          // ── Right: Minimal Utilities (Source Switcher · Profile) ──
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerRight,
              child: _utilities(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _brand() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onCategorySelected(DesktopNavCategory.home),
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
      (DesktopNavCategory.discover, 'Discover'),
      (DesktopNavCategory.library, 'Library'),
      (DesktopNavCategory.downloads, 'Downloads'),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final (category, label) in categories)
          if (category == DesktopNavCategory.discover &&
              currentCategory == DesktopNavCategory.discover)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _DesktopNavbarSearchBar(
                controller: searchController,
                onChanged: onSearchChanged,
                onSubmitted: onSearchSubmitted,
              ),
            )
          else
            _DesktopNavLink(
              label: label,
              active: currentCategory == category,
              onTap: () => onCategorySelected(category),
            ),
      ],
    );
  }

  Widget _utilities(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Full screen toggle (removes upper window border)
        const _DesktopFullscreenButton(),

        const SizedBox(width: 14),

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

        const SizedBox(width: 16),

        // Profile Avatar
        _DesktopProfileAvatar(
          onTap: () {
            final auth = sl<AuthCubit>().state;
            if (auth.isLoggedIn) {
              onCategorySelected(DesktopNavCategory.profile);
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
            : Colors.white.withValues(alpha: 0.65));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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

class _DesktopFullscreenButton extends StatefulWidget {
  const _DesktopFullscreenButton();

  @override
  State<_DesktopFullscreenButton> createState() => _DesktopFullscreenButtonState();
}

class _DesktopFullscreenButtonState extends State<_DesktopFullscreenButton> with WindowListener {
  bool _isFullScreen = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _checkStatus();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _checkStatus() async {
    try {
      final isFull = await windowManager.isFullScreen();
      if (mounted) setState(() => _isFullScreen = isFull);
    } catch (_) {}
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _isFullScreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _isFullScreen = false);
  }

  Future<void> _toggleFullscreen() async {
    try {
      final isFull = await windowManager.isFullScreen();
      await windowManager.setFullScreen(!isFull);
      if (mounted) setState(() => _isFullScreen = !isFull);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _isFullScreen ? 'Exit Full Screen' : 'Full Screen',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: _toggleFullscreen,
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            scale: _hovered ? 1.08 : 1.0,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: HugeIcon(
                icon: _isFullScreen
                    ? HugeIcons.strokeRoundedMinimize01
                    : HugeIcons.strokeRoundedFullScreen,
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

class _DesktopNavbarSearchBar extends StatefulWidget {
  const _DesktopNavbarSearchBar({
    this.controller,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_DesktopNavbarSearchBar> createState() => _DesktopNavbarSearchBarState();
}

class _DesktopNavbarSearchBarState extends State<_DesktopNavbarSearchBar> {
  late final TextEditingController _effectiveController;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _effectiveController = widget.controller ?? TextEditingController();
    _effectiveController.addListener(_onTextChange);
    // Smooth autofocus when morphing into search bar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _effectiveController.removeListener(_onTextChange);
    _focusNode.dispose();
    if (widget.controller == null) _effectiveController.dispose();
    super.dispose();
  }

  void _onTextChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: 250,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.22),
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedSearch01,
            size: 16.5,
            color: Colors.white.withValues(alpha: 0.75),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _effectiveController,
              focusNode: _focusNode,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
              decoration: InputDecoration(
                hintText: 'Search…',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.40),
                  fontSize: 12.5,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
            ),
          ),
          if (_effectiveController.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _effectiveController.clear();
                widget.onChanged?.call('');
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.close_rounded,
                  size: 15,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
