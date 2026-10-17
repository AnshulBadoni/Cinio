import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'native_cover_provider.dart';
import 'poster_power_up_effect.dart';
import 'poster_shatter_effect.dart';

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
  VoidCallback? onStatus,
  Future<void> Function()? onRemoveHistory,
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
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondaryAnimation) =>
          _PosterQuickActions(
        animation: animation,
        item: item,
        heroTag: heroTag,
        onPlay: onPlay,
        onMarkWatched: onMarkWatched,
        onToggleLibrary: onToggleLibrary,
        onInfo: onInfo,
        onStatus: onStatus,
        onRemoveHistory: onRemoveHistory,
        playLabel: playLabel,
        initialInLibrary: inLibrary,
        initialWatched: watched,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          child,
    ),
  );
}

class _PosterQuickActions extends StatefulWidget {
  const _PosterQuickActions({
    required this.animation,
    required this.item,
    required this.heroTag,
    required this.onPlay,
    required this.onMarkWatched,
    required this.onToggleLibrary,
    required this.onInfo,
    this.onStatus,
    this.onRemoveHistory,
    required this.initialInLibrary,
    required this.initialWatched,
    this.playLabel,
  });

  final Animation<double> animation;

  final MediaItem item;
  final String heroTag;
  final VoidCallback onPlay;
  final Future<void> Function() onMarkWatched;
  final Future<bool> Function() onToggleLibrary;
  final VoidCallback onInfo;
  final VoidCallback? onStatus;
  final Future<void> Function()? onRemoveHistory;
  final bool initialInLibrary;
  final bool initialWatched;
  final String? playLabel;

  @override
  State<_PosterQuickActions> createState() => _PosterQuickActionsState();
}

class _PosterQuickActionsState extends State<_PosterQuickActions> {
  final GlobalKey<PosterShatterEffectState> _shatterKey =
      GlobalKey<PosterShatterEffectState>();
  final GlobalKey<PosterPowerUpEffectState> _powerUpKey =
      GlobalKey<PosterPowerUpEffectState>();

  late bool _inLibrary = widget.initialInLibrary;
  late bool _watched = widget.initialWatched;
  bool _busy = false;
  double? _aspectRatio;
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;

  @override
  void initState() {
    super.initState();
    _resolveImageAspectRatio();
  }

  @override
  void dispose() {
    if (_imageStream != null && _imageStreamListener != null) {
      _imageStream!.removeListener(_imageStreamListener!);
    }
    super.dispose();
  }

  void _resolveImageAspectRatio() {
    final cover = widget.item.cover;
    if (cover == null || cover.isEmpty) return;
    try {
      final provider = nativeCoverProvider(cover, widget.item.coverHeaders);
      final stream = provider.resolve(ImageConfiguration.empty);
      _imageStream = stream;
      _imageStreamListener = ImageStreamListener((info, synchronousCall) {
        final w = info.image.width;
        final h = info.image.height;
        if (w > 0 && h > 0) {
          final ratio = w / h;
          if (_aspectRatio != ratio) {
            if (synchronousCall) {
              _aspectRatio = ratio;
            } else if (mounted) {
              setState(() => _aspectRatio = ratio);
            }
          }
        }
      });
      stream.addListener(_imageStreamListener!);
    } catch (_) {}
  }

  String get _playText => widget.playLabel ?? (_watched ? 'Watch Again' : 'Play');

  Future<void> _toggleLibrary() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_inLibrary) {
        // Trigger shatter broken-to-pieces animation on the focused poster
        await _shatterKey.currentState?.shatter();
        await widget.onToggleLibrary();
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        final value = await widget.onToggleLibrary();
        if (mounted) {
          setState(() => _inLibrary = value);
          // Trigger subtle power-up animation on the focused card
          unawaited(_powerUpKey.currentState?.powerUp());
        }
      }
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

  Widget _quickActionsFlightShuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) {
        final t = curved.value.clamp(0.0, 1.0);
        // Interpolate corner radius: 12.0 on grid card -> 14.0 in quick actions modal
        final radius = 12.0 + (2.0 * t);
        final shadowAlpha = 0.40 * t;
        final blur = 22.0 * t;
        final spread = 2.0 * t;

        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              if (t > 0.05)
                BoxShadow(
                  color: Colors.black.withValues(alpha: shadowAlpha),
                  blurRadius: blur,
                  spreadRadius: spread,
                  offset: Offset(0, 8.0 * t),
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: child,
          ),
        );
      },
      child: widget.item.cover?.isNotEmpty == true
          ? Image(
              image: nativeCoverProvider(
                widget.item.cover!,
                widget.item.coverHeaders,
              ),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.high,
            )
          : ColoredBox(color: AppColors.surface2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Keep the focus artwork intentionally smaller than a detail hero.
    // If the image is wider (landscape e.g. 16:9), adapt width and height so
    // it comes wider on focus too, rather than being forced into a tall 2:3 box.
    final ratio = _aspectRatio;
    final isWider = ratio != null && ratio > 1.15;

    final double posterWidth;
    final double posterHeight;
    final double maxBoxWidth;

    if (isWider) {
      posterWidth = (size.width * 0.84).clamp(280.0, 420.0);
      posterHeight = posterWidth / ratio;
      maxBoxWidth = posterWidth;
    } else {
      posterHeight = (size.height * 0.32).clamp(230.0, 440.0);
      posterWidth = ratio != null
          ? (posterHeight * ratio).clamp(150.0, size.width * 0.8)
          : (posterHeight * 2 / 3);
      maxBoxWidth = 310.0;
    }

    final pillWidgets = <Widget>[
      _QuickActionButton(
        icon: _watched
            ? Icons.replay_rounded
            : Icons.play_arrow_rounded,
        label: _playText,
        primary: true,
        onTap: _play,
      ),
      _QuickActionButton(
        icon: Icons.info_outline_rounded,
        label: 'Info',
        onTap: _info,
      ),
      if (widget.onStatus != null)
        _QuickActionButton(
          icon: Icons.bookmark_outline_rounded,
          label: 'Status & Categories',
          onTap: () {
            Navigator.of(context).pop();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.onStatus!();
            });
          },
        ),
      _QuickActionButton(
        icon: _watched
            ? Icons.check_rounded
            : Icons.done_all_rounded,
        label: _watched ? 'Watched' : 'Mark as watched',
        onTap: _markWatched,
      ),
      _QuickActionButton(
        icon: _inLibrary
            ? Icons.delete_outline_rounded
            : Icons.add_rounded,
        label: _inLibrary ? 'Remove from Library' : 'Add to Library',
        destructive: _inLibrary,
        onTap: _toggleLibrary,
      ),
      if (widget.onRemoveHistory != null)
        _QuickActionButton(
          icon: Icons.history_toggle_off_rounded,
          label: 'Remove from History',
          destructive: true,
          onTap: () async {
            if (_busy) return;
            setState(() => _busy = true);
            final nav = Navigator.of(context);
            try {
              await widget.onRemoveHistory!();
              if (mounted) nav.pop();
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
        ),
    ];

    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: widget.animation,
            builder: (context, _) {
              final t = widget.animation.value.clamp(0.0, 1.0);
              final curveT = Curves.easeOutCubic.transform(t);
              final blurSigma = 14.0 * curveT;
              final scrimAlpha = 0.65 * curveT;
              return Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: blurSigma.clamp(0.001, 14.0),
                      sigmaY: blurSigma.clamp(0.001, 14.0),
                    ),
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: scrimAlpha),
                    ),
                  ),
                ),
              );
            },
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 30),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxBoxWidth),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Hero(
                        tag: widget.heroTag,
                        createRectTween: (begin, end) =>
                            MaterialRectArcTween(begin: begin, end: end),
                        flightShuttleBuilder: _quickActionsFlightShuttle,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.40),
                                blurRadius: 22,
                                spreadRadius: 2,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: PosterShatterEffect(
                            key: _shatterKey,
                            child: PosterPowerUpEffect(
                              key: _powerUpKey,
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
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _StaggeredItem(
                        animation: widget.animation,
                        start: 0.16,
                        end: 0.58,
                        offsetY: 14.0,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (int i = 0; i < pillWidgets.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        _StaggeredItem(
                          animation: widget.animation,
                          start: 0.22 + (i * 0.07),
                          end: (0.22 + (i * 0.07) + 0.42).clamp(0.0, 1.0),
                          child: pillWidgets[i],
                        ),
                      ],
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

/// Staggered slide-up and fade-in container for quick action modal items.
class _StaggeredItem extends StatelessWidget {
  const _StaggeredItem({
    required this.animation,
    required this.start,
    required this.end,
    this.offsetY = 18.0,
    required this.child,
  });

  final Animation<double> animation;
  final double start;
  final double end;
  final double offsetY;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Interval(
        start.clamp(0.0, 1.0),
        end.clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
      reverseCurve: Curves.easeInCubic,
    );

    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) {
        final progress = curved.value;
        return Opacity(
          opacity: progress.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, offsetY * (1.0 - progress)),
            child: child,
          ),
        );
      },
      child: child,
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
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool destructive;

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
      child: Material(
        color: matColor,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            height: 54,
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
    );
  }
}

