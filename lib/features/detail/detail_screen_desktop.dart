part of 'detail_screen.dart';

/// Desktop-native Detail Screen:
/// • 16:9 widescreen backdrop artwork / auto-playing muted trailer.
/// • Official movie title logo (from TMDB) or dynamic Cinio archetype typography.
/// • Multi-season detection via [seasonOf] with instant season switching.
/// • Dedicated smooth scrolling episodes list with desktop scrollbar.
class DetailScreenDesktop extends StatefulWidget {
  const DetailScreenDesktop({super.key, required this.item});
  final MediaItem item;

  @override
  State<DetailScreenDesktop> createState() => _DetailScreenDesktopState();
}

class _DetailScreenDesktopState extends State<DetailScreenDesktop> {
  final MyListStore _myList = sl<MyListStore>();
  final ResumeStore _resume = sl<ResumeStore>();
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _episodesScrollCtrl = ScrollController();

  TrailerSource? _trailerSource;
  bool _trailerResolving = false;
  String? _trailerKey;

  String? _titleLogoUrl;
  String? _resolvedBackdropUrl;

  int? _selectedSeason;
  String _searchQuery = '';
  bool _isLiked = false;
  bool _isWatched = false;
  bool _isFavorited = false;

  @override
  void initState() {
    super.initState();
    _resolvedBackdropUrl = widget.item.heroImage;
    _resolveTrailerForItem(widget.item);
    final detail = context.read<DetailCubit>().state.detail;
    if (detail != null) {
      _resolveExtrasIfNeeded(detail);
    }
    _loadTitleLogo();
    if (_resolvedBackdropUrl == null || _resolvedBackdropUrl!.isEmpty) {
      _resolve16x9Backdrop();
    }
  }

  void _resolveTrailerForItem(MediaItem item) {
    if (_trailerSource != null || _trailerResolving) return;
    _trailerResolving = true;

    final tmdbId = item.tmdbId;
    final isTv = item.tmdbIsTv;

    sl<TrailerService>()
        .resolveTrailer(
          title: item.title,
          englishTitle: item.englishTitle,
          type: item.type,
          year: item.year,
          tmdbId: tmdbId,
          isTv: isTv,
        )
        .then((source) {
      if (!mounted) return;
      if (source != null && source != _trailerSource) {
        setState(() => _trailerSource = source);
      }
    }).catchError((_) {
    }).whenComplete(() {
      if (mounted) _trailerResolving = false;
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _episodesScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTitleLogo() async {
    try {
      final logo = await sl<TitleLogoService>().logoFor(widget.item);
      if (mounted && logo != null && logo.isNotEmpty) {
        setState(() => _titleLogoUrl = logo);
      }
    } catch (_) {}
  }

  Future<void> _resolve16x9Backdrop() async {
    try {
      final dio = sl<Dio>();
      final tmdbId = widget.item.tmdbId;
      final isTv = widget.item.tmdbIsTv;

      if (tmdbId != null && tmdbId > 0) {
        final path = isTv ? 'tv/$tmdbId' : 'movie/$tmdbId';
        final res = await dio.get<Map<String, dynamic>>(
          'https://${Tmdb.host}/3/$path',
          queryParameters: {'api_key': Tmdb.apiKey},
        );
        final bg = res.data?['backdrop_path']?.toString();
        if (mounted && bg != null && bg.isNotEmpty) {
          setState(() => _resolvedBackdropUrl = '${Tmdb.img}/original$bg');
          return;
        }
      }

      // Fallback search by title
      final cleanTitle = widget.item.englishTitle ?? widget.item.title;
      final res = await dio.get<Map<String, dynamic>>(
        'https://${Tmdb.host}/3/search/multi',
        queryParameters: {
          'api_key': Tmdb.apiKey,
          'query': cleanTitle,
        },
      );
      final results = res.data?['results'] as List?;
      if (results != null && results.isNotEmpty) {
        for (final r in results) {
          if (r is Map && r['backdrop_path'] != null) {
            final bg = r['backdrop_path'].toString();
            if (mounted && bg.isNotEmpty) {
              setState(() => _resolvedBackdropUrl = '${Tmdb.img}/original$bg');
              return;
            }
          }
        }
      }
    } catch (_) {}
  }

  void _resolveExtrasIfNeeded(MediaDetail detail) {
    final key = '${detail.sourceId}:${detail.id}:${detail.title}';
    if (_trailerKey == key && _trailerSource != null) return;
    _trailerKey = key;

    final tmdbId = detail.tmdbId ?? widget.item.tmdbId;
    final isTv = detail.isSeries || widget.item.tmdbIsTv;

    if (_trailerSource == null && !_trailerResolving) {
      _trailerResolving = true;
      sl<TrailerService>()
          .resolveTrailer(
            title: detail.title,
            englishTitle: detail.englishTitle,
            type: detail.type,
            year: detail.year ?? widget.item.year,
            tmdbId: tmdbId,
            isTv: isTv,
          )
          .then((source) {
        if (!mounted) return;
        if (source != null && source != _trailerSource) {
          setState(() => _trailerSource = source);
        }
      }).catchError((_) {
        // Optional fallback
      }).whenComplete(() {
        if (mounted) _trailerResolving = false;
      });
    }

    if (_titleLogoUrl == null) {
      sl<TitleLogoService>()
          .logoForDetail(
            title: detail.title,
            tmdbId: tmdbId,
            isTv: isTv,
            year: detail.year ?? widget.item.year,
          )
          .then((logo) {
        if (mounted && logo != null && logo.isNotEmpty) {
          setState(() => _titleLogoUrl = logo);
        }
      }).catchError((_) {});
    }

    if (_resolvedBackdropUrl == null || _resolvedBackdropUrl!.isEmpty) {
      _resolve16x9Backdrop();
    }
  }

  void _openTrailerFullscreen(MediaDetail detail) {
    if (_trailerSource != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TrailerScreen(
            title: detail.title,
            source: _trailerSource!,
          ),
        ),
      );
      return;
    }

    final tmdbId = detail.tmdbId ?? widget.item.tmdbId;
    final isTv = detail.isSeries || widget.item.tmdbIsTv;
    sl<TrailerService>()
        .resolveTrailer(
          title: detail.title,
          englishTitle: detail.englishTitle,
          type: detail.type,
          year: detail.year ?? widget.item.year,
          tmdbId: tmdbId,
          isTv: isTv,
        )
        .then((source) {
      if (!mounted || source == null) return;
      setState(() => _trailerSource = source);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TrailerScreen(
            title: detail.title,
            source: source,
          ),
        ),
      );
    });
  }

  void _playEpisode(MediaDetail detail, List<Episode> eps, int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          sourceId: detail.sourceId,
          episodes: eps,
          startIndex: index,
          resume: _resume,
          resolveSources: (url) async {
            return sl<SourceRepository>().sources(
              url,
              sourceId: detail.sourceId,
              fast: true,
            );
          },
          history: sl<WatchHistory>(),
          showTitle: detail.title,
          cover: detail.cover ?? widget.item.cover,
          coverHeaders: detail.coverHeaders ?? widget.item.coverHeaders,
          showUrl: detail.url,
          category: 'sub',
          scrobbleTitle: detail.title,
          tmdbId: detail.tmdbId ?? widget.item.tmdbId,
          tmdbIsTv: detail.tmdbIsTv,
          imdbId: detail.imdbId ?? widget.item.imdbId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: BlocConsumer<DetailCubit, DetailState>(
        listener: (context, state) {
          final detail = state.detail;
          if (detail != null) {
            _resolveExtrasIfNeeded(detail);
          }
        },
        builder: (context, state) {
          final detail = state.detail;
          if (detail != null && _trailerSource == null && !_trailerResolving) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _trailerSource == null && !_trailerResolving) {
                _resolveExtrasIfNeeded(detail);
              }
            });
          }

          if (state.status == DetailStatus.loading || detail == null) {
            return const Center(
              child: CircularProgressIndicator(
                color: AppColors.defaultAccent,
                strokeWidth: 2.5,
              ),
            );
          }

          final episodes = detail.episodes;
          // Prefer resolved 16:9 backdrop, then heroImage, then cover
          final backdropUrl = _resolvedBackdropUrl ??
              widget.item.heroImage ??
              detail.cover ??
              widget.item.cover;

          return Stack(
            fit: StackFit.expand,
            children: [
              // ── 1. Full-Screen 16:9 Backdrop Artwork / Trailer ────
              Positioned.fill(
                child: _backdropView(backdropUrl),
              ),

              // ── 2. Atmospheric Gradients ───────────────────────────
              // Left-to-right scrim for razor-sharp typography
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        stops: const [0.0, 0.44, 0.72, 1.0],
                        colors: [
                          Colors.black.withValues(alpha: 0.94),
                          Colors.black.withValues(alpha: 0.78),
                          Colors.black.withValues(alpha: 0.32),
                          Colors.black.withValues(alpha: 0.12),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Top and bottom vignettes
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.18, 0.82, 1.0],
                        colors: [
                          Colors.black.withValues(alpha: 0.65),
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.75),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── 3. Top Header (< Back button) ──────────────────────
              Positioned(
                top: 24,
                left: 36,
                right: 36,
                child: Row(
                  children: [
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.40),
                          ),
                          child: const Icon(
                            Icons.chevron_left_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    _topRightUtilities(),
                  ],
                ),
              ),

              // ── 4. Main Two-Column Layout ──────────────────────────
              Positioned.fill(
                top: 78,
                bottom: 24,
                left: 48,
                right: 48,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left Column: Show Metadata, Summary & Action Bar
                    Expanded(
                      child: _leftContentColumn(detail, episodes),
                    ),

                    const SizedBox(width: 48),

                    // Right Column: Floating Frosted Episodes Panel
                    SizedBox(
                      width: 410,
                      child: _rightEpisodesPanel(detail, episodes),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _backdropView(String? backdropUrl) {
    if (_trailerSource != null) {
      return _HeroTrailer(
        key: ValueKey(_trailerSource.hashCode),
        trailer: _trailerSource!,
        collapsed: false,
        placeholder: _staticBackdrop(backdropUrl),
        onTapFullscreen: () {
          final detail = context.read<DetailCubit>().state.detail;
          if (detail != null) _openTrailerFullscreen(detail);
        },
      );
    }
    return _staticBackdrop(backdropUrl);
  }

  Widget _staticBackdrop(String? backdropUrl) {
    if (backdropUrl != null && backdropUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: backdropUrl,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        memCacheWidth: 1920,
        placeholder: (_, _) => Container(color: Colors.black),
        errorWidget: (_, _, _) => Container(color: Colors.black),
      );
    }
    return Container(color: Colors.black);
  }

  Widget _topRightUtilities() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.grid_view_rounded,
          size: 20,
          color: Colors.white.withValues(alpha: 0.70),
        ),
        const SizedBox(width: 14),
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.20),
              width: 1,
            ),
          ),
          child: CircleAvatar(
            backgroundColor: AppColors.surface2,
            child: const Icon(
              Icons.person_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Left Column (Movie Title Logo / Metadata / Action Bar)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _leftContentColumn(MediaDetail detail, List<Episode> episodes) {
    final genres = detail.genres;
    final cast = detail.cast.isNotEmpty
        ? detail.cast
        : detail.castMembers.map((c) => c.name).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),

                // ── Title: Official Movie Title Logo or Cinio Archetype ──
                _titleHeader(detail),

                const SizedBox(height: 22),

                // ── Runtime · Year · IMDb Rating ──────────────────
                Row(
                  children: [
                    Text(
                      detail.isSeries ? '44 min' : '128 min',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(width: 24),

                    Text(
                      detail.year != null && detail.year!.isNotEmpty
                          ? '${detail.year}–'
                          : '2011–',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(width: 24),

                    _imdbRating(detail.rating),
                  ],
                ),

                const SizedBox(height: 28),

                // ── GENRES ─────────────────────────────────────────
                if (genres.isNotEmpty) ...[
                  _sectionSubtitle('GENRES'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      for (final g in genres.take(4)) _frostedPill(g),
                    ],
                  ),
                  const SizedBox(height: 26),
                ],

                // ── CAST ───────────────────────────────────────────
                if (cast.isNotEmpty) ...[
                  _sectionSubtitle('CAST'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      for (final c in cast.take(4)) _frostedPill(c),
                    ],
                  ),
                  const SizedBox(height: 26),
                ],

                // ── SUMMARY ────────────────────────────────────────
                _sectionSubtitle('SUMMARY'),
                const SizedBox(height: 10),
                Text(
                  detail.description != null && detail.description!.isNotEmpty
                      ? detail.description!
                      : 'An anthology horror drama series centering on different characters and locations, showcasing different aspects of horror.',
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13.5,
                    height: 1.55,
                    letterSpacing: -0.05,
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),

        // ── Bottom Action Bar ──────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: _bottomActionBar(detail),
        ),
      ],
    );
  }

  Widget _titleHeader(MediaDetail detail) {
    // If official TMDB stylized title logo exists, display it
    if (_titleLogoUrl != null && _titleLogoUrl!.isNotEmpty) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 110),
        child: CachedNetworkImage(
          imageUrl: _titleLogoUrl!,
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          filterQuality: FilterQuality.high,
          placeholder: (_, _) => _titleTextFallback(detail),
          errorWidget: (_, _, _) => _titleTextFallback(detail),
        ),
      );
    }

    return _titleTextFallback(detail);
  }

  Widget _titleTextFallback(MediaDetail detail) {
    // Dynamic Cinio typography archetype matching movie style
    return cinioFallbackTitle(
      title: detail.title,
      seed: detail.id,
      accent: AppColors.accent,
      fontSize: 42,
      textAlign: TextAlign.left,
    );
  }

  Widget _imdbRating(double? rating) {
    final displayRating = (rating != null && rating > 0)
        ? rating.toStringAsFixed(1)
        : '7.9';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          displayRating,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 7),
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
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionSubtitle(String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.40),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _frostedPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.90),
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _bottomActionBar(MediaDetail detail) {
    final isBookmarked = _myList.contains(widget.item);

    return Row(
      children: [
        // ── "🎬 Trailer" Pill Button ──────────────────────────────
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => _openTrailerFullscreen(detail),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.20),
                  width: 1,
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.movie_creation_outlined,
                    color: Colors.white,
                    size: 19,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Trailer',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(width: 14),

        // ── Bookmark / Add to List ────────────────────────────────
        _circleUtility(
          icon: isBookmarked
              ? Icons.bookmark_added_rounded
              : Icons.bookmark_add_outlined,
          active: isBookmarked,
          tooltip: isBookmarked ? 'In My List' : 'Add to List',
          onTap: () {
            setState(() {
              if (isBookmarked) {
                _myList.remove(widget.item);
              } else {
                _myList.add(widget.item);
              }
            });
          },
        ),

        const SizedBox(width: 10),

        // ── Watched Status ────────────────────────────────────────
        _circleUtility(
          icon: _isWatched
              ? Icons.visibility_rounded
              : Icons.remove_red_eye_outlined,
          active: _isWatched,
          tooltip: 'Mark as Watched',
          onTap: () => setState(() => _isWatched = !_isWatched),
        ),

        const SizedBox(width: 10),

        // ── Like / Thumbs Up ──────────────────────────────────────
        _circleUtility(
          icon: _isLiked
              ? Icons.thumb_up_rounded
              : Icons.thumb_up_alt_outlined,
          active: _isLiked,
          tooltip: 'Like',
          onTap: () => setState(() => _isLiked = !_isLiked),
        ),

        const SizedBox(width: 10),

        // ── Favorite / Heart ──────────────────────────────────────
        _circleUtility(
          icon: _isFavorited
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          active: _isFavorited,
          tooltip: 'Favorite',
          onTap: () => setState(() => _isFavorited = !_isFavorited),
        ),

        const SizedBox(width: 10),

        // ── Share ─────────────────────────────────────────────────
        _circleUtility(
          icon: Icons.share_outlined,
          tooltip: 'Share',
          onTap: () {
            Clipboard.setData(ClipboardData(text: detail.url));
            SharePlus.instance.share(
              ShareParams(text: ShareLink.shareText(widget.item)),
            );
          },
        ),
      ],
    );
  }

  Widget _circleUtility({
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
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? AppColors.defaultAccent.withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.08),
              border: Border.all(
                color: active
                    ? AppColors.defaultAccent
                    : Colors.white.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: Center(
              child: Icon(
                icon,
                color: active ? AppColors.defaultAccent : Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Right Column (Multi-Season Navigation & Scrollable Episodes)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _rightEpisodesPanel(MediaDetail detail, List<Episode> episodes) {
    if (!detail.isSeries || episodes.isEmpty) {
      return _movieFallbackPanel(detail);
    }

    // Extract all unique seasons using the global seasonOf helper
    final seasons = episodes
        .map((e) => seasonOf(e) ?? 1)
        .toSet()
        .toList()
      ..sort();

    final currentSeason = _selectedSeason ?? (seasons.isNotEmpty ? seasons.first : 1);

    final filtered = episodes.where((e) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final title = (e.metaTitle ?? e.title).toLowerCase();
        final numStr = e.number?.toInt().toString() ?? '';
        return title.contains(q) || numStr.contains(q);
      }
      return (seasonOf(e) ?? 1) == currentSeason;
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.65),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Season Controls Header ──────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // < Prev Button
              _seasonNavButton(
                label: 'Prev',
                hasLeading: true,
                enabled: seasons.indexOf(currentSeason) > 0,
                onTap: () {
                  final idx = seasons.indexOf(currentSeason);
                  if (idx > 0) {
                    setState(() => _selectedSeason = seasons[idx - 1]);
                  }
                },
              ),

              // Season N ▾ Dropdown
              _seasonDropdown(seasons, currentSeason),

              // Next > Button
              _seasonNavButton(
                label: 'Next',
                hasLeading: false,
                enabled: seasons.indexOf(currentSeason) < seasons.length - 1,
                onTap: () {
                  final idx = seasons.indexOf(currentSeason);
                  if (idx < seasons.length - 1) {
                    setState(() => _selectedSeason = seasons[idx + 1]);
                  }
                },
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ── "search videos 🔍" Input Pill ────────────────────────
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      hintText: 'search videos',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.40),
                        fontSize: 12.5,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  ),
                ),
                Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.50),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── Scrollable Episodes List with Desktop Scrollbar ──────
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No episodes found',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 13,
                      ),
                    ),
                  )
                : RawScrollbar(
                    controller: _episodesScrollCtrl,
                    thumbVisibility: true,
                    trackVisibility: false,
                    thickness: 6,
                    radius: const Radius.circular(3),
                    thumbColor: Colors.white.withValues(alpha: 0.25),
                    child: ListView.separated(
                      controller: _episodesScrollCtrl,
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final ep = filtered[index];
                        final fullIndex = episodes.indexOf(ep);
                        return _EpisodeCardItem(
                          episode: ep,
                          index: fullIndex >= 0 ? fullIndex : index,
                          onTap: () => _playEpisode(
                            detail,
                            episodes,
                            fullIndex >= 0 ? fullIndex : index,
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _seasonNavButton({
    required String label,
    required bool hasLeading,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.35,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasLeading)
                const Icon(
                  Icons.chevron_left_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (!hasLeading)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: Colors.white,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seasonDropdown(List<int> seasons, int currentSeason) {
    return PopupMenuButton<int>(
      color: const Color(0xFF1E222D),
      initialValue: currentSeason,
      onSelected: (season) {
        setState(() {
          _selectedSeason = season;
          _searchQuery = '';
          _searchCtrl.clear();
        });
      },
      itemBuilder: (context) => [
        for (final s in seasons)
          PopupMenuItem<int>(
            value: s,
            child: Text(
              'Season $s',
              style: TextStyle(
                color: s == currentSeason ? AppColors.defaultAccent : Colors.white,
                fontWeight: s == currentSeason ? FontWeight.w700 : FontWeight.w400,
                fontSize: 13,
              ),
            ),
          ),
      ],
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Season $currentSeason',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down_rounded,
              color: Colors.white.withValues(alpha: 0.70),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _movieFallbackPanel(MediaDetail detail) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.defaultAccent.withValues(alpha: 0.2),
              border: Border.all(color: AppColors.defaultAccent, width: 2),
            ),
            child: const Center(
              child: Icon(
                Icons.play_arrow_rounded,
                color: AppColors.defaultAccent,
                size: 40,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            detail.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Full Movie · ${detail.year ?? ''}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 26),
          FilledButton.icon(
            onPressed: () {
              if (detail.episodes.isNotEmpty) {
                _playEpisode(detail, detail.episodes, 0);
              }
            },
            icon: const Icon(Icons.play_arrow_rounded, size: 22),
            label: const Text(
              'Watch Movie',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Subcomponent: Episode Card Item (16:9 Thumbnail + Clean Typography)
// ─────────────────────────────────────────────────────────────────────────────

class _EpisodeCardItem extends StatefulWidget {
  const _EpisodeCardItem({
    required this.episode,
    required this.index,
    required this.onTap,
  });

  final Episode episode;
  final int index;
  final VoidCallback onTap;

  @override
  State<_EpisodeCardItem> createState() => _EpisodeCardItemState();
}

class _EpisodeCardItemState extends State<_EpisodeCardItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ep = widget.episode;
    final epNumber = ep.number != null ? ep.number!.toInt() : widget.index + 1;
    final displayTitle = ep.metaTitle ??
        (ep.title.isNotEmpty ? ep.title : 'Episode $epNumber');
    final date = ep.date ?? '';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              // 16:9 Thumbnail (104 × 62)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 104,
                  height: 62,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (ep.thumbnail != null && ep.thumbnail!.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: ep.thumbnail!,
                          fit: BoxFit.cover,
                          memCacheWidth: 220,
                          memCacheHeight: 130,
                          placeholder: (_, _) =>
                              Container(color: AppColors.surface2),
                          errorWidget: (_, _, _) => Container(
                            color: AppColors.surface2,
                            child: const Icon(
                              Icons.movie_rounded,
                              color: AppColors.textTertiary,
                              size: 20,
                            ),
                          ),
                        )
                      else
                        Container(
                          color: AppColors.surface2,
                          child: const Icon(
                            Icons.movie_rounded,
                            color: AppColors.textTertiary,
                            size: 20,
                          ),
                        ),

                      // Hover play overlay
                      if (_hovered)
                        Container(
                          color: Colors.black.withValues(alpha: 0.40),
                          child: const Center(
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Title & Date
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$epNumber. $displayTitle',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _hovered
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.90),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (date.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        date,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.42),
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
