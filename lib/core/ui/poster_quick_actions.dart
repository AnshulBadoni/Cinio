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
    required this.initialInLibrary,
    required this.initialWatched,
    this.playLabel,
  });

  final MediaItem item;
  final String heroTag;
  final VoidCallback onPlay;
  final Future<void> Function() onMarkWatched;
  final Future<bool> Function() onToggleLibrary;
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final maxPosterHeight = (size.height * 0.54).clamp(330.0, 760.0);

    final posterWidth = maxPosterHeight * 0.675;

    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.item.cover?.isNotEmpty == true)
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.18,
                  child: Image(
                    image: nativeCoverProvider(widget.item.cover!, widget.item.coverHeaders),
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation,
              builder: (context, _) {
                final progress = (ModalRoute.of(context)?.animation?.value ?? 1.0)
                    .clamp(0.0, 1.0);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 26 * progress,
                      sigmaY: 26 * progress,
                    ),
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.20 * progress),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Hero(
                    tag: widget.heroTag,
                    createRectTween: (begin, end) => MaterialRectArcTween(begin: begin, end: end),
                    flightShuttleBuilder: (context, animation, direction, fromHero, toHero) =>
                        direction == HeroFlightDirection.push ? fromHero.widget : toHero.widget,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SizedBox(
                        width: posterWidth,
                        height: maxPosterHeight,
                        child: widget.item.cover?.isNotEmpty == true
                            ? Image(
                                image: nativeCoverProvider(widget.item.cover!, widget.item.coverHeaders),
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                filterQuality: FilterQuality.high,
                              )
                            : ColoredBox(color: AppColors.surface2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    widget.item.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.display.copyWith(fontSize: 22),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (widget.item.year?.isNotEmpty == true) widget.item.year!,
                      widget.item.tmdbIsTv ? 'Series' : 'Movie',
                    ].join('  ·  '),
                    textAlign: TextAlign.center,
                    style: AppText.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _QuickActionButton(
                    icon: _watched ? Icons.replay_rounded : Icons.play_arrow_rounded,
                    label: _playText,
                    primary: true,
                    onTap: _play,
                  ),
                  const SizedBox(height: 8),
                  _QuickActionButton(
                    icon: _watched ? Icons.check_rounded : Icons.done_all_rounded,
                    label: _watched ? 'Watched' : 'Mark as Watched',
                    onTap: _markWatched,
                  ),
                  const SizedBox(height: 8),
                  _QuickActionButton(
                    icon: _inLibrary ? Icons.check_rounded : Icons.add_rounded,
                    label: _inLibrary ? 'In Library' : 'Add to Library',
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
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: primary ? 84 : 72,
      child: Material(
        color: primary ? Colors.white : AppColors.surface,
        borderRadius: BorderRadius.circular(primary ? 18 : 16),
        child: InkWell(
          borderRadius: BorderRadius.circular(primary ? 18 : 16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: primary ? Colors.black : Colors.white,
                  size: primary ? 25 : 23,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.button.copyWith(
                      color: primary ? Colors.black : Colors.white,
                      fontSize: primary ? 18 : 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

