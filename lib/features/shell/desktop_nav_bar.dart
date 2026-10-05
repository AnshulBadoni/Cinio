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
    this.isScrolled = false,
  });

  final DesktopNavCategory currentCategory;
  final ValueChanged<DesktopNavCategory> onCategorySelected;
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
          // ── Left: Clean Navigation Links (HOME · DISCOVER · LIBRARY · DOWNLOADS)
          _navigationLinks(),

          const Spacer(),

          // ── Right: Utilities (Search · Fullscreen · Source · Profile) ──
          _utilities(context),
        ],
      ),
    );
  }

  Widget _navigationLinks() {
    const categories = <(DesktopNavCategory, String)>[
      (DesktopNavCategory.home, 'HOME'),
      (DesktopNavCategory.discover, 'DISCOVER'),
      (DesktopNavCategory.library, 'LIBRARY'),
      (DesktopNavCategory.downloads, 'DOWNLOADS'),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final (category, label) in categories)
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
        // Search icon button
        _DesktopSearchIconButton(
          active: currentCategory == DesktopNavCategory.discover,
          onTap: () => onCategorySelected(DesktopNavCategory.discover),
        ),

        const SizedBox(width: 14),

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
            : Colors.white.withValues(alpha: 0.58));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: 1.2,
                ),
                child: Text(widget.label),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                height: 2.5,
                width: active ? 22 : 0,
                decoration: BoxDecoration(
                  color: active ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopSearchIconButton extends StatefulWidget {
  const _DesktopSearchIconButton({
    required this.active,
    required this.onTap,
  });

  final bool active;
  final VoidCallback onTap;

  @override
  State<_DesktopSearchIconButton> createState() => _DesktopSearchIconButtonState();
}

class _DesktopSearchIconButtonState extends State<_DesktopSearchIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Search',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hovered
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.transparent,
            ),
            child: Icon(
              Icons.search_rounded,
              size: 22,
              color: widget.active
                  ? Colors.white
                  : (_hovered
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.78)),
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

