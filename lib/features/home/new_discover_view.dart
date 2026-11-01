import 'dart:async';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../core/cache/app_image_cache.dart';
import '../../core/di/injector.dart';
import '../../core/metadata/theporndb.dart';
import '../../core/metadata/tmdb_discover_service.dart';
import '../../core/models/media_item.dart';
import '../../core/models/person.dart';
import '../../core/playback/playback_prefs.dart';
import '../../core/prefs/catalog_source_prefs.dart';
import '../../core/repository/source_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/ui/content_row.dart';
import '../../core/ui/native_cover_provider.dart';
import '../../core/ui/poster_card.dart';
import '../../core/ui/source_switcher.dart';
import '../people/favorite_actors_screen.dart';
import '../search/bloc/search_bloc.dart';
import '../search/bloc/search_state.dart';

/// Modern Discover Page with horizontal infinite-scrolling poster rows.
class NewDiscoverView extends StatefulWidget {
  const NewDiscoverView({
    super.key,
    required this.onTapItem,
    required this.onTapPerson,
    required this.onOpenSeeAll,
    required this.onTapSearch,
    required this.onOpenFilters,
    this.onLongPressItem,
    this.onLongPressPerson,
    this.onBack,
  });

  final void Function(MediaItem item) onTapItem;
  final void Function(PersonRef person) onTapPerson;
  final void Function(
    String title,
    List<MediaItem> items, {
    Future<List<MediaItem>> Function(int)? onLoadMore,
  }) onOpenSeeAll;
  final VoidCallback onTapSearch;
  final VoidCallback onOpenFilters;
  final void Function(MediaItem item, String heroTag)? onLongPressItem;
  final void Function(PersonRef person, String heroTag)? onLongPressPerson;
  final VoidCallback? onBack;

  @override
  State<NewDiscoverView> createState() => _NewDiscoverViewState();
}

class _NewDiscoverViewState extends State<NewDiscoverView>
    with TickerProviderStateMixin {
  final _tmdb = sl<TmdbDiscoverService>();
  final _prefs = sl<CatalogSourcePrefs>();
  ThePornDb? get _tpdb => sl.isRegistered<ThePornDb>() ? sl<ThePornDb>() : null;

  late final AnimationController _gradientAnimCtrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat(reverse: true);

  StreamSubscription<SearchState>? _searchSub;

  Color _prominentColor = const Color(0xFF673AB7);

  // TMDB / Mixed Data
  List<MediaItem> _movies = [];
  int _moviesPage = 1;
  bool _loadingMoreMovies = false;

  List<MediaItem> _series = [];
  int _seriesPage = 1;
  bool _loadingMoreSeries = false;

  List<MediaItem> _anime = [];
  int _animePage = 1;
  bool _loadingMoreAnime = false;

  List<PersonRef> _actors = [];

  // TPDB Data
  List<MediaItem> _popularScenes = [];
  int _popularPage = 1;
  bool _loadingMorePopular = false;

  List<MediaItem> _trendingScenes = [];
  int _trendingPage = 1;
  bool _loadingMoreTrending = false;

  List<MediaItem> _topRatedScenes = [];
  int _topRatedPage = 1;
  bool _loadingMoreTopRated = false;

  // Banner Carousel items (TMDB / Mixed)
  List<MediaItem> _bannerItems = [];

  // Provider section (TPDB mode)
  String _selectedProviderId = 'theporndb';
  List<({String id, String label, String? repo})> _availableProviders = [];

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onPrefsChanged);
    _loadAvailableProviders();
    _loadAllCategories();

    // Listen to SearchBloc filter emissions so Discover updates in real time
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final bloc = context.read<SearchBloc>();
        _searchSub = bloc.stream.listen((state) {
          if (mounted) {
            _loadAllCategories();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _gradientAnimCtrl.dispose();
    _searchSub?.cancel();
    _prefs.removeListener(_onPrefsChanged);
    super.dispose();
  }

  void _onPrefsChanged() {
    if (mounted) {
      _loadAvailableProviders();
      _loadAllCategories();
    }
  }

  CatalogSource get _source => _prefs.source;
  bool get _isTpdb => _source == CatalogSource.thePornDb;
  bool get _isMixed => _source == CatalogSource.mixed;

  void _loadAvailableProviders() {
    final nsfw = categorizedSources().nsfw;
    final list = <({String id, String label, String? repo})>[
      (id: 'theporndb', label: 'ThePornDB Discovery', repo: null),
    ];
    for (final s in nsfw) {
      if (s.id != 'theporndb' && s.id != 'tpdb') {
        list.add(s);
      }
    }
    _availableProviders = list;
    if (!_availableProviders.any((p) => p.id == _selectedProviderId)) {
      _selectedProviderId = _availableProviders.first.id;
    }
  }

  Future<void> _extractProminentColor(String? coverUrl, [Map<String, String>? headers]) async {
    if (coverUrl == null || coverUrl.isEmpty) return;
    try {
      final ImageProvider imageProvider = headers != null && headers.isNotEmpty
          ? nativeCoverProvider(coverUrl, headers)
          : CachedNetworkImageProvider(coverUrl);
      final pal = await PaletteGenerator.fromImageProvider(
        ResizeImage(imageProvider, width: 120),
        size: const Size(120, 180),
        maximumColorCount: 6,
      );
      final color = pal.vibrantColor?.color ??
          pal.dominantColor?.color ??
          pal.darkVibrantColor?.color ??
          pal.mutedColor?.color;
      if (color != null && mounted) {
        setState(() => _prominentColor = color);
      }
    } catch (_) {}
  }

  void _loadAllCategories() {
    if (!mounted) return;

    if (_isTpdb && _tpdb != null) {
      _loadTpdbContent();
    } else if (_isMixed) {
      _loadMixedContent();
    } else {
      _loadTmdbContent();
    }
  }

  void _loadTmdbContent() {
    _moviesPage = 1;
    _seriesPage = 1;
    _animePage = 1;

    _tmdb.getTrendingMovies(page: 1).then((items) {
      if (!mounted) return;
      setState(() {
        _movies = items;
        if (_bannerItems.isEmpty) _bannerItems = items.take(6).toList();
      });
      if (items.isNotEmpty) {
        _extractProminentColor(items.first.cover, items.first.coverHeaders);
      }
    }).catchError((_) {});

    _tmdb.getPopularSeries(page: 1).then((items) {
      if (mounted) setState(() => _series = items);
    }).catchError((_) {});

    _tmdb.getPopularAnime(page: 1).then((items) {
      if (mounted) setState(() => _anime = items);
    }).catchError((_) {});

    _tmdb.getPopularPeople().then((people) {
      if (mounted) setState(() => _actors = people);
    }).catchError((_) {});

    _tmdb.getLatestMovies().then((items) {
      if (!mounted) return;
      if (items.isNotEmpty) {
        setState(() => _bannerItems = items.take(6).toList());
      }
    }).catchError((_) {});
  }

  void _loadTpdbContent() {
    final tpdb = _tpdb!;
    _popularPage = 1;
    _trendingPage = 1;
    _topRatedPage = 1;

    tpdb.popularMovies(page: 1).then((items) {
      if (!mounted) return;
      setState(() {
        _popularScenes = items;
      });
      if (items.isNotEmpty) {
        _extractProminentColor(items.first.cover, items.first.coverHeaders);
      }
    }).catchError((_) {});

    tpdb.trendingMovies(page: 1).then((items) {
      if (!mounted) return;
      setState(() {
        _trendingScenes = items;
        if (_bannerItems.isEmpty) _bannerItems = items.take(6).toList();
      });
      if (_popularScenes.isEmpty && items.isNotEmpty) {
        _extractProminentColor(items.first.cover, items.first.coverHeaders);
      }
    }).catchError((_) {});

    tpdb.topRatedMovies(page: 1).then((items) {
      if (!mounted) return;
      setState(() => _topRatedScenes = items);
    }).catchError((_) {});

    tpdb.performers().then((performers) {
      if (!mounted) return;
      final actors = performers
          .map((p) => PersonRef(
                id: 0,
                externalId: p.id.replaceFirst('tpdb:performer:', ''),
                source: PersonSource.thePornDbPerformer,
                name: p.title,
                photo: p.cover,
              ))
          .toList();
      setState(() => _actors = actors);
    }).catchError((_) {});
  }

  void _loadMixedContent() {
    _moviesPage = 1;
    _seriesPage = 1;
    _animePage = 1;

    final tpdb = _tpdb;
    List<MediaItem> tmdbMovies = [];
    List<MediaItem> tpdbMovies = [];
    List<PersonRef> tmdbPeople = [];
    List<PersonRef> tpdbPeople = [];

    void updateMovies() {
      if (!mounted) return;
      final mixed = _interleaveItems(tmdbMovies, tpdbMovies);
      setState(() {
        _movies = mixed;
        if (mixed.isNotEmpty) _bannerItems = mixed.take(6).toList();
      });
      if (mixed.isNotEmpty) {
        _extractProminentColor(mixed.first.cover, mixed.first.coverHeaders);
      }
    }

    void updatePeople() {
      if (!mounted) return;
      setState(() {
        _actors = _interleavePeople(tmdbPeople, tpdbPeople);
      });
    }

    _tmdb.getTrendingMovies(page: 1).then((items) {
      tmdbMovies = items;
      updateMovies();
    }).catchError((_) {});

    _tmdb.getPopularSeries(page: 1).then((items) {
      if (mounted) setState(() => _series = items);
    }).catchError((_) {});

    _tmdb.getPopularAnime(page: 1).then((items) {
      if (mounted) setState(() => _anime = items);
    }).catchError((_) {});

    _tmdb.getPopularPeople().then((people) {
      tmdbPeople = people;
      updatePeople();
    }).catchError((_) {});

    if (tpdb != null) {
      tpdb.trendingMovies(page: 1).then((items) {
        tpdbMovies = items;
        updateMovies();
      }).catchError((_) {});

      tpdb.performers().then((performers) {
        tpdbPeople = performers
            .map((p) => PersonRef(
                  id: 0,
                  externalId: p.id.replaceFirst('tpdb:performer:', ''),
                  source: PersonSource.thePornDbPerformer,
                  name: p.title,
                  photo: p.cover,
                ))
            .toList();
        updatePeople();
      }).catchError((_) {});
    }
  }

  // ── Pagination helpers ───────────────────────────────────────────────────────
  Future<void> _loadMoreMovies() async {
    if (_loadingMoreMovies) return;
    setState(() => _loadingMoreMovies = true);
    final nextPage = _moviesPage + 1;
    try {
      final more = await _tmdb.getTrendingMovies(page: nextPage);
      if (mounted && more.isNotEmpty) {
        setState(() {
          _moviesPage = nextPage;
          _movies.addAll(more);
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingMoreMovies = false);
    }
  }

  Future<void> _loadMoreSeries() async {
    if (_loadingMoreSeries) return;
    setState(() => _loadingMoreSeries = true);
    final nextPage = _seriesPage + 1;
    try {
      final more = await _tmdb.getPopularSeries(page: nextPage);
      if (mounted && more.isNotEmpty) {
        setState(() {
          _seriesPage = nextPage;
          _series.addAll(more);
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingMoreSeries = false);
    }
  }

  Future<void> _loadMoreAnime() async {
    if (_loadingMoreAnime) return;
    setState(() => _loadingMoreAnime = true);
    final nextPage = _animePage + 1;
    try {
      final more = await _tmdb.getPopularAnime(page: nextPage);
      if (mounted && more.isNotEmpty) {
        setState(() {
          _animePage = nextPage;
          _anime.addAll(more);
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingMoreAnime = false);
    }
  }

  Future<void> _loadMorePopular() async {
    if (_loadingMorePopular || _tpdb == null) return;
    setState(() => _loadingMorePopular = true);
    final nextPage = _popularPage + 1;
    try {
      final more = await _tpdb!.popularMovies(page: nextPage);
      if (mounted && more.isNotEmpty) {
        setState(() {
          _popularPage = nextPage;
          _popularScenes.addAll(more);
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingMorePopular = false);
    }
  }

  Future<void> _loadMoreTrending() async {
    if (_loadingMoreTrending || _tpdb == null) return;
    setState(() => _loadingMoreTrending = true);
    final nextPage = _trendingPage + 1;
    try {
      final more = await _tpdb!.trendingMovies(page: nextPage);
      if (mounted && more.isNotEmpty) {
        setState(() {
          _trendingPage = nextPage;
          _trendingScenes.addAll(more);
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingMoreTrending = false);
    }
  }

  Future<void> _loadMoreTopRated() async {
    if (_loadingMoreTopRated || _tpdb == null) return;
    setState(() => _loadingMoreTopRated = true);
    final nextPage = _topRatedPage + 1;
    try {
      final more = await _tpdb!.topRatedMovies(page: nextPage);
      if (mounted && more.isNotEmpty) {
        setState(() {
          _topRatedPage = nextPage;
          _topRatedScenes.addAll(more);
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingMoreTopRated = false);
    }
  }

  List<MediaItem> _interleaveItems(List<MediaItem> a, List<MediaItem> b) {
    final out = <MediaItem>[];
    var i = 0, j = 0;
    while (i < a.length || j < b.length) {
      if (i < a.length) out.add(a[i++]);
      if (j < b.length) out.add(b[j++]);
    }
    return out;
  }

  List<PersonRef> _interleavePeople(List<PersonRef> a, List<PersonRef> b) {
    final out = <PersonRef>[];
    var i = 0, j = 0;
    while (i < a.length || j < b.length) {
      if (i < a.length) out.add(a[i++]);
      if (j < b.length) out.add(b[j++]);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return ValueListenableBuilder<int>(
      valueListenable: PlaybackPrefs.hideTitlesRevision,
      builder: (context, _, _) {
        final hideTitles = sl<PlaybackPrefs>().hideTitles;
        final spacing = sl<PlaybackPrefs>().hiddenTitleSpacing;
        const width = 140.0;
        final rowHeight = hideTitles ? (width / (2 / 3)) + spacing : 236.0;

        return Stack(
          children: [
            // Top moving ambient radial gradient from prominent color of top movie
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 480,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _gradientAnimCtrl,
                  builder: (context, _) {
                    final t = _gradientAnimCtrl.value;
                    final center = Alignment(
                      -0.7 + 0.9 * t,
                      -1.0 + 0.35 * math.sin(t * math.pi),
                    );
                    final radius = 1.35 + 0.25 * math.sin(t * math.pi);
                    return Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: center,
                          radius: radius,
                          colors: [
                            _prominentColor.withValues(alpha: 0.52),
                            _prominentColor.withValues(alpha: 0.24),
                            _prominentColor.withValues(alpha: 0.08),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.45, 0.75, 1.0],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 18)),
                if (_isTpdb) ...[
                  // TPDB Mode: Popular, Trending, Top Rated, Performers, New Releases
                  SliverToBoxAdapter(
                    child: ContentRow(
                      title: 'Popular',
                      itemWidth: width,
                      itemHeight: rowHeight,
                      itemCount: _popularScenes.length,
                      onSeeAll: () => widget.onOpenSeeAll(
                        'Popular',
                        _popularScenes,
                        onLoadMore: (p) => _tpdb?.popularMovies(page: p) ?? Future.value([]),
                      ),
                      onLoadMore: _loadMorePopular,
                      isLoadingMore: _loadingMorePopular,
                      itemBuilder: (c, i) => _buildPosterCard(
                        _popularScenes[i],
                        'tpdb:popular:$i:${_popularScenes[i].id}',
                        width,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  SliverToBoxAdapter(
                    child: ContentRow(
                      title: 'Trending',
                      itemWidth: width,
                      itemHeight: rowHeight,
                      itemCount: _trendingScenes.length,
                      onSeeAll: () => widget.onOpenSeeAll(
                        'Trending',
                        _trendingScenes,
                        onLoadMore: (p) => _tpdb?.trendingMovies(page: p) ?? Future.value([]),
                      ),
                      onLoadMore: _loadMoreTrending,
                      isLoadingMore: _loadingMoreTrending,
                      itemBuilder: (c, i) => _buildPosterCard(
                        _trendingScenes[i],
                        'tpdb:trending:$i:${_trendingScenes[i].id}',
                        width,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  SliverToBoxAdapter(
                    child: ContentRow(
                      title: 'Top Rated',
                      itemWidth: width,
                      itemHeight: rowHeight,
                      itemCount: _topRatedScenes.length,
                      onSeeAll: () => widget.onOpenSeeAll(
                        'Top Rated',
                        _topRatedScenes,
                        onLoadMore: (p) => _tpdb?.topRatedMovies(page: p) ?? Future.value([]),
                      ),
                      onLoadMore: _loadMoreTopRated,
                      isLoadingMore: _loadingMoreTopRated,
                      itemBuilder: (c, i) => _buildPosterCard(
                        _topRatedScenes[i],
                        'tpdb:toprated:$i:${_topRatedScenes[i].id}',
                        width,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  SliverToBoxAdapter(
                    child: _buildActorsSection(hideTitles),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  SliverToBoxAdapter(
                    child: _buildBannerSection(
                      title: 'New Releases',
                      items: _bannerItems,
                      onSeeAll: () => _openTpdbProviderView(context),
                    ),
                  ),
                ] else ...[
                  // TMDB & Mixed Mode: Movies, Series, Anime, Actors, New Releases
                  SliverToBoxAdapter(
                    child: ContentRow(
                      title: 'Movies',
                      itemWidth: width,
                      itemHeight: rowHeight,
                      itemCount: _movies.length,
                      onSeeAll: () => widget.onOpenSeeAll(
                        'Movies',
                        _movies,
                        onLoadMore: _isMixed ? null : (p) => _tmdb.getTrendingMovies(page: p),
                      ),
                      onLoadMore: _isMixed ? null : _loadMoreMovies,
                      isLoadingMore: _loadingMoreMovies,
                      itemBuilder: (c, i) => _buildPosterCard(
                        _movies[i],
                        'discover:movies:$i:${_movies[i].id}',
                        width,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  SliverToBoxAdapter(
                    child: ContentRow(
                      title: 'Series',
                      itemWidth: width,
                      itemHeight: rowHeight,
                      itemCount: _series.length,
                      onSeeAll: () => widget.onOpenSeeAll(
                        'Series',
                        _series,
                        onLoadMore: (p) => _tmdb.getPopularSeries(page: p),
                      ),
                      onLoadMore: _loadMoreSeries,
                      isLoadingMore: _loadingMoreSeries,
                      itemBuilder: (c, i) => _buildPosterCard(
                        _series[i],
                        'discover:series:$i:${_series[i].id}',
                        width,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  SliverToBoxAdapter(
                    child: ContentRow(
                      title: 'Anime',
                      itemWidth: width,
                      itemHeight: rowHeight,
                      itemCount: _anime.length,
                      onSeeAll: () => widget.onOpenSeeAll(
                        'Anime',
                        _anime,
                        onLoadMore: (p) => _tmdb.getPopularAnime(page: p),
                      ),
                      onLoadMore: _loadMoreAnime,
                      isLoadingMore: _loadingMoreAnime,
                      itemBuilder: (c, i) => _buildPosterCard(
                        _anime[i],
                        'discover:anime:$i:${_anime[i].id}',
                        width,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  SliverToBoxAdapter(
                    child: _buildActorsSection(hideTitles),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  SliverToBoxAdapter(
                    child: _buildBannerSection(
                      title: 'New Releases',
                      items: _bannerItems,
                      onSeeAll: () => widget.onOpenSeeAll('New Releases', _bannerItems),
                    ),
                  ),
                ],
                // Bottom padding so content scrolls clear of the bottom floating search pill
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
            ),

            // Bottom Floating Search Bar Pill + Filter Toggle (Fixed at bottom)
            Positioned(
              left: 16,
              right: 16,
              bottom: bottomInset > 0 ? bottomInset + 10 : 16,
              child: Builder(
                builder: (context) {
                  final materialThemeBg = Color.lerp(
                    ThemeController.materialYou ? AppColors.surface2 : const Color(0xFF221C1A),
                    AppColors.accent,
                    0.08,
                  )!;
                  return Row(
                    children: [
                      Expanded(child: _buildFloatingSearchBar(materialThemeBg)),
                      const SizedBox(width: 10),
                      _GlassFilterButton(onTap: widget.onOpenFilters, bgColor: materialThemeBg),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPosterCard(MediaItem item, String heroTag, double width) {
    return PosterCard(
      title: item.title,
      imageUrl: item.cover,
      headers: item.coverHeaders,
      cellWidth: width,
      qualityBadge: item.quality,
      dubBadge: item.dubBadge,
      heroTag: heroTag,
      onTap: () => widget.onTapItem(item),
      onLongPress: () => widget.onLongPressItem?.call(item, heroTag),
    );
  }

  void _openTpdbProviderView(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TpdbProviderScreen(
          availableProviders: _availableProviders,
          initialProviderId: _selectedProviderId,
          onTapItem: widget.onTapItem,
          onLongPressItem: widget.onLongPressItem,
        ),
      ),
    );
  }

  Widget _buildActorsSection(bool hideTitles) {
    final square = sl<PlaybackPrefs>().peopleCardStyle == 'square';
    final cardWidth = square ? 120.0 : 108.0;
    final cardHeight = hideTitles
        ? (square ? 116.0 : 106.0)
        : (square ? 156.0 : 148.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Actors',
                  style: AppText.headline.copyWith(
                    color: const Color(0xFFEDE8E4),
                    fontSize: 16.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              _GlassChevronButton(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const FavoriteActorsScreen(),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: cardHeight,
          child: _actors.isEmpty
              ? const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24),
                  ),
                )
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _actors.length,
                  itemBuilder: (context, index) {
                    final actor = _actors[index];
                    final heroTag = 'discover:actor:$index:${actor.id}:${actor.name}';
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: cardWidth,
                        child: _DiscoverActorCard(
                          actor: actor,
                          square: square,
                          hideTitles: hideTitles,
                          heroTag: heroTag,
                          onTap: () => widget.onTapPerson(actor),
                          onLongPress: () => widget.onLongPressPerson?.call(actor, heroTag),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildBannerSection({
    required String title,
    required List<MediaItem> items,
    required VoidCallback onSeeAll,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppText.headline.copyWith(
                    color: const Color(0xFFEDE8E4),
                    fontSize: 16.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              _GlassChevronButton(onTap: onSeeAll),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _NewReleasesCarousel(
            items: items,
            onTap: widget.onTapItem,
            onLongPress: widget.onLongPressItem,
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingSearchBar(Color bg) {
    final unselectedColor = Color.lerp(
      const Color(0xFFDEC5BF),
      AppColors.accent,
      0.12,
    )!;
    return GestureDetector(
      onTap: widget.onTapSearch,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              color: unselectedColor,
              size: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Search movies, series, anime...',
                style: AppText.body.copyWith(
                  color: unselectedColor.withValues(alpha: 0.8),
                  fontSize: 14,
                ),
              ),
            ),
            Icon(
              Icons.mic_none_rounded,
              color: unselectedColor.withValues(alpha: 0.8),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

/// Wider landscape 16:9 poster card for TPDB New Releases
class _DiscoverWiderCard extends StatefulWidget {
  const _DiscoverWiderCard({
    required this.item,
    required this.heroTag,
    required this.onTap,
    required this.onLongPress,
    required this.width,
    required this.height,
  });

  final MediaItem item;
  final String heroTag;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final double width;
  final double height;

  @override
  State<_DiscoverWiderCard> createState() => _DiscoverWiderCardState();
}

class _DiscoverWiderCardState extends State<_DiscoverWiderCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: widget.width,
            height: widget.height,
            color: const Color(0xFF16161D),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (widget.item.cover != null && widget.item.cover!.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: widget.item.cover!,
                    fit: BoxFit.cover,
                    cacheManager: AppImageCache.cacheManagerOrDefault,
                    errorWidget: (_, _, _) => Container(color: const Color(0xFF1E1E26)),
                  )
                else
                  Container(color: const Color(0xFF1E1E26)),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Color(0xB3000000),
                      ],
                      stops: [0.45, 1.0],
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  bottom: 8,
                  right: 10,
                  child: Text(
                    widget.item.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

/// Actor card following circle vs square people preference with smooth scale animation
class _DiscoverActorCard extends StatefulWidget {
  const _DiscoverActorCard({
    required this.actor,
    required this.square,
    required this.hideTitles,
    required this.heroTag,
    required this.onTap,
    required this.onLongPress,
  });

  final PersonRef actor;
  final bool square;
  final bool hideTitles;
  final String heroTag;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_DiscoverActorCard> createState() => _DiscoverActorCardState();
}

class _DiscoverActorCardState extends State<_DiscoverActorCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final avatarSize = widget.square ? 112.0 : 102.0;

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: avatarSize,
              height: avatarSize,
              decoration: BoxDecoration(
                shape: widget.square ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: widget.square ? BorderRadius.circular(16) : null,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x44000000),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: widget.square
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _buildAvatarImage(),
                    )
                  : ClipOval(
                      child: _buildAvatarImage(),
                    ),
            ),
            if (!widget.hideTitles) ...[
              const SizedBox(height: 6),
              Text(
                widget.actor.name,
                style: AppText.caption.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.0,
                ),
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarImage() {
    final photo = widget.actor.photo;
    if (photo != null && photo.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: photo,
        fit: BoxFit.cover,
        cacheManager: AppImageCache.cacheManagerOrDefault,
        errorWidget: (_, _, _) => Container(
          color: AppColors.surface2,
          child: const Icon(Icons.person_rounded, color: AppColors.textTertiary, size: 36),
        ),
      );
    }
    return Container(
      color: AppColors.surface2,
      child: const Icon(Icons.person_rounded, color: AppColors.textTertiary, size: 36),
    );
  }
}

/// Auto-sliding Widescreen New Releases Banner Carousel
class _NewReleasesCarousel extends StatefulWidget {
  const _NewReleasesCarousel({
    required this.items,
    required this.onTap,
    this.onLongPress,
  });

  final List<MediaItem> items;
  final void Function(MediaItem) onTap;
  final void Function(MediaItem, String)? onLongPress;

  @override
  State<_NewReleasesCarousel> createState() => _NewReleasesCarouselState();
}

class _NewReleasesCarouselState extends State<_NewReleasesCarousel> {
  late final PageController _pageController;
  Timer? _timer;
  int _currentPage = 0;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.items.length <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_pageController.hasClients || widget.items.isEmpty) return;
      final nextPage = (_currentPage + 1) % widget.items.length;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void didUpdateWidget(covariant _NewReleasesCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.length > 1 && (_timer == null || !_timer!.isActive)) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final carouselHeight = ((screenWidth - 32) * 9 / 16).clamp(148.0, 196.0);

    if (widget.items.isEmpty) {
      return Container(
        height: carouselHeight,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(18),
        ),
      );
    }

    return AnimatedScale(
      scale: _pressed ? 0.96 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: carouselHeight,
          decoration: BoxDecoration(
            color: const Color(0xFF16161D),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: widget.items.length,
                onPageChanged: (idx) {
                  setState(() => _currentPage = idx);
                },
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  final imageUrl = item.heroImage ?? item.cover;
                  final heroTag = 'discover:banner:$index:${item.id}';

                  return GestureDetector(
                    onTap: () => widget.onTap(item),
                    onLongPress: () => widget.onLongPress?.call(item, heroTag),
                    onTapDown: (_) => setState(() => _pressed = true),
                    onTapUp: (_) => setState(() => _pressed = false),
                    onTapCancel: () => setState(() => _pressed = false),
                    behavior: HitTestBehavior.opaque,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (imageUrl != null && imageUrl.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            cacheManager: AppImageCache.cacheManagerOrDefault,
                            errorWidget: (_, _, _) => Container(
                              color: const Color(0xFF1E1E26),
                            ),
                          )
                        else
                          Container(color: const Color(0xFF1E1E26)),
                      ],
                    ),
                  );
                },
              ),

              // Animated Pagination Dots
              if (widget.items.length > 1)
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      widget.items.length.clamp(0, 6),
                      (i) {
                        final isActive = i == _currentPage % widget.items.length;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 2.5),
                          width: isActive ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isActive
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      },
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

/// The circular glass filter button in top right of Discover header
class _GlassFilterButton extends StatefulWidget {
  const _GlassFilterButton({required this.onTap, this.bgColor});

  final VoidCallback onTap;
  final Color? bgColor;

  @override
  State<_GlassFilterButton> createState() => _GlassFilterButtonState();
}

class _GlassFilterButtonState extends State<_GlassFilterButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.bgColor ?? const Color(0x6618181E);
    final iconColor = Color.lerp(
      const Color(0xFFDEC5BF),
      AppColors.accent,
      0.12,
    )!;
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.90 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bg,
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: Icon(
              Icons.tune_rounded,
              color: iconColor,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

/// The circular glass chevron button matching home screen ContentRow header
class _GlassChevronButton extends StatefulWidget {
  const _GlassChevronButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_GlassChevronButton> createState() => _GlassChevronButtonState();
}

class _GlassChevronButtonState extends State<_GlassChevronButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.90 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: ClipOval(
          child: Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0x6618181E),
            ),
            child: const Center(
              child: Padding(
                padding: EdgeInsets.only(left: 1.5),
                child: Icon(
                  CupertinoIcons.chevron_right,
                  size: 13,
                  color: Color(0xDDFFFFFF),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dedicated provider screen for TPDB New Releases ("View all")
class _TpdbProviderScreen extends StatefulWidget {
  const _TpdbProviderScreen({
    required this.availableProviders,
    required this.initialProviderId,
    required this.onTapItem,
    required this.onLongPressItem,
  });

  final List<({String id, String label, String? repo})> availableProviders;
  final String initialProviderId;
  final void Function(MediaItem) onTapItem;
  final void Function(MediaItem, String)? onLongPressItem;

  @override
  State<_TpdbProviderScreen> createState() => _TpdbProviderScreenState();
}

class _TpdbProviderScreenState extends State<_TpdbProviderScreen> {
  late String _selectedId;
  List<MediaItem> _items = [];
  bool _loading = false;
  final SourceRepository _repo = sl<SourceRepository>();
  ThePornDb? get _tpdb => sl.isRegistered<ThePornDb>() ? sl<ThePornDb>() : null;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialProviderId;
    _fetchItems(_selectedId);
  }

  Future<void> _fetchItems(String providerId) async {
    setState(() => _loading = true);
    try {
      List<MediaItem> items;
      if (providerId == 'theporndb' || providerId == 'tpdb') {
        items = await (_tpdb?.trendingMovies() ?? Future.value(<MediaItem>[]));
      } else {
        final sections = await _repo.home(sourceId: providerId);
        final out = <MediaItem>[];
        for (final sec in sections) {
          out.addAll(sec.items);
        }
        items = out;
      }
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedProvider = widget.availableProviders.firstWhere(
      (p) => p.id == _selectedId,
      orElse: () => (id: _selectedId, label: 'Provider', repo: null),
    );

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'New Releases',
          style: AppText.headline.copyWith(
            color: const Color(0xFFEDE8E4),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Provider selector chips (XNXX, Xtapes, ThePornDB Discovery)
          SizedBox(
            height: 42,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: widget.availableProviders.length,
              itemBuilder: (context, index) {
                final p = widget.availableProviders[index];
                final isSelected = p.id == _selectedId;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(p.label),
                    selected: isSelected,
                    showCheckmark: false,
                    selectedColor: const Color(0xFF2979FF),
                    backgroundColor: const Color(0xFF1E1E26),
                    side: BorderSide.none,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 13.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    onSelected: (_) {
                      if (_selectedId == p.id) return;
                      setState(() => _selectedId = p.id);
                      _fetchItems(p.id);
                    },
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              selectedProvider.label,
              style: AppText.headline.copyWith(
                color: const Color(0xFFEDE8E4),
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white38,
                    ),
                  )
                : _items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.cloud_off_rounded,
                              color: Colors.white38,
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No streams found on ${selectedProvider.label}',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: () => _fetchItems(_selectedId),
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Retry'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.25),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        physics: const BouncingScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 16 / 10,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final heroTag = 'tpdb:provider_screen:$index:${item.id}';
                          return _DiscoverWiderCard(
                            item: item,
                            heroTag: heroTag,
                            width: double.infinity,
                            height: double.infinity,
                            onTap: () => widget.onTapItem(item),
                            onLongPress: () =>
                                widget.onLongPressItem?.call(item, heroTag),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
