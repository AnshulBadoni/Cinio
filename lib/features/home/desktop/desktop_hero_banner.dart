import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/di/injector.dart';
import '../../../core/metadata/title_logo_service.dart';
import '../../../core/metadata/tmdb.dart';
import '../../../core/models/media_item.dart';
import '../../../core/playback/my_list.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/ui/cinio_title_style.dart';

/// Full-bleed cinematic desktop hero carousel.
///
/// Features:
/// • Multi-item auto-advancing carousel with pause-on-hover.
/// • High-resolution 16:9 widescreen backdrop art with smooth atmospheric scrims.
/// • Official stylized TMDB title logos with [cinioFallbackTitle] archetype fallback.
/// • Clean modern metadata badges (Type, Year, Rating, Genres) — no hardcoded labels.
/// • Editorial synopsis typography with high readability.
/// • Redesigned action buttons: high-contrast pure white Play, frosted glass More Info,
///   and interactive My List bookmark toggle.
/// • Sleek arrow navigation and interactive animated progress indicator pills.
class DesktopHeroBanner extends StatefulWidget {
  const DesktopHeroBanner({
    super.key,
    required this.items,
    required this.onPlay,
    required this.onMoreInfo,
  });

  final List<MediaItem> items;
  final void Function(MediaItem item) onPlay;
  final void Function(MediaItem item) onMoreInfo;

  @override
  State<DesktopHeroBanner> createState() => _DesktopHeroBannerState();
}

class _DesktopHeroBannerState extends State<DesktopHeroBanner> {
  late final PageController _pageController;
  int _currentIndex = 0;
  Timer? _autoTimer;
  bool _isHovered = false;

  final MyListStore _myList = sl<MyListStore>();
  final Map<String, String> _logoUrls = {};
  final Map<String, String> _backdrops = {};
  final Map<String, String> _overviews = {};
  final Map<String, List<String>> _genres = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _preloadCurrentAndAdjacent(0);
    _startAutoTimer();
  }

  @override
  void didUpdateWidget(covariant DesktopHeroBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.length != oldWidget.items.length) {
      _preloadCurrentAndAdjacent(_currentIndex);
      _startAutoTimer();
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoTimer() {
    _autoTimer?.cancel();
    if (widget.items.length <= 1) return;

    _autoTimer = Timer.periodic(const Duration(milliseconds: 6500), (_) {
      if (!mounted || _isHovered || widget.items.isEmpty) return;
      final next = (_currentIndex + 1) % widget.items.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _preloadCurrentAndAdjacent(int index) {
    if (widget.items.isEmpty) return;
    _resolveSlideExtras(widget.items[index]);
    if (index + 1 < widget.items.length) {
      _resolveSlideExtras(widget.items[index + 1]);
    }
    if (index - 1 >= 0) {
      _resolveSlideExtras(widget.items[index - 1]);
    }
  }

  Future<void> _resolveSlideExtras(MediaItem item) async {
    // 1. Official TMDB Stylized Title Logo
    if (!_logoUrls.containsKey(item.id)) {
      try {
        final logo = await sl<TitleLogoService>().logoFor(item);
        if (mounted && logo != null && logo.isNotEmpty) {
          setState(() => _logoUrls[item.id] = logo);
        }
      } catch (_) {}
    }

    // 2. 16:9 Backdrop Artwork & Synopsis
    if (!_backdrops.containsKey(item.id) || !_overviews.containsKey(item.id)) {
      try {
        final tmdbId = item.tmdbId;
        final isTv = item.tmdbIsTv;
        if (tmdbId != null && tmdbId > 0) {
          final dio = sl<Dio>();
          final path = isTv ? 'tv/$tmdbId' : 'movie/$tmdbId';
          final res = await dio.get<Map<String, dynamic>>(
            'https://${Tmdb.host}/3/$path',
            queryParameters: {'api_key': Tmdb.apiKey},
          );
          final data = res.data;
          if (data != null && mounted) {
            final bg = data['backdrop_path']?.toString();
            final ov = data['overview']?.toString();
            final glist = data['genres'] as List?;
            setState(() {
              if (bg != null && bg.isNotEmpty) {
                _backdrops[item.id] = '${Tmdb.img}/original$bg';
              }
              if (ov != null && ov.isNotEmpty) {
                _overviews[item.id] = ov;
              }
              if (glist != null && glist.isNotEmpty) {
                _genres[item.id] = glist
                    .map((g) => g is Map ? g['name']?.toString() ?? '' : '')
                    .where((s) => s.isNotEmpty)
                    .toList();
              }
            });
          }
        }
      } catch (_) {}
    }
  }

  void _goToPage(int page) {
    if (page < 0 || page >= widget.items.length) return;
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    final screenHeight = MediaQuery.sizeOf(context).height;
    final heroHeight = screenHeight.clamp(600.0, double.infinity).toDouble();

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: SizedBox(
        height: heroHeight,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── 1. PageView for Smooth Carousel Sliding ─────────────
            PageView.builder(
              controller: _pageController,
              itemCount: widget.items.length,
              onPageChanged: (idx) {
                setState(() => _currentIndex = idx);
                _preloadCurrentAndAdjacent(idx);
              },
              itemBuilder: (context, index) {
                final item = widget.items[index];
                return _buildHeroSlide(item, heroHeight);
              },
            ),

            // ── 2. Arrow Navigation Controls (Previous / Next) ──────
            if (widget.items.length > 1) ...[
              Positioned(
                left: 20,
                top: (heroHeight - 48) / 2,
                child: _carouselArrowButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: () {
                    final prev = _currentIndex > 0
                        ? _currentIndex - 1
                        : widget.items.length - 1;
                    _goToPage(prev);
                  },
                ),
              ),
              Positioned(
                right: 20,
                top: (heroHeight - 48) / 2,
                child: _carouselArrowButton(
                  icon: Icons.chevron_right_rounded,
                  onTap: () {
                    final next = (_currentIndex + 1) % widget.items.length;
                    _goToPage(next);
                  },
                ),
              ),
            ],

            // ── 3. Bottom-Right Pagination Indicator Pills ──────────
            if (widget.items.length > 1)
              Positioned(
                right: 56,
                bottom: (heroHeight * 0.10).clamp(56.0, 90.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < widget.items.length; i++)
                      _paginationPill(i, i == _currentIndex),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroSlide(MediaItem item, double heroHeight) {
    final backdrop = _backdrops[item.id] ?? item.heroImage ?? item.cover;
    final overview = _overviews[item.id] ?? '';
    final genresList = _genres[item.id] ?? item.genres;
    final isBookmarked = _myList.contains(item);

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── High-Res Artwork ────────────────────────────────────────
        if (backdrop != null && backdrop.isNotEmpty)
          CachedNetworkImage(
            imageUrl: backdrop,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            memCacheWidth: 1920,
            fadeInDuration: const Duration(milliseconds: 250),
            placeholder: (_, _) => Container(color: AppColors.bg),
            errorWidget: (_, _, _) => Container(color: AppColors.bg),
          )
        else
          Container(color: AppColors.bg),

        // ── Atmospheric Scrims ──────────────────────────────────────
        // Left-to-right gradient for typography contrast
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: const [0.0, 0.38, 0.68, 1.0],
                  colors: [
                    Colors.black.withValues(alpha: 0.92),
                    Colors.black.withValues(alpha: 0.68),
                    Colors.black.withValues(alpha: 0.20),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        // Bottom gradient melting seamlessly into content rows
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.45, 0.70, 0.88, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.20),
                    AppColors.bg.withValues(alpha: 0.82),
                    AppColors.bg,
                  ],
                ),
              ),
            ),
          ),
        ),

        // Subtle top gradient behind the backgroundless navbar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 140,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.65),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── Hero Content (Badges / Stylized Title / Overview / Actions) ──
        Positioned(
          left: 56,
          bottom: (heroHeight * 0.10).clamp(56.0, 90.0),
          right: 140,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Metadata Badges Row (NO 'CINIO ORIGINAL')
                Row(
                  children: [
                    _metaBadge(
                      item.tmdbIsTv ? 'TV SERIES' : 'MOVIE',
                      isAccent: true,
                    ),
                    if (item.year != null && item.year!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _metaBadge(item.year!),
                    ],
                    if (item.rating != null && item.rating! > 0) ...[
                      const SizedBox(width: 10),
                      _imdbRatingBadge(item.rating!),
                    ],
                    if (genresList.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          genresList.take(3).join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.68),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 16),

                // 2. Stylized Title (TMDB Image Logo or Cinio Archetype)
                _titleDisplay(item),

                const SizedBox(height: 14),

                // 3. Editorial Overview Typography
                Text(
                  overview.isNotEmpty
                      ? overview
                      : 'Stream in full high definition with multi-audio sources, custom subtitle formatting, and instant playback on Cinio.',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 14.5,
                    height: 1.55,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.15,
                    shadows: const [
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // 4. Redesigned Action Buttons
                Row(
                  children: [
                    // Primary "Watch Now" White Pill
                    _HeroPrimaryPlayButton(
                      onTap: () => widget.onPlay(item),
                    ),

                    const SizedBox(width: 14),

                    // Secondary "More Info" Frosted Pill
                    _HeroSecondaryInfoButton(
                      onTap: () => widget.onMoreInfo(item),
                    ),

                    const SizedBox(width: 12),

                    // Quick "My List" Bookmark Toggle
                    _heroCircleUtility(
                      icon: isBookmarked
                          ? Icons.bookmark_added_rounded
                          : Icons.bookmark_add_outlined,
                      active: isBookmarked,
                      tooltip: isBookmarked ? 'In My List' : 'Add to My List',
                      onTap: () {
                        setState(() {
                          if (isBookmarked) {
                            _myList.remove(item);
                          } else {
                            _myList.add(item);
                          }
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _titleDisplay(MediaItem item) {
    final logoUrl = _logoUrls[item.id];
    if (logoUrl != null && logoUrl.isNotEmpty) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 105),
        child: CachedNetworkImage(
          imageUrl: logoUrl,
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          filterQuality: FilterQuality.high,
          placeholder: (_, _) => _titleFallback(item),
          errorWidget: (_, _, _) => _titleFallback(item),
        ),
      );
    }
    return _titleFallback(item);
  }

  Widget _titleFallback(MediaItem item) {
    return cinioFallbackTitle(
      title: item.title,
      seed: item.tmdbId ?? item.id,
      accent: AppColors.accent,
      fontSize: 44,
      textAlign: TextAlign.left,
    );
  }

  Widget _metaBadge(String text, {bool isAccent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
      decoration: BoxDecoration(
        color: isAccent
            ? AppColors.defaultAccent.withValues(alpha: 0.88)
            : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isAccent
              ? AppColors.defaultAccent
              : Colors.white.withValues(alpha: 0.18),
          width: 0.8,
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _imdbRatingBadge(double rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFF5C518),
            borderRadius: BorderRadius.circular(3),
          ),
          child: const Text(
            'IMDb',
            style: TextStyle(
              color: Colors.black,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          rating.toStringAsFixed(1),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _heroCircleUtility({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? AppColors.defaultAccent.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.10),
              border: Border.all(
                color: active
                    ? AppColors.defaultAccent
                    : Colors.white.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            child: Center(
              child: Icon(
                icon,
                color: active ? AppColors.defaultAccent : Colors.white,
                size: 21,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _carouselArrowButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isHovered
                ? Colors.black.withValues(alpha: 0.65)
                : Colors.black.withValues(alpha: 0.25),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 1,
            ),
          ),
          child: Center(
            child: Icon(
              icon,
              color: Colors.white.withValues(alpha: 0.90),
              size: 26,
            ),
          ),
        ),
      ),
    );
  }

  Widget _paginationPill(int index, bool active) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _goToPage(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 28 : 7,
          height: 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: active
                ? Colors.white
                : Colors.white.withValues(alpha: 0.32),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.45),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}

/// Solid white primary "Watch Now" button with hover feedback.
class _HeroPrimaryPlayButton extends StatefulWidget {
  const _HeroPrimaryPlayButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_HeroPrimaryPlayButton> createState() => _HeroPrimaryPlayButtonState();
}

class _HeroPrimaryPlayButtonState extends State<_HeroPrimaryPlayButton> {
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
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          transform: _hovered
              ? Matrix4.diagonal3Values(1.025, 1.025, 1.0)
              : Matrix4.identity(),
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withValues(alpha: 0.92)
                : Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _hovered ? 0.40 : 0.25),
                blurRadius: _hovered ? 14 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.play_arrow_rounded,
                color: Colors.black,
                size: 24,
              ),
              SizedBox(width: 8),
              Text(
                'Watch Now',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Frosted translucent secondary "More Info" button.
class _HeroSecondaryInfoButton extends StatefulWidget {
  const _HeroSecondaryInfoButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_HeroSecondaryInfoButton> createState() =>
      _HeroSecondaryInfoButtonState();
}

class _HeroSecondaryInfoButtonState extends State<_HeroSecondaryInfoButton> {
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
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: _hovered
                  ? Colors.white.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.20),
              width: 1,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: Colors.white,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'More Info',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
