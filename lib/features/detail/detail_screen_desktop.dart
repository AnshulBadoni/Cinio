part of 'detail_screen.dart';

/// Desktop-native Detail Screen precisely styled after the modern streaming reference:
/// • Full-bleed 16:9 widescreen backdrop / auto-playing muted hero trailer.
/// • Stylized official TMDB title logo with [cinioFallbackTitle] archetype fallback.
/// • Refined metadata line: "2021 | 2 Seasons | 16+ | [IMDb] 9.0" with frosted genre pills.
/// • Open middle layout with red accent dash and high-readability 3-line synopsis.
/// • Action bar: solid white "[ ▶ Resume S1 E3 ]" pill + circular frosted buttons (⤓, +, ♡, ···).
/// • Right-hand floating frosted Episodes Panel with season switching ("Season 1 ˅", "Season 2"),
///   total episodes count, and episode cards with active coral outline, 16:9 thumbnails, and watched checkmarks.
class DetailScreenDesktop extends StatefulWidget {
  const DetailScreenDesktop({super.key, required this.item});
  final MediaItem item;

  @override
  State<DetailScreenDesktop> createState() => _DetailScreenDesktopState();
}

class _DetailScreenDesktopState extends State<DetailScreenDesktop> {
  final MyListStore _myList = sl<MyListStore>();
  final ResumeStore _resume = sl<ResumeStore>();
  final ScrollController _episodesScrollCtrl = ScrollController();

  TrailerSource? _trailerSource;
  bool _trailerResolving = false;
  String? _trailerKey;

  String? _titleLogoUrl;
  String? _resolvedBackdropUrl;

  int? _selectedSeason;
  bool _isFavorited = false;

  int _resumeIndex(List<Episode> eps) {
    if (eps.isEmpty) return 0;
    int? highestMarked;
    for (int j = 0; j < eps.length; j++) {
      final mark = _resume.get(widget.item.sourceId, widget.item.url, eps[j].id);
      if (mark != null) {
        highestMarked = j;
      }
    }
    if (highestMarked == null) return 0;
    final mark = _resume.get(
      widget.item.sourceId,
      widget.item.url,
      eps[highestMarked].id,
    )!;
    if (!mark.finished) return highestMarked;
    if (highestMarked + 1 < eps.length) return highestMarked + 1;
    return highestMarked;
  }

  bool _hasResume(List<Episode> eps) {
    if (eps.isEmpty) return false;
    return eps.any(
      (e) => _resume.get(widget.item.sourceId, widget.item.url, e.id) != null,
    );
  }

  @override
  void initState() {
    super.initState();
    _resolvedBackdropUrl = widget.item.heroImage;
    _loadTitleLogo();

    if (_resolvedBackdropUrl == null || _resolvedBackdropUrl!.isEmpty) {
      _resolve16x9Backdrop();
    }

    final detail = context.read<DetailCubit>().state.detail;
    if (detail != null) {
      _resolveExtras(detail);
    } else {
      _resolveTrailerEagerly(widget.item);
    }
  }

  @override
  void dispose() {
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

      // Fallback search by cleaned title
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

  void _resolveTrailerEagerly(MediaItem item) {
    if (_trailerSource != null) return;
    _trailerResolving = true;

    sl<TrailerService>()
        .resolveTrailer(
          title: item.title,
          englishTitle: item.englishTitle,
          type: item.type,
          year: item.year,
          tmdbId: item.tmdbId,
          isTv: item.tmdbIsTv,
        )
        .then((source) {
      if (!mounted) return;
      if (source != null && _trailerSource == null) {
        setState(() => _trailerSource = source);
      }
    }).catchError((_) {
    }).whenComplete(() {
      if (mounted) _trailerResolving = false;
    });
  }

  void _resolveExtras(MediaDetail detail) {
    final key = '${detail.sourceId}:${detail.id}:${detail.title}';
    if (_trailerKey == key && _trailerSource != null) return;
    _trailerKey = key;

    final tmdbId = detail.tmdbId ?? widget.item.tmdbId;
    final isTv = detail.isSeries || widget.item.tmdbIsTv;

    // Resolve trailer with high priority using official detail TMDB ID
    if (_trailerSource == null) {
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
        if (source != null) {
          setState(() => _trailerSource = source);
        }
      }).catchError((_) {
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
    final isCatalog = widget.item.sourceId == 'tmdb:catalog' ||
        widget.item.sourceId.startsWith('tpdb:');

    ({MediaItem item, MediaDetail detail})? cachedResolved;

    Future<({String url, String sourceId})> resolvePlaybackTarget(String u) async {
      if (!isCatalog) {
        return (url: u, sourceId: detail.sourceId);
      }
      try {
        final resolved = cachedResolved ??= await sl<SourceRepository>()
            .resolveCatalogTitle(
              widget.item,
              category: 'sub',
            )
            .timeout(const Duration(seconds: 10), onTimeout: () => null);

        if (resolved == null) {
          return (url: u, sourceId: detail.sourceId);
        }

        final targetSourceId = resolved.item.sourceId;

        if (targetSourceId.startsWith('stremio:')) {
          final addonId = targetSourceId.substring('stremio:'.length);
          final imdbId =
              resolved.item.imdbId ?? detail.imdbId ?? widget.item.imdbId;
          if (imdbId != null && imdbId.isNotEmpty) {
            Episode? origEp;
            for (final e in eps) {
              if (e.url == u || e.id == u) {
                origEp = e;
                break;
              }
            }
            final isTv = detail.isSeries ||
                widget.item.tmdbIsTv ||
                (origEp != null && origEp.season != null);
            if (isTv) {
              final s = (origEp != null ? seasonOf(origEp) : null) ?? 1;
              final epNum = origEp?.number?.toInt() ?? 1;
              return (
                url: 'stremio://$addonId/stream/series/$imdbId:$s:$epNum',
                sourceId: targetSourceId
              );
            } else {
              return (
                url: 'stremio://$addonId/stream/movie/$imdbId',
                sourceId: targetSourceId
              );
            }
          }
        }

        if (resolved.detail.episodes.isEmpty) {
          return (url: resolved.item.url, sourceId: targetSourceId);
        }
        for (final e in resolved.detail.episodes) {
          if (e.url == u || e.id == u) {
            return (url: e.url, sourceId: targetSourceId);
          }
        }
        Episode? origEp;
        for (final e in eps) {
          if (e.url == u || e.id == u) {
            origEp = e;
            break;
          }
        }
        if (origEp != null) {
          final wantedSeason = seasonOf(origEp);
          final wantedNumber = origEp.number;
          for (final e in resolved.detail.episodes) {
            if (e.number == wantedNumber &&
                (wantedSeason == null || seasonOf(e) == wantedSeason)) {
              return (url: e.url, sourceId: targetSourceId);
            }
          }
          if (wantedNumber != null) {
            for (final e in resolved.detail.episodes) {
              if (e.number == wantedNumber) {
                return (url: e.url, sourceId: targetSourceId);
              }
            }
          }
        }
        return (url: resolved.detail.episodes.first.url, sourceId: targetSourceId);
      } catch (_) {
        return (url: u, sourceId: detail.sourceId);
      }
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          sourceId: isCatalog ? sl<ActiveSourceCubit>().state : detail.sourceId,
          episodes: eps,
          startIndex: index,
          resume: _resume,
          resolveSources: (url) async {
            final target = await resolvePlaybackTarget(url);
            return sl<SourceRepository>().sources(
              target.url,
              sourceId: target.sourceId,
              fast: true,
            );
          },
          pollSources: (url) async {
            final target = await resolvePlaybackTarget(url);
            return sl<SourceRepository>().polledSources(
              target.url,
              sourceId: target.sourceId,
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
            _resolveExtras(detail);
          }
        },
        builder: (context, state) {
          final detail = state.detail;

          if (detail != null && _trailerSource == null && !_trailerResolving) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _trailerSource == null && !_trailerResolving) {
                _resolveExtras(detail);
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
              // ── 1. Full-Screen 16:9 Backdrop Artwork / Auto-Playing Trailer ──
              Positioned.fill(
                child: _backdropView(backdropUrl),
              ),

              // ── 2. Cinematic Atmospheric Scrims ────────────────────
              // Left-to-right gradient for typography legibility while keeping center/right vivid
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        stops: const [0.0, 0.35, 0.65, 1.0],
                        colors: [
                          Colors.black.withValues(alpha: 0.88),
                          Colors.black.withValues(alpha: 0.58),
                          Colors.black.withValues(alpha: 0.15),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Bottom and top ambient vignettes
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.18, 0.70, 1.0],
                        colors: [
                          Colors.black.withValues(alpha: 0.55),
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.85),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── 3. Top Navigation Header ───────────────────────────
              Positioned(
                top: 24,
                left: 36,
                right: 36,
                child: Row(
                  children: [
                    // Minimal circular back button
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.40),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.14),
                              width: 1,
                            ),
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

              // ── 4. Main Two-Column Layout (Matching Arcane Reference) ─
              Positioned.fill(
                top: 76,
                bottom: 28,
                left: 48,
                right: 48,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left Column: Stylized Title, Meta Row, Genres, Open Artwork, Synopsis, Actions
                    Expanded(
                      child: _leftContentColumn(detail, episodes),
                    ),

                    const SizedBox(width: 44),

                    // Right Column: Floating Frosted Episodes Panel
                    SizedBox(
                      width: 420,
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
        autoplay: true,
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
        fadeInDuration: const Duration(milliseconds: 220),
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
          color: Colors.white.withValues(alpha: 0.75),
        ),
        const SizedBox(width: 16),
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
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
  // Left Column (Hero Title, Meta Row, Genres, Synopsis, Action Buttons)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _leftContentColumn(MediaDetail detail, List<Episode> episodes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 1. Stylized Title Logo ─────────────────────────────────
        _titleHeader(detail),

        const SizedBox(height: 18),

        // ── 2. Metadata Line: "2021 | 2 Seasons | 16+ | [IMDb] 9.0" ─
        _metadataRow(detail, episodes),

        const SizedBox(height: 16),

        // ── 3. Frosted Genre Pills Row ─────────────────────────────
        _genresPillRow(detail),

        // ── 4. Open Space Letting Background Artwork Shine ─────────
        const Spacer(),

        // ── 5. Red Accent Dash (Exact Match to Arcane Reference) ───
        Container(
          width: 26,
          height: 3,
          decoration: BoxDecoration(
            color: const Color(0xFFE50914),
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),

        const SizedBox(height: 10),

        // ── 6. Editorial Synopsis ──────────────────────────────────
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Text(
            detail.description != null && detail.description!.isNotEmpty
                ? detail.description!
                : 'An aspiring utopian regime clashes with a violent radical underground. At the heart of this revolution of magic and tech, a family\'s bond is tested.',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              fontSize: 14.5,
              height: 1.52,
              fontWeight: FontWeight.w400,
              shadows: const [
                Shadow(
                  color: Colors.black87,
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 22),

        // ── 7. Primary Action Button & Circular Frosted Utilities ──
        _bottomActionBar(detail, episodes),
      ],
    );
  }

  Widget _titleHeader(MediaDetail detail) {
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
    return cinioFallbackTitle(
      title: detail.title,
      seed: detail.id,
      accent: AppColors.accent,
      genres: detail.genres,
      fontSize: 44,
      textAlign: TextAlign.left,
    );
  }

  Widget _metadataRow(MediaDetail detail, List<Episode> episodes) {
    final year = detail.year != null && detail.year!.isNotEmpty
        ? detail.year!
        : (widget.item.year ?? '2021');

    final seasonsCount = episodes
        .map((e) => seasonOf(e) ?? 1)
        .toSet()
        .length;
    final seasonsText = detail.isSeries
        ? (seasonsCount > 1 ? '$seasonsCount Seasons' : '1 Season')
        : (episodes.isNotEmpty && episodes.first.runtimeMinutes != null
            ? '${episodes.first.runtimeMinutes! ~/ 60}h ${episodes.first.runtimeMinutes! % 60}m'
            : 'Movie');

    final rating = (detail.rating != null && detail.rating! > 0)
        ? detail.rating!
        : (widget.item.rating ?? 9.0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Year
        Text(
          year,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),

        _metaDivider(),

        // Seasons / Duration
        Text(
          seasonsText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),

        _metaDivider(),

        // Content age rating (e.g. 16+ / TV-MA / PG-13)
        Text(
          detail.isSeries ? '16+' : 'PG-13',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),

        _metaDivider(),

        // IMDb Gold Badge + Rating
        _imdbRatingBadge(rating),
      ],
    );
  }

  Widget _metaDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Text(
        '|',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.35),
          fontSize: 14,
          fontWeight: FontWeight.w300,
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
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          rating.toStringAsFixed(1),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _genresPillRow(MediaDetail detail) {
    final genres = detail.genres.isNotEmpty
        ? detail.genres
        : (widget.item.genres.isNotEmpty
            ? widget.item.genres
            : ['Animation', 'Action', 'Adventure', 'Drama']);

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        for (final g in genres.take(4))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6.5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
                width: 1,
              ),
            ),
            child: Text(
              g,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.90),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _bottomActionBar(MediaDetail detail, List<Episode> episodes) {
    final isBookmarked = _myList.contains(widget.item);

    // Determine resume or start episode
    Episode? targetEp;
    String playLabel = 'Watch Now';

    if (detail.isSeries && episodes.isNotEmpty) {
      final hasResume = _hasResume(episodes);
      final rIndex = _resumeIndex(episodes);
      targetEp = episodes[rIndex];
      final sNum = seasonOf(targetEp) ?? 1;
      final eNum = targetEp.number?.toInt() ?? (rIndex + 1);
      playLabel = hasResume
          ? 'Resume S$sNum E$eNum'
          : 'Play S$sNum E$eNum';
    } else {
      final hasResume = _hasResume(episodes);
      playLabel = hasResume ? 'Resume' : 'Watch Movie';
      if (episodes.isNotEmpty) {
        targetEp = episodes.first;
      }
    }

    final targetIndex = targetEp != null ? episodes.indexOf(targetEp) : 0;

    return Row(
      children: [
        // ── Primary Solid White Play / Resume Button ───────────────
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {
              if (episodes.isNotEmpty) {
                _playEpisode(detail, episodes, targetIndex >= 0 ? targetIndex : 0);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.black,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    playLabel,
                    style: const TextStyle(
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
        ),

        const SizedBox(width: 14),

        // ── Download Button [ ⤓ ] ─────────────────────────────────
        _circleUtility(
          icon: Icons.download_rounded,
          tooltip: 'Download',
          onTap: () {
            if (episodes.isNotEmpty) {
              _playEpisode(detail, episodes, targetIndex >= 0 ? targetIndex : 0);
            }
          },
        ),

        const SizedBox(width: 10),

        // ── My List / Watchlist [ + ] ─────────────────────────────
        _circleUtility(
          icon: isBookmarked ? Icons.check_rounded : Icons.add_rounded,
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

        // ── Favorite / Heart [ ♡ ] ────────────────────────────────
        _circleUtility(
          icon: _isFavorited
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          active: _isFavorited,
          tooltip: 'Favorite',
          onTap: () => setState(() => _isFavorited = !_isFavorited),
        ),

        const SizedBox(width: 10),

        // ── More Options / Trailer [ ··· ] ────────────────────────
        _circleUtility(
          icon: Icons.more_horiz_rounded,
          tooltip: 'Trailer & More Options',
          onTap: () => _openTrailerFullscreen(detail),
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

  // ─────────────────────────────────────────────────────────────────────────
  // Right Column (Floating Frosted Episodes Panel - Matching Reference)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _rightEpisodesPanel(MediaDetail detail, List<Episode> episodes) {
    if (!detail.isSeries || episodes.isEmpty) {
      return _movieFallbackPanel(detail);
    }

    final seasons = episodes
        .map((e) => seasonOf(e) ?? 1)
        .toSet()
        .toList()
      ..sort();

    final currentSeason = _selectedSeason ?? (seasons.isNotEmpty ? seasons.first : 1);

    final filteredEpisodes = episodes
        .where((e) => (seasonOf(e) ?? 1) == currentSeason)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F14).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.60),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Season Tabs Header: "Season 1 ˅    Season 2       Episodes 9" ─
          Row(
            children: [
              // Active Season Selector
              _seasonDropdown(seasons, currentSeason),

              if (seasons.length > 1) ...[
                const SizedBox(width: 16),
                for (final s in seasons.where((s) => s != currentSeason).take(2))
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedSeason = s),
                        child: Text(
                          'Season $s',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],

              const Spacer(),

              // Episodes Count Badge (e.g. "Episodes 9")
              Text(
                'Episodes ${filteredEpisodes.length}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Episodes List (Active item highlighted with red outline) ─
          Expanded(
            child: RawScrollbar(
              controller: _episodesScrollCtrl,
              thumbVisibility: false,
              thickness: 4,
              radius: const Radius.circular(4),
              thumbColor: Colors.white.withValues(alpha: 0.20),
              child: ListView.separated(
                controller: _episodesScrollCtrl,
                physics: const BouncingScrollPhysics(),
                itemCount: filteredEpisodes.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final ep = filteredEpisodes[index];
                  final hasResume = _hasResume(episodes);
                  final resumeEpIndex = _resumeIndex(episodes);
                  final isActive = hasResume
                      ? (ep.id == episodes[resumeEpIndex].id)
                      : (index == 0);
                  final isWatched = _resume.get(
                        widget.item.sourceId,
                        widget.item.url,
                        ep.id,
                      )?.finished ??
                      false;

                  return _EpisodeRowItem(
                    ep: ep,
                    index: index,
                    isActive: isActive,
                    isWatched: isWatched,
                    onTap: () => _playEpisode(detail, filteredEpisodes, index),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seasonDropdown(List<int> seasons, int currentSeason) {
    if (seasons.length <= 1) {
      return Text(
        'Season $currentSeason',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    return PopupMenuButton<int>(
      initialValue: currentSeason,
      tooltip: 'Select Season',
      color: const Color(0xFF181820),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Colors.white.withValues(alpha: 0.12),
        ),
      ),
      onSelected: (season) {
        setState(() => _selectedSeason = season);
      },
      itemBuilder: (context) => [
        for (final s in seasons)
          PopupMenuItem<int>(
            value: s,
            child: Row(
              children: [
                Text(
                  'Season $s',
                  style: TextStyle(
                    color: s == currentSeason ? Colors.white : Colors.white70,
                    fontWeight: s == currentSeason
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                if (s == currentSeason) ...[
                  const Spacer(),
                  const Icon(
                    Icons.check_rounded,
                    color: AppColors.defaultAccent,
                    size: 18,
                  ),
                ],
              ],
            ),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Season $currentSeason',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Colors.white,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _movieFallbackPanel(MediaDetail detail) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F14).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FEATURE FILM',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          if (detail.cast.isNotEmpty) ...[
            Text(
              'STARRING',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.40),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in detail.cast.take(6))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      c,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Episode row component exactly matching the Arcane reference:
/// • 16:9 thumbnail on left.
/// • Middle: Episode number (red if active), title, duration · rating.
/// • Trailing: Circular checkmark [✓] if watched, or circular play [▷] if unwatched.
/// • Active item has a subtle red/coral border highlight.
class _EpisodeRowItem extends StatefulWidget {
  const _EpisodeRowItem({
    required this.ep,
    required this.index,
    required this.isActive,
    required this.isWatched,
    required this.onTap,
  });

  final Episode ep;
  final int index;
  final bool isActive;
  final bool isWatched;
  final VoidCallback onTap;

  @override
  State<_EpisodeRowItem> createState() => _EpisodeRowItemState();
}

class _EpisodeRowItemState extends State<_EpisodeRowItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ep = widget.ep;
    final epNumber = ep.number?.toInt() ?? (widget.index + 1);
    final displayTitle = ep.metaTitle ?? ep.title;
    final isActive = widget.isActive;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive
                  ? const Color(0xFFE50914).withValues(alpha: 0.75)
                  : (_hovered
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.04)),
              width: isActive ? 1.2 : 0.8,
            ),
            color: isActive
                ? Colors.white.withValues(alpha: 0.06)
                : (_hovered
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.transparent),
          ),
          child: Row(
            children: [
              // 16:9 Thumbnail (106 × 60)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 106,
                  height: 60,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (ep.thumbnail != null && ep.thumbnail!.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: ep.thumbnail!,
                          fit: BoxFit.cover,
                          memCacheWidth: 220,
                          placeholder: (_, _) => Container(color: AppColors.surface2),
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

                      if (_hovered)
                        Container(
                          color: Colors.black.withValues(alpha: 0.35),
                          child: const Center(
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Number + Title + Duration · Rating
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Text(
                          '$epNumber',
                          style: TextStyle(
                            color: isActive
                                ? const Color(0xFFE50914)
                                : Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ep.runtimeMinutes != null
                          ? '${ep.runtimeMinutes} min'
                          : 'Episode',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.42),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Trailing circular checkmark [✓] or play outline [▷]
              _trailingActionIcon(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trailingActionIcon() {
    if (widget.isWatched) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.45),
            width: 1.2,
          ),
        ),
        child: const Center(
          child: Icon(
            Icons.check_rounded,
            color: Colors.white,
            size: 16,
          ),
        ),
      );
    }

    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.45),
          width: 1.2,
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.play_arrow_rounded,
          color: Colors.white,
          size: 18,
        ),
      ),
    );
  }
}
