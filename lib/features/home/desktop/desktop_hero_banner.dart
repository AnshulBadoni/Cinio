import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/di/injector.dart';
import '../../../core/metadata/tmdb.dart';
import '../../../core/models/media_item.dart';
import '../../../core/playback/my_list.dart';
import '../../../core/theme/app_colors.dart';

/// Fullscreen cinematic desktop hero carousel matching reference design.
///
/// Features:
/// • Full-page height (fills viewport) with first row embedded cleanly at the bottom.
/// • Smooth auto-advancing carousel with pause-on-hover.
/// • High-resolution 16:9 widescreen backdrop art with atmospheric scrims.
/// • Bold, clean sans-serif uppercase typography matching the reference design.
/// • Sleek metadata row: Studio/Category tagline · IMDb rating badge · Year.
/// • Redesigned action buttons: Solid vibrant purple [PLAY] pill + Circular (+) outline (no glow).
/// • Zero overlap: Ample vertical breathing room between buttons and the bottom row.
class DesktopHeroBanner extends StatefulWidget {
  const DesktopHeroBanner({
    super.key,
    required this.items,
    required this.onPlay,
    required this.onMoreInfo,
    this.bottomRow,
  });

  final List<MediaItem> items;
  final void Function(MediaItem item) onPlay;
  final void Function(MediaItem item) onMoreInfo;
  final Widget? bottomRow;

  @override
  State<DesktopHeroBanner> createState() => _DesktopHeroBannerState();
}

class _DesktopHeroBannerState extends State<DesktopHeroBanner> {
  late final PageController _pageController;
  int _currentIndex = 0;
  Timer? _autoTimer;
  bool _isHovered = false;

  final MyListStore _myList = sl<MyListStore>();
  final Map<String, String> _backdrops = {};
  final Map<String, String> _overviews = {};
  final Map<String, List<String>> _genres = {};
  final Map<String, String> _studios = {};
  final Map<String, double> _ratings = {};
  final Map<String, String> _years = {};

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
    // 16:9 Backdrop Artwork & Metadata
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
            final comps = data['production_companies'] as List?;
            final vote = (data['vote_average'] as num?)?.toDouble();
            final date = data['release_date']?.toString() ?? data['first_air_date']?.toString();

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
              if (comps != null && comps.isNotEmpty) {
                final c = comps.first;
                if (c is Map && c['name'] != null && c['name'].toString().isNotEmpty) {
                  _studios[item.id] = c['name'].toString();
                }
              }
              if (vote != null && vote > 0) {
                _ratings[item.id] = vote;
              }
              if (date != null && date.length >= 4) {
                _years[item.id] = date.substring(0, 4);
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

    // Full page height matching reference screenshot
    final screenHeight = MediaQuery.sizeOf(context).height;
    final heroHeight = screenHeight.clamp(720.0, 1400.0).toDouble();

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

            // ── 2. Arrow Navigation Controls (on hover) ─────────────
            if (widget.items.length > 1 && _isHovered) ...[
              Positioned(
                left: 16,
                top: heroHeight * 0.28,
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
                right: 16,
                top: heroHeight * 0.28,
                child: _carouselArrowButton(
                  icon: Icons.chevron_right_rounded,
                  onTap: () {
                    final next = (_currentIndex + 1) % widget.items.length;
                    _goToPage(next);
                  },
                ),
              ),
            ],

            // ── 3. Subtle Pagination Indicator Pills (clean, no glow)
            if (widget.items.length > 1)
              Positioned(
                right: 56,
                top: (heroHeight * 0.18).clamp(110.0, 175.0) + 10,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < widget.items.length; i++)
                      _paginationPill(i, i == _currentIndex),
                  ],
                ),
              ),

            // ── 4. First Row ("MY LIST") Embedded Cleanly at Bottom ──
            if (widget.bottomRow != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: widget.bottomRow!,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroSlide(MediaItem item, double heroHeight) {
    final backdrop = _backdrops[item.id] ?? item.heroImage ?? item.cover;
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
        // Left-to-right gradient for crisp typography contrast
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: const [0.0, 0.42, 0.72, 1.0],
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.black.withValues(alpha: 0.58),
                    Colors.black.withValues(alpha: 0.15),
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
                  stops: const [0.35, 0.65, 0.85, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.20),
                    Colors.black.withValues(alpha: 0.70),
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
                    Colors.black.withValues(alpha: 0.55),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── Hero Content (Title / Metadata / Action Buttons) ────────
        // Positioned at upper-middle with ample breathing room above the bottom row
        Positioned(
          left: 56,
          top: (heroHeight * 0.18).clamp(110.0, 175.0),
          right: 140,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Bold, clean sans-serif Title (matching reference image)
                _titleDisplay(item),

                const SizedBox(height: 14),

                // 2. Sleek Metadata Row: Studio/Category tagline · IMDb Rating · Year
                _sleekMetadataRow(item),

                const SizedBox(height: 22),

                // 3. Action Buttons: Solid Purple [PLAY] pill + Circular (+) outline (no glow)
                _actionButtonsRow(item, isBookmarked),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _titleDisplay(MediaItem item) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Text(
        item.title.toUpperCase(),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 44,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
          height: 1.10,
          shadows: [
            Shadow(
              color: Color(0x66000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sleekMetadataRow(MediaItem item) {
    final studio = _studios[item.id];
    final genresList = _genres[item.id] ?? item.genres;
    final rating = _ratings[item.id] ?? item.rating;
    final year = _years[item.id] ?? item.year;

    final String tagline;
    if (studio != null && studio.isNotEmpty) {
      tagline = 'A $studio ${item.tmdbIsTv ? 'Series' : 'Film'}';
    } else if (genresList.isNotEmpty) {
      tagline = '${genresList.take(2).join(' • ')} ${item.tmdbIsTv ? 'Series' : 'Film'}';
    } else {
      tagline = item.tmdbIsTv ? 'Original Series' : 'Original Film';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Studio / Category tagline
        Text(
          tagline,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.82),
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),

        // IMDb rating badge (replaces 98% Match per user request)
        if (rating != null && rating > 0) ...[
          const SizedBox(width: 14),
          _imdbRatingBadge(rating),
        ],

        // Year
        if (year != null && year.isNotEmpty) ...[
          const SizedBox(width: 14),
          Text(
            year,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ],
    );
  }

  Widget _imdbRatingBadge(double rating) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF5C518),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'IMDb',
            style: TextStyle(
              color: Colors.black,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              color: Colors.black,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButtonsRow(MediaItem item, bool isBookmarked) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Vibrant Purple PLAY Button (solid, no glow)
        _HeroPurplePlayButton(
          onTap: () => widget.onPlay(item),
        ),

        const SizedBox(width: 14),

        // Circular (+) outline My List button (clean border, no glow)
        _HeroAddToListCircleButton(
          isBookmarked: isBookmarked,
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
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.45),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 1,
            ),
          ),
          child: Center(
            child: Icon(
              icon,
              color: Colors.white,
              size: 24,
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
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 24 : 7,
          height: 5,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: active
                ? Colors.white
                : Colors.white.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}

/// Vibrant purple primary "PLAY" pill button matching reference design (flat, no glow).
class _HeroPurplePlayButton extends StatefulWidget {
  const _HeroPurplePlayButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_HeroPurplePlayButton> createState() => _HeroPurplePlayButtonState();
}

class _HeroPurplePlayButtonState extends State<_HeroPurplePlayButton> {
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
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 38),
          decoration: BoxDecoration(
            color: _hovered
                ? const Color(0xFF8824F5)
                : const Color(0xFF7A1AF0), // Solid vibrant purple from reference screenshot
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.center,
          child: const Text(
            'PLAY',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular outline (+) bookmark toggle button matching reference design (no glow).
class _HeroAddToListCircleButton extends StatefulWidget {
  const _HeroAddToListCircleButton({
    required this.isBookmarked,
    required this.onTap,
  });

  final bool isBookmarked;
  final VoidCallback onTap;

  @override
  State<_HeroAddToListCircleButton> createState() =>
      _HeroAddToListCircleButtonState();
}

class _HeroAddToListCircleButtonState
    extends State<_HeroAddToListCircleButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.isBookmarked ? 'In My List' : 'Add to My List',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hovered
                  ? Colors.white.withValues(alpha: 0.18)
                  : Colors.black.withValues(alpha: 0.25),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.85),
                width: 1.8,
              ),
            ),
            child: Icon(
              widget.isBookmarked ? Icons.check_rounded : Icons.add_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}
