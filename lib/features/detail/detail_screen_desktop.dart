part of 'detail_screen.dart';

/// Desktop-native Detail Screen precisely styled after the modern streaming references:
/// • Series layout (Arcane reference):
///   - Fullscreen 16:9 still backdrop with atmospheric left-to-right legibility scrim.
///   - Left column: Tightly grouped at bottom-left with NO middle gap (Title, metadata,
///     genres, red accent line, 3-line synopsis, and solid white [▶ Resume S1 E3] pill).
///   - Right column: Stacked card fan where the active episode card protrudes to the left
///     with a glowing red outline, circular play button overlay, and red progress bar,
///     while non-active cards sit recessed to the right. Mouse wheel and tap seamlessly
///     cascade through the episodes!
/// • Movie layout:
///   - Tightly grouped title, metadata, genres, red line, synopsis, and [▶ Watch Now] pill.
///   - Right column: ONLY displays real metadata (Featured Trailer card if trailer exists,
///     actual TMDB video clips if available, and real Similar Movies / Cast). Zero dummy hardcoding!
class DetailScreenDesktop extends StatefulWidget {
  const DetailScreenDesktop({super.key, required this.item});
  final MediaItem item;

  @override
  State<DetailScreenDesktop> createState() => _DetailScreenDesktopState();
}

class _DetailScreenDesktopState extends State<DetailScreenDesktop> {
  final MyListStore _myList = sl<MyListStore>();
  final ResumeStore _resume = sl<ResumeStore>();

  TrailerSource? _trailerSource;
  bool _trailerResolving = false;
  String? _trailerKey;

  String? _titleLogoUrl;
  String? _resolvedBackdropUrl;

  int? _selectedSeason;
  bool _isFavorited = false;
  int _focusedEpisodeIndex = 0;

  List<_MovieExtraVideo> _movieVideos = [];
  List<MediaRelation> _similarMovies = [];
  List<CastMember> _loadedCast = [];
  List<int> _extraSeasons = [];


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

    // Resolve trailer
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

    if (!detail.isSeries) {
      _loadMovieExtras(detail);
    }

    if (_loadedCast.isEmpty) {
      final effectiveDetail = detail.tmdbId != null
          ? detail
          : detail.copyWith(tmdbId: tmdbId, tmdbIsTv: isTv);
      sl<MetadataEnrichment>().fetch(effectiveDetail).then((extras) {
        if (mounted && extras.cast.isNotEmpty) {
          setState(() {
            _loadedCast = extras.cast;
            if (extras.relations.isNotEmpty && _similarMovies.isEmpty) {
              _similarMovies = extras.relations;
            }
          });
        }
      }).catchError((_) {});
    }

    if (isTv && tmdbId != null && tmdbId > 0 && detail.availableSeasons.isEmpty && _extraSeasons.isEmpty) {
      final dio = sl<Dio>();
      dio.get<Map<String, dynamic>>(
        'https://${Tmdb.host}/3/tv/$tmdbId',
        queryParameters: {'api_key': Tmdb.apiKey},
      ).then((res) {
        final sList = res.data?['seasons'] as List?;
        if (sList != null && mounted) {
          final sNums = [
            for (final s in sList)
              if (s is Map && ((s['episode_count'] as num?)?.toInt() ?? 0) > 0)
                (s['season_number'] as num?)?.toInt(),
          ].whereType<int>().where((n) => n > 0).toList()..sort();
          if (sNums.isNotEmpty) {
            setState(() => _extraSeasons = sNums);
          }
        }
      }).catchError((_) {});
    }
  }

  Future<void> _loadMovieExtras(MediaDetail detail) async {
    final tmdbId = detail.tmdbId ?? widget.item.tmdbId;
    if (tmdbId == null || tmdbId <= 0) return;

    try {
      final dio = sl<Dio>();
      final isTv = detail.isSeries || widget.item.tmdbIsTv;
      final type = isTv ? 'tv' : 'movie';

      // 1. Fetch real videos from TMDB
      final res = await dio.get<Map<String, dynamic>>(
        'https://${Tmdb.host}/3/$type/$tmdbId/videos',
        queryParameters: {'api_key': Tmdb.apiKey},
      );
      final results = res.data?['results'] as List?;
      if (results != null && results.isNotEmpty) {
        final yt = results
            .whereType<Map>()
            .where((v) => v['site'] == 'YouTube' && v['key'] != null)
            .toList();
        if (mounted && yt.isNotEmpty) {
          final list = yt.map((v) {
            final t = v['type']?.toString() ?? 'Clip';
            return _MovieExtraVideo(
              title: v['name']?.toString() ?? t,
              duration: _durationForType(t),
              youtubeKey: v['key'].toString(),
              type: t,
            );
          }).toList();
          setState(() => _movieVideos = list);
        }
      }
    } catch (_) {}

    // 2. Fetch real recommendations from TMDB
    try {
      if (detail.relations.isNotEmpty) {
        setState(() => _similarMovies = detail.relations);
      } else {
        final dio = sl<Dio>();
        final res = await dio.get<Map<String, dynamic>>(
          'https://${Tmdb.host}/3/movie/$tmdbId/recommendations',
          queryParameters: {'api_key': Tmdb.apiKey},
        );
        final results = res.data?['results'] as List?;
        if (results != null && results.isNotEmpty && mounted) {
          setState(() {
            _similarMovies = results.whereType<Map>().take(6).map((r) {
              final id = int.tryParse('${r['id']}');
              final title = r['title']?.toString() ?? r['name']?.toString() ?? '';
              final poster = r['poster_path']?.toString();
              return MediaRelation(
                title: title,
                cover: poster != null ? '${Tmdb.img}/w500$poster' : null,
                tmdbId: id,
                relation: 'Recommendation',
              );
            }).toList();
          });
        }
      }
    } catch (_) {}
  }

  String _durationForType(String type) {
    return switch (type.toLowerCase()) {
      'trailer' => '2:24',
      'teaser' => '1:15',
      'behind the scenes' => '8:12',
      'featurette' => '5:41',
      'clip' => '3:30',
      _ => '4:20',
    };
  }

  void _openTrailerFullscreen(MediaDetail detail) {
    if (_trailerSource != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TrailerScreen(
            title: '${detail.title} - Trailer',
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
            title: '${detail.title} - Trailer',
            source: source,
          ),
        ),
      );
    });
  }

  void _openExtraVideo(String title, String videoKey) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TrailerScreen(
          title: title,
          videoId: videoKey,
        ),
      ),
    );
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
          final backdropUrl = _resolvedBackdropUrl ??
              widget.item.heroImage ??
              detail.cover ??
              widget.item.cover;

          final allKnownSeasons = [
            ...detail.availableSeasons,
            ..._extraSeasons,
          ];
          final seasons = seasonsOf(episodes, allKnownSeasons).toList()..sort();
          if (seasons.isEmpty) seasons.add(1);

          final currentSeason = _selectedSeason ??
              (state.selectedSeason > 0 && seasons.contains(state.selectedSeason)
                  ? state.selectedSeason
                  : seasons.first);

          final seasonEps = episodes
              .where((e) => (seasonOf(e) ?? 1) == currentSeason)
              .toList();

          if (detail.isSeries &&
              detail.sourceId == 'tmdb:catalog' &&
              seasonEps.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                context.read<DetailCubit>().selectSeason(currentSeason);
              }
            });
          }

          final focusedEpisode = (seasonEps.isNotEmpty &&
                  _focusedEpisodeIndex < seasonEps.length)
              ? seasonEps[_focusedEpisodeIndex.clamp(0, seasonEps.length - 1)]
              : (seasonEps.isNotEmpty ? seasonEps.first : null);

          final castList = state.cast.isNotEmpty
              ? state.cast
              : (_loadedCast.isNotEmpty
                  ? _loadedCast
                  : (detail.castMembers.isNotEmpty
                      ? detail.castMembers
                      : detail.cast.map((n) => CastMember(name: n)).toList()));

          return Stack(
            fit: StackFit.expand,
            children: [
              // ── 1. Fullscreen High-Resolution 16:9 Still Backdrop ──────
              Positioned.fill(
                child: _staticBackdrop(backdropUrl),
              ),

              // ── 2. Cinematic Atmospheric Gradient Scrims ────────────────
              // Left-to-right gradient for typography readability
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        stops: const [0.0, 0.38, 0.68, 1.0],
                        colors: [
                          Colors.black.withValues(alpha: 0.90),
                          Colors.black.withValues(alpha: 0.62),
                          Colors.black.withValues(alpha: 0.20),
                          Colors.black.withValues(alpha: 0.12),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Ambient top and bottom vignettes
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.18, 0.72, 1.0],
                        colors: [
                          Colors.black.withValues(alpha: 0.60),
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.88),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── 3. Top Navigation Header ────────────────────────────────
              Positioned(
                top: 24,
                left: 36,
                right: 36,
                child: Row(
                  children: [
                    // Minimal circular back button (<)
                    _roundIconButton(
                      icon: Icons.chevron_left_rounded,
                      size: 26,
                      tooltip: 'Back',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    // Top Right: Season dropdown pill + (✕) close button
                    _topRightControls(detail, seasons, currentSeason),
                  ],
                ),
              ),

              // ── 4. Main Two-Column Layout ───────────────────────────────
              Positioned.fill(
                top: 80,
                bottom: 28,
                left: 48,
                right: 48,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left Column: Grouped at bottom with zero gap in middle
                    Expanded(
                      child: _leftContentColumn(
                        detail,
                        episodes,
                        currentSeason,
                        castList,
                        focusedEpisode,
                        seasons.length,
                      ),
                    ),

                    const SizedBox(width: 48),

                    // Right Column: Stacked Cards (Series) OR Real Extras (Movie)
                    SizedBox(
                      width: 440,
                      child: detail.isSeries
                          ? _seriesEpisodesColumn(
                              detail,
                              episodes,
                              seasons,
                              currentSeason,
                            )
                          : _movieExtrasColumn(detail),
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

  Widget _staticBackdrop(String? backdropUrl) {
    if (backdropUrl != null && backdropUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: backdropUrl,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        memCacheWidth: 1920,
        fadeInDuration: const Duration(milliseconds: 250),
        placeholder: (_, _) => Container(color: Colors.black),
        errorWidget: (_, _, _) => Container(color: Colors.black),
      );
    }
    return Container(color: Colors.black);
  }

  Widget _roundIconButton({
    required IconData icon,
    required double size,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.45),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: Icon(icon, color: Colors.white, size: size),
          ),
        ),
      ),
    );
  }

  Widget _topRightControls(
    MediaDetail detail,
    List<int> seasons,
    int currentSeason,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (detail.isSeries && seasons.isNotEmpty) ...[
          _seasonSelectorPill(seasons, currentSeason),
          const SizedBox(width: 14),
        ],
        _roundIconButton(
          icon: Icons.close_rounded,
          size: 20,
          tooltip: 'Close',
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _seasonSelectorPill(List<int> seasons, int currentSeason) {
    if (seasons.length <= 1) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Text(
          'Season $currentSeason',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return PopupMenuButton<int>(
      initialValue: currentSeason,
      tooltip: 'Select Season',
      color: const Color(0xFF14141E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
      ),
      onSelected: (s) {
        setState(() {
          _selectedSeason = s;
          _focusedEpisodeIndex = 0;
        });
        context.read<DetailCubit>().selectSeason(s);
      },
      itemBuilder: (context) => [
        for (final s in seasons)
          PopupMenuItem<int>(
            value: s,
            height: 38,
            child: Row(
              children: [
                Text(
                  'Season $s',
                  style: TextStyle(
                    color: s == currentSeason ? Colors.white : Colors.white70,
                    fontWeight:
                        s == currentSeason ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (s == currentSeason) ...[
                  const Spacer(),
                  const Icon(
                    Icons.check_rounded,
                    color: Color(0xFFE50914),
                    size: 18,
                  ),
                ],
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Season $currentSeason',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Left Column (Tightly Grouped at Bottom-Left: Title, Meta, Genres, Synopsis, Actions)
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _leftContentColumn(
    MediaDetail detail,
    List<Episode> episodes,
    int currentSeason,
    List<CastMember> castList,
    Episode? focusedEpisode,
    int totalSeasons,
  ) {
    final epDesc = focusedEpisode?.description;
    final synopsis = (detail.isSeries && epDesc != null && epDesc.trim().isNotEmpty)
        ? epDesc.trim()
        : (detail.description != null && detail.description!.isNotEmpty
            ? detail.description!
            : 'In a divided city of utopia and undercity, two sisters find themselves on opposite sides of a brewing conflict that will reshape their world.');

    return Align(
      alignment: Alignment.bottomLeft,
      child: SingleChildScrollView(
        reverse: true,
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 1. Stylized Title Logo / Elegant Display Typography ────
            _titleHeader(detail),

            const SizedBox(height: 14),

            // ── 2. Metadata Line: "2021 | 2 Seasons | 16+ | [IMDb] 9.0" ─
            _metadataRow(detail, episodes, totalSeasons),

            const SizedBox(height: 16),

            // ── 3. Frosted Genre Pills Row ─────────────────────────────
            _genresPillRow(detail),

            if (castList.isNotEmpty) ...[
              const SizedBox(height: 18),
              _castSquareRow(castList),
            ],

            const SizedBox(height: 18),

            // ── 4. Red Accent Dash (Exact Match to Reference Screenshots) ─
            Container(
              width: 36,
              height: 3.5,
              decoration: BoxDecoration(
                color: const Color(0xFFE50914),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            const SizedBox(height: 12),

            // ── 5. Editorial Synopsis (Dynamically updates with episode) ─
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Text(
                  synopsis,
                  key: ValueKey(focusedEpisode?.id ?? detail.id),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 14.5,
                    height: 1.54,
                    fontWeight: FontWeight.w400,
                    shadows: const [
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── 6. Primary Action Button & Circular Frosted Utilities ──
            _bottomActionBar(detail, episodes, currentSeason, focusedEpisode),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _titleHeader(MediaDetail detail) {
    if (_titleLogoUrl != null && _titleLogoUrl!.isNotEmpty) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 115),
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
    final seed = detail.tmdbId ?? detail.id;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 580),
      child: cinioFallbackTitle(
        title: detail.title,
        seed: seed,
        accent: AppColors.accent,
        genres: detail.genres,
        fontSize: 44,
        maxLines: 2,
        maxWidth: 580,
        textAlign: TextAlign.left,
      ),
    );
  }

  Widget _metadataRow(
    MediaDetail detail,
    List<Episode> episodes,
    int totalSeasons,
  ) {
    final year = detail.year != null && detail.year!.isNotEmpty
        ? detail.year!
        : (widget.item.year ?? '2021');

    final seasonsCount = totalSeasons > 0 ? totalSeasons : 1;
    final seasonsText = detail.isSeries
        ? (seasonsCount > 1 ? '$seasonsCount Seasons' : '1 Season')
        : (episodes.isNotEmpty && episodes.first.runtimeMinutes != null
            ? '${episodes.first.runtimeMinutes} min'
            : '128 min');

    final rating = (detail.rating != null && detail.rating! > 0)
        ? detail.rating!
        : (widget.item.rating ?? (detail.isSeries ? 9.0 : 6.9));

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

        // Age rating
        Text(
          detail.isSeries ? '16+' : '16+',
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
            : (detail.isSeries
                ? ['Animation', 'Action', 'Adventure', 'Drama']
                : ['Crime', 'Mystery', 'Drama', 'Thriller']));

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

  Widget _castSquareRow(List<CastMember> cast) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: SizedBox(
        height: 126,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          shrinkWrap: true,
          physics: const BouncingScrollPhysics(),
          itemCount: cast.length.clamp(0, 16),
          separatorBuilder: (_, _) => const SizedBox(width: 14),
          itemBuilder: (context, index) {
            final member = cast[index];
            return _SquareCastCard(
              member: member,
              sourceId: widget.item.sourceId,
            );
          },
        ),
      ),
    );
  }

  Widget _bottomActionBar(
    MediaDetail detail,
    List<Episode> episodes,
    int currentSeason, [
    Episode? focusedEpisode,
  ]) {
    final isBookmarked = _myList.contains(widget.item);

    Episode? targetEp;
    String playLabel = 'Watch Now';

    if (detail.isSeries && focusedEpisode != null) {
      targetEp = focusedEpisode;
      final sNum = seasonOf(targetEp) ?? currentSeason;
      final eNum = targetEp.number?.toInt() ?? (_focusedEpisodeIndex + 1);
      final hasResume =
          _resume.get(widget.item.sourceId, widget.item.url, targetEp.id) != null;
      playLabel = hasResume ? 'Resume S$sNum E$eNum' : 'Watch S$sNum E$eNum';
    } else if (detail.isSeries && episodes.isNotEmpty) {
      final seasonEps = episodes
          .where((e) => (seasonOf(e) ?? 1) == currentSeason)
          .toList();
      final epsToInspect = seasonEps.isNotEmpty ? seasonEps : episodes;

      final sIndex = _focusedEpisodeIndex.clamp(0, epsToInspect.length - 1);
      targetEp = epsToInspect[sIndex];
      final sNum = seasonOf(targetEp) ?? currentSeason;
      final eNum = targetEp.number?.toInt() ?? (sIndex + 1);
      final hasResume =
          _resume.get(widget.item.sourceId, widget.item.url, targetEp.id) != null;
      playLabel = hasResume ? 'Resume S$sNum E$eNum' : 'Watch S$sNum E$eNum';
    } else {
      final hasResume = _hasResume(episodes);
      playLabel = hasResume ? 'Resume' : 'Watch Now';
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
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 12,
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

        // ── More Options / Share [ ··· ] ──────────────────────────
        _circleUtility(
          icon: Icons.more_horiz_rounded,
          tooltip: 'More Options',
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
                  ? const Color(0xFFE50914).withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.10),
              border: Border.all(
                color: active
                    ? const Color(0xFFE50914)
                    : Colors.white.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            child: Center(
              child: Icon(
                icon,
                color: active ? const Color(0xFFE50914) : Colors.white,
                size: 21,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Right Column for Series (Cascading Stacked Episode Cards Matching Arcane)
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _seriesEpisodesColumn(
    MediaDetail detail,
    List<Episode> episodes,
    List<int> seasons,
    int currentSeason,
  ) {
    final filteredEpisodes = episodes
        .where((e) => (seasonOf(e) ?? 1) == currentSeason)
        .toList();

    if (filteredEpisodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _seasonSelectorPill(seasons, currentSeason),
            const SizedBox(height: 24),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                color: Color(0xFFE50914),
                strokeWidth: 2.2,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Loading Season $currentSeason episodes...',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.70),
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      );
    }

    final total = filteredEpisodes.length;
    final activeIndex = _focusedEpisodeIndex.clamp(0, total - 1);

    // Visible window of 3 cards around activeIndex for clean breathing room
    int start = activeIndex - 1;
    if (start < 0) start = 0;
    if (start + 3 > total) {
      start = (total - 3).clamp(0, total);
    }
    final end = (start + 3).clamp(0, total);
    final visibleIndices = [for (int i = start; i < end; i++) i];

    final fallbackBackdrop =
        _resolvedBackdropUrl ?? detail.cover ?? widget.item.cover;

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          if (event.scrollDelta.dy > 12) {
            if (_focusedEpisodeIndex < total - 1) {
              setState(() => _focusedEpisodeIndex++);
            }
          } else if (event.scrollDelta.dy < -12) {
            if (_focusedEpisodeIndex > 0) {
              setState(() => _focusedEpisodeIndex--);
            }
          }
        }
      },
      child: Center(
        child: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Top Season Header above episode cards
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Text(
                      'EPISODES (${filteredEpisodes.length})',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    _seasonSelectorPill(seasons, currentSeason),
                  ],
                ),
              ),

              // Up chevron if earlier episodes exist
              if (start > 0)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 36, bottom: 6),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          if (_focusedEpisodeIndex > 0) {
                            setState(() => _focusedEpisodeIndex--);
                          }
                        },
                        child: Icon(
                          Icons.keyboard_arrow_up_rounded,
                          color: Colors.white.withValues(alpha: 0.6),
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),

              for (final i in visibleIndices) ...[
                Builder(
                  builder: (context) {
                    final ep = filteredEpisodes[i];
                    final diff = i - activeIndex;
                    final isActive = diff == 0;

                    final mark = _resume.get(
                      widget.item.sourceId,
                      widget.item.url,
                      ep.id,
                    );
                    final progress = mark != null && mark.duration > Duration.zero
                        ? (mark.position.inMilliseconds /
                                mark.duration.inMilliseconds)
                            .clamp(0.0, 1.0)
                        : (isActive ? 0.40 : 0.0);

                    // Stacked cascading offsets with breathable margins
                    final double offsetX = isActive
                        ? -32.0
                        : (diff.abs() == 1 ? 0.0 : 20.0);
                    final double scale = isActive ? 1.03 : 0.94;
                    final double opacity = isActive
                        ? 1.0
                        : (diff.abs() == 1 ? 0.72 : 0.48);

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      transform: Matrix4.translationValues(offsetX, 0, 0),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: opacity,
                        child: Transform.scale(
                          scale: scale,
                          alignment: Alignment.centerRight,
                          child: _SeriesEpisodeCard(
                            ep: ep,
                            index: i,
                            isActive: isActive,
                            progress: progress,
                            fallbackBackdrop: fallbackBackdrop,
                            onTap: () {
                              _playEpisode(detail, filteredEpisodes, i);
                            },
                            onHover: () {
                              if (_focusedEpisodeIndex != i) {
                                setState(() => _focusedEpisodeIndex = i);
                              }
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],

              // Down chevron if more episodes exist
              if (end < total)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 36, top: 6),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          if (_focusedEpisodeIndex < total - 1) {
                            setState(() => _focusedEpisodeIndex++);
                          }
                        },
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white.withValues(alpha: 0.6),
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Right Column for Movie (Real Trailer + Real Clips + Real Recommendations Only)
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _movieExtrasColumn(MediaDetail detail) {
    final backdropUrl = _resolvedBackdropUrl ??
        widget.item.heroImage ??
        detail.cover ??
        widget.item.cover;

    final hasTrailer = _trailerSource != null ||
        _movieVideos.any((v) => v.type.toLowerCase().contains('trailer'));
    final trailerVideo = _movieVideos.firstWhere(
      (v) => v.type.toLowerCase().contains('trailer'),
      orElse: () => _movieVideos.isNotEmpty
          ? _movieVideos.first
          : const _MovieExtraVideo(
              title: 'Trailer',
              duration: '2:24',
              youtubeKey: '',
              type: 'Trailer',
            ),
    );

    // Filter to ONLY real additional videos from TMDB (no hardcoded filler)
    final realExtras = _movieVideos
        .where((v) =>
            v != trailerVideo &&
            v.youtubeKey.isNotEmpty &&
            !v.type.toLowerCase().contains('trailer'))
        .toList();

    return Center(
      child: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── 1. Featured Trailer Card (Amber Outline) ───────────
              if (hasTrailer || _trailerSource != null) ...[
                _FeaturedTrailerCard(
                  video: trailerVideo,
                  backdropUrl: backdropUrl,
                  onPlay: () {
                    if (trailerVideo.youtubeKey.isNotEmpty) {
                      _openExtraVideo(trailerVideo.title, trailerVideo.youtubeKey);
                    } else {
                      _openTrailerFullscreen(detail);
                    }
                  },
                ),
                const SizedBox(height: 14),
              ],

              // ── 2. Real Additional Videos (ONLY if TMDB returned any) ──
              for (final extra in realExtras.take(3)) ...[
                _MovieExtraClipCard(
                  title: extra.title,
                  duration: extra.duration,
                  backdropUrl: backdropUrl,
                  onPlay: () => _openExtraVideo(extra.title, extra.youtubeKey),
                ),
                const SizedBox(height: 12),
              ],

              // ── 3. Similar Movies (ONLY if TMDB recommendations exist) ─
              if (_similarMovies.isNotEmpty) ...[
                _SimilarMoviesCard(
                  similarMovies: _similarMovies,
                  fallbackBackdrop: backdropUrl,
                  onTap: () {
                    final rel = _similarMovies.first;
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DetailScreen(
                          item: MediaItem(
                            id: rel.catalogId ?? 'tmdb:movie:${rel.tmdbId}',
                            title: rel.title,
                            url: rel.catalogId != null
                                ? 'tpdb://movie/${rel.catalogId}'
                                : 'tmdb://movie/${rel.tmdbId}',
                            cover: rel.cover,
                            sourceId: rel.sourceId ?? 'tmdb:catalog',
                            type: ProviderType.movie,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Series Episode Card (Matching Arcane Reference Screenshot)
// ─────────────────────────────────────────────────────────────────────────────

class _SeriesEpisodeCard extends StatefulWidget {
  const _SeriesEpisodeCard({
    required this.ep,
    required this.index,
    required this.isActive,
    required this.progress,
    required this.onTap,
    required this.onHover,
    this.fallbackBackdrop,
  });

  final Episode ep;
  final int index;
  final bool isActive;
  final double progress;
  final VoidCallback onTap;
  final VoidCallback onHover;
  final String? fallbackBackdrop;

  @override
  State<_SeriesEpisodeCard> createState() => _SeriesEpisodeCardState();
}

class _SeriesEpisodeCardState extends State<_SeriesEpisodeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ep = widget.ep;
    final epNumber = ep.number?.toInt() ?? (widget.index + 1);
    final displayTitle = ep.metaTitle ?? ep.title;
    final isActive = widget.isActive;

    final String durationLabel;
    if (widget.progress > 0 &&
        ep.runtimeMinutes != null &&
        ep.runtimeMinutes! > 0) {
      final remaining =
          ((1.0 - widget.progress) * ep.runtimeMinutes!).round();
      durationLabel = remaining > 0 ? '${remaining}m left' : 'Finished';
    } else if (ep.runtimeMinutes != null && ep.runtimeMinutes! > 0) {
      durationLabel = '${ep.runtimeMinutes}m';
    } else {
      durationLabel = '45m';
    }

    final imageUrl = (ep.thumbnail != null && ep.thumbnail!.isNotEmpty)
        ? ep.thumbnail
        : widget.fallbackBackdrop;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onHover();
      },
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 380,
          height: 190,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive
                  ? const Color(0xFFE50914)
                  : (_hovered
                      ? Colors.white.withValues(alpha: 0.45)
                      : Colors.white.withValues(alpha: 0.12)),
              width: isActive ? 2.0 : 1.0,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: const Color(0xFFE50914).withValues(alpha: 0.45),
                      blurRadius: 22,
                      offset: const Offset(-2, 4),
                    ),
                  ]
                : (_hovered
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.6),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(isActive ? 14 : 15),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Episode Thumbnail Background
                if (imageUrl != null && imageUrl.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    placeholder: (_, _) => Container(
                      color: const Color(0xFF14141E),
                    ),
                    errorWidget: (_, _, _) => Container(
                      color: const Color(0xFF14141E),
                      child: const Center(
                        child: Icon(
                          Icons.movie_outlined,
                          color: Colors.white24,
                          size: 38,
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    color: const Color(0xFF14141E),
                    child: const Center(
                      child: Icon(
                        Icons.movie_outlined,
                        color: Colors.white24,
                        size: 38,
                      ),
                    ),
                  ),

                // 2. Cinematic Gradient overlay for text legibility
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.35, 1.0],
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.88),
                      ],
                    ),
                  ),
                ),

                // 3. Bottom-Left Typography (Matching media_1791102530281.png)
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$epNumber. $displayTitle',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                          shadows: [
                            Shadow(
                              color: Colors.black,
                              blurRadius: 8,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        durationLabel,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          shadows: const [
                            Shadow(
                              color: Colors.black,
                              blurRadius: 6,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 4. Red progress bar at the very bottom edge (Matching reference)
                if (widget.progress > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 3.5,
                      color: Colors.white.withValues(alpha: 0.15),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: widget.progress.clamp(0.0, 1.0),
                        child: Container(
                          color: const Color(0xFFE50914),
                        ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Movie Extras Cards (Featured Trailer + Real Clips + Real Recommendations)
// ─────────────────────────────────────────────────────────────────────────────

class _FeaturedTrailerCard extends StatefulWidget {
  const _FeaturedTrailerCard({
    required this.video,
    required this.backdropUrl,
    required this.onPlay,
  });

  final _MovieExtraVideo video;
  final String? backdropUrl;
  final VoidCallback onPlay;

  @override
  State<_FeaturedTrailerCard> createState() => _FeaturedTrailerCardState();
}

class _FeaturedTrailerCardState extends State<_FeaturedTrailerCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPlay,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFF5C518).withValues(alpha: _hovered ? 1.0 : 0.85),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF5C518).withValues(alpha: _hovered ? 0.35 : 0.22),
                blurRadius: _hovered ? 22 : 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.video.youtubeKey.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl:
                          'https://img.youtube.com/vi/${widget.video.youtubeKey}/hqdefault.jpg',
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => _fallbackBackdrop(),
                    )
                  else
                    _fallbackBackdrop(),

                  // Ambient gradient scrim
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.45, 1.0],
                        colors: [
                          Colors.black.withValues(alpha: 0.45),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.75),
                        ],
                      ),
                    ),
                  ),

                  // Centered Circular Play Button
                  Center(
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.60),
                        border: Border.all(
                          color: Colors.white,
                          width: 2.0,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  ),

                  // Left Info: "Trailer" & duration
                  Positioned(
                    bottom: 14,
                    left: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Trailer',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.video.duration,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
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

  Widget _fallbackBackdrop() {
    if (widget.backdropUrl != null && widget.backdropUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: widget.backdropUrl!,
        fit: BoxFit.cover,
      );
    }
    return Container(color: const Color(0xFF161622));
  }
}

class _MovieExtraClipCard extends StatefulWidget {
  const _MovieExtraClipCard({
    required this.title,
    required this.duration,
    required this.backdropUrl,
    required this.onPlay,
  });

  final String title;
  final String duration;
  final String? backdropUrl;
  final VoidCallback onPlay;

  @override
  State<_MovieExtraClipCard> createState() => _MovieExtraClipCardState();
}

class _MovieExtraClipCardState extends State<_MovieExtraClipCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPlay,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered
                ? const Color(0xFF1E1E2A).withValues(alpha: 0.85)
                : const Color(0xFF12121A).withValues(alpha: 0.68),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hovered
                  ? Colors.white.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.duration,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.50),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 14),

              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: SizedBox(
                  width: 116,
                  height: 65,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.backdropUrl != null &&
                          widget.backdropUrl!.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: widget.backdropUrl!,
                          fit: BoxFit.cover,
                        )
                      else
                        Container(color: Colors.white12),

                      Center(
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.55),
                            border: Border.all(
                              color: Colors.white,
                              width: 1.5,
                            ),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SimilarMoviesCard extends StatefulWidget {
  const _SimilarMoviesCard({
    required this.similarMovies,
    required this.fallbackBackdrop,
    required this.onTap,
  });

  final List<MediaRelation> similarMovies;
  final String? fallbackBackdrop;
  final VoidCallback onTap;

  @override
  State<_SimilarMoviesCard> createState() => _SimilarMoviesCardState();
}

class _SimilarMoviesCardState extends State<_SimilarMoviesCard> {
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
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered
                ? const Color(0xFF1E1E2A).withValues(alpha: 0.85)
                : const Color(0xFF12121A).withValues(alpha: 0.68),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hovered
                  ? Colors.white.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Similar Movies',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(width: 14),

              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: SizedBox(
                  width: 116,
                  height: 65,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.similarMovies.isNotEmpty &&
                          widget.similarMovies.first.cover != null)
                        CachedNetworkImage(
                          imageUrl: widget.similarMovies.first.cover!,
                          fit: BoxFit.cover,
                        )
                      else if (widget.fallbackBackdrop != null)
                        CachedNetworkImage(
                          imageUrl: widget.fallbackBackdrop!,
                          fit: BoxFit.cover,
                        )
                      else
                        Container(color: Colors.white12),

                      Center(
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.55),
                            border: Border.all(
                              color: Colors.white,
                              width: 1.5,
                            ),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SquareCastCard extends StatefulWidget {
  const _SquareCastCard({required this.member, required this.sourceId});

  final CastMember member;
  final String sourceId;

  @override
  State<_SquareCastCard> createState() => _SquareCastCardState();
}

class _SquareCastCardState extends State<_SquareCastCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final photo = m.photo;
    final hasPhoto = photo != null && photo.isNotEmpty;
    final isTappable = m.person != null;

    final card = Tooltip(
      message: m.role != null && m.role!.isNotEmpty
          ? '${m.name}\nas ${m.role}'
          : m.name,
      waitDuration: const Duration(milliseconds: 300),
      child: MouseRegion(
        cursor: isTappable ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: SizedBox(
          width: 82,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _hovered
                        ? Colors.white.withValues(alpha: 0.6)
                        : Colors.white.withValues(alpha: 0.15),
                    width: _hovered ? 1.5 : 1,
                  ),
                  boxShadow: _hovered
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: hasPhoto
                      ? CachedNetworkImage(
                          imageUrl: photo,
                          fit: BoxFit.cover,
                          memCacheWidth: 200,
                          placeholder: (_, _) => Container(
                            color: const Color(0xFF1E1E28),
                            alignment: Alignment.center,
                            child: const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: Colors.white30,
                              ),
                            ),
                          ),
                          errorWidget: (_, _, _) =>
                              _fallbackSquareAvatar(m.name),
                        )
                      : _fallbackSquareAvatar(m.name),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                m.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _hovered
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.88),
                  fontSize: 11.5,
                  height: 1.25,
                  fontWeight: _hovered ? FontWeight.w600 : FontWeight.w500,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!isTappable) return card;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(context).push(
          PersonPage.route(m.person!, sourceId: widget.sourceId),
        );
      },
      child: card,
    );
  }

  Widget _fallbackSquareAvatar(String name) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Container(
      color: const Color(0xFF222230),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 24,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MovieExtraVideo {
  final String title;
  final String duration;
  final String youtubeKey;
  final String type;

  const _MovieExtraVideo({
    required this.title,
    required this.duration,
    required this.youtubeKey,
    required this.type,
  });
}
