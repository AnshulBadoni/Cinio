import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'native_cover_provider.dart';

/// Long-press action overlay for browse/discover posters.
///
/// The poster is shared with the source card through a Hero so the interaction
/// feels like the artwork itself moves into focus rather than opening a generic
/// bottom sheet. Actions are deliberately injected by the caller so this
/// component stays independent of navigation and provider resolution.
Future<void> showPosterQuickActions(
  BuildContext context, {
  required MediaItem item,
  required String heroTag,
  required VoidCallback onPlay,
  required Future<void> Function() onMarkWatched,
  required Future<bool> Function() onToggleLibrary,
  required VoidCallback onInfo,
  String? playLabel,
  bool inLibrary = false,
  bool watched = false,
}) {
  if (item.cover != null && item.cover!.isNotEmpty) {
    unawaited(precacheImage(nativeCoverProvider(item.cover!, item.coverHeaders), context));
  }
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (context, animation, secondaryAnimation) =>
          _PosterQuickActions(
        item: item,
        heroTag: heroTag,
        onPlay: onPlay,
        onMarkWatched: onMarkWatched,
        onToggleLibrary: onToggleLibrary,
        onInfo: onInfo,
        playLabel: playLabel,
        initialInLibrary: inLibrary,
        initialWatched: watched,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: child,
        );
      },
    ),
  );
}

class _PosterQuickActions extends StatefulWidget {
  const _PosterQuickActions({
    required this.item,
    required this.heroTag,
    required this.onPlay,
    required this.onMarkWatched,
    required this.onToggleLibrary,
    required this.onInfo,
    required this.initialInLibrary,
    required this.initialWatched,
    this.playLabel,
  });

  final MediaItem item;
  final String heroTag;
  final VoidCallback onPlay;
  final Future<void> Function() onMarkWatched;
  final Future<bool> Function() onToggleLibrary;
  final VoidCallback onInfo;
  final bool initialInLibrary;
  final bool initialWatched;
  final String? playLabel;

  @override
  State<_PosterQuickActions> createState() => _PosterQuickActionsState();
}

class _PosterQuickActionsState extends State<_PosterQuickActions> {
  late bool _inLibrary = widget.initialInLibrary;
  late bool _watched = widget.initialWatched;
  bool _busy = false;

  String get _playText => widget.playLabel ?? (_watched ? 'Watch Again' : 'Play');

  Future<void> _toggleLibrary() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final value = await widget.onToggleLibrary();
      if (mounted) setState(() => _inLibrary = value);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markWatched() async {
    if (_busy || _watched) return;
    setState(() => _busy = true);
    try {
      await widget.onMarkWatched();
      if (mounted) setState(() => _watched = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _play() {
    if (_busy) return;
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onPlay());
  }

  void _info() {
    if (_busy) return;
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onInfo();
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Keep the focus artwork intentionally smaller than a detail hero. The
    // long-press surface is an action palette, not a full-screen poster page.
    final posterHeight = (size.height * 0.32).clamp(230.0, 440.0);
    final posterWidth = posterHeight * 2 / 3;

    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.item.cover?.isNotEmpty == true)
            Positioned.fill(
              child: IgnorePointer(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: Opacity(
                    opacity: 0.12,
                    child: Image(
                      image: nativeCoverProvider(
                        widget.item.cover!,
                        widget.item.coverHeaders,
                      ),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.low,
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.42),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 30),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 310),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Hero(
                        tag: widget.heroTag,
                        createRectTween: (begin, end) =>
                            MaterialRectArcTween(begin: begin, end: end),
                        flightShuttleBuilder:
                            (context, animation, direction, fromHero, toHero) =>
                                direction == HeroFlightDirection.push
                                    ? fromHero.widget
                                    : toHero.widget,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            width: posterWidth,
                            height: posterHeight,
                            child: widget.item.cover?.isNotEmpty == true
                                ? Image(
                                    image: nativeCoverProvider(
                                      widget.item.cover!,
                                      widget.item.coverHeaders,
                                    ),
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                    filterQuality: FilterQuality.high,
                                    errorBuilder: (context, error, stackTrace) =>
                                        ColoredBox(color: AppColors.surface2),
                                  )
                                : ColoredBox(color: AppColors.surface2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        widget.item.title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.display.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        [
                          if (widget.item.year?.isNotEmpty == true)
                            widget.item.year!,
                          widget.item.tmdbIsTv ? 'Series' : 'Movie',
                        ].join('  ·  '),
                        textAlign: TextAlign.center,
                        style: AppText.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _QuickActionButton(
                        icon: _watched
                            ? Icons.replay_rounded
                            : Icons.play_arrow_rounded,
                        label: _playText,
                        primary: true,
                        onTap: _play,
                      ),
                      const SizedBox(height: 8),
                      _QuickActionButton(
                        icon: Icons.info_outline_rounded,
                        label: 'Info',
                        onTap: _info,
                      ),
                      const SizedBox(height: 8),
                      _QuickActionButton(
                        icon: _watched
                            ? Icons.check_rounded
                            : Icons.done_all_rounded,
                        label: _watched ? 'Watched' : 'Mark as watched',
                        onTap: _markWatched,
                      ),
                      const SizedBox(height: 8),
                      _QuickActionButton(
                        icon: _inLibrary
                            ? Icons.delete_outline_rounded
                            : Icons.add_rounded,
                        label: _inLibrary ? 'Remove from Library' : 'Add to Library',
                        destructive: _inLibrary,
                        onTap: _toggleLibrary,
                      ),
                      if (_busy) ...[
                        const SizedBox(height: 12),
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.destructive = false,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool destructive;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(999);
    final fgColor = primary
        ? Colors.black
        : destructive
            ? const Color(0xFFFF6E6E)
            : Colors.white;
    final borderColor = destructive
        ? Colors.redAccent.withValues(alpha: 0.38)
        : Colors.white.withValues(alpha: primary ? 0.30 : 0.14);
    final gradientColors = primary
        ? [
            Colors.white.withValues(alpha: 0.98),
            Colors.white.withValues(alpha: 0.82),
          ]
        : destructive
            ? [
                Colors.redAccent.withValues(alpha: 0.22),
                Colors.redAccent.withValues(alpha: 0.10),
              ]
            : [
                Colors.white.withValues(alpha: 0.10),
                Colors.white.withValues(alpha: 0.045),
              ];
    final matColor = primary
        ? Colors.white.withValues(alpha: 0.92)
        : destructive
            ? Colors.redAccent.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.075);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: matColor,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Container(
              height: compact ? 50 : 54,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: borderColor,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: gradientColors,
                ),
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      color: fgColor,
                      size: 21,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: AppText.button.copyWith(
                          color: fgColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

