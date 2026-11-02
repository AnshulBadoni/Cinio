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
import '../../core/metadata/title_logo_service.dart';
import '../../core/metadata/tmdb_discover_service.dart';
import '../../core/models/media_item.dart';
import '../../core/models/person.dart';
import '../../core/models/provider_info.dart';
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
import '../people/see_all_actors_screen.dart';
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

  final void Function(MediaItem item, {String? heroTag}) onTapItem;
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
  final SourceRepository _repo = sl<SourceRepository>();

  late final AnimationController _gradientAnimCtrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat(reverse: true);

  StreamSubscription<SearchState>? _searchSub;

  Color _prominentColor = AppColors.accent;

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

  // Banner Carousel items (TMDB / Mixed / TPDB)
  List<MediaItem> _bannerItems = [];

  String _selectedCategory = 'All';

  static const List<String> _tmdbCategories = ['All', 'Movies', 'Series', 'Anime', 'Actors'];
  static const List<String> _tpdbCategories = ['All', 'Scenes', 'Movies', 'Performers'];

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good morning';
    } else if (hour < 17) {
      return 'Good afternoon';
    } else {
      return 'Good evening';
    }
  }

  List<MediaItem> get _editorsPicksItems {
    if (_isTpdb) {
      if (_trendingScenes.isNotEmpty) return _trendingScenes;
      if (_topRatedScenes.isNotEmpty) return _topRatedScenes;
      return _popularScenes;
    }
    if (_series.isNotEmpty) return _series;
    if (_anime.isNotEmpty) return _anime;
    return _movies.skip(3).toList();
  }

  // Provider section
  String _selectedProviderId = '';
  List<({String id, String label, String? repo})> _availableProviders = [];
  List<MediaItem> _providerItems = [];
  bool _loadingProvider = false;
  final Map<String, double> _aspectRatios = {};

  void _resolveImageAspect(String url, Map<String, String>? headers) {
    if (_aspectRatios.containsKey(url)) return;
    try {
      final ImageProvider imageProvider = headers != null && headers.isNotEmpty
          ? nativeCoverProvider(url, headers)
          : CachedNetworkImageProvider(url);
      imageProvider.resolve(const ImageConfiguration()).addListener(
        ImageStreamListener((info, _) {
          final w = info.image.width;
          final h = info.image.height;
          if (h > 0 && mounted) {
            final ratio = w / h;
            if (_aspectRatios[url] == null) {
              setState(() {
                _aspectRatios[url] = ratio;
              });
            }
          }
        }, onError: (_, __) {}),
      );
    } catch (_) {}
  }

  bool _isItemWide(MediaItem item) {
    if (item.heroImage != null && item.heroImage!.isNotEmpty) return true;
    if (_isTpdb) return true;
    final provId = _selectedProviderId.toLowerCase();
    if (provId.contains('tpdb') ||
        provId.contains('theporndb') ||
        provId.contains('jav') ||
        provId.contains('scene') ||
        provId.contains('tube') ||
        provId.contains('porn') ||
        provId.contains('adult')) {
      return true;
    }
    final src = item.sourceId.toLowerCase();
    if (src.contains('tpdb') ||
        src.contains('performer') ||
        src.contains('scene') ||
        src.contains('jav') ||
        src.contains('tube')) {
      return true;
    }
    final cover = (item.cover ?? '').toLowerCase();
    if (cover.contains('/w500/') ||
        cover.contains('/original/') ||
        cover.contains('backdrop') ||
        cover.contains('fanart') ||
        cover.contains('thumb') ||
        cover.contains('preview') ||
        cover.contains('screenshot') ||
        cover.contains('banner')) {
      return true;
    }
    final cached = _aspectRatios[item.cover];
    if (cached != null && cached >= 1.15) {
      return true;
    }
    return false;
  }

  static const List<Color> _curatedVibrantColors = [
    Color(0xFF8B5CF6), // Vibrant Purple
    Color(0xFFEF4444), // Crimson Red
    Color(0xFF10B981), // Emerald Green
    Color(0xFF3B82F6), // Royal Blue
    Color(0xFFF59E0B), // Vibrant Amber
    Color(0xFFEC4899), // Pink
  ];

  Color _sanitizeProminentColor(Color c, [int hash = 0]) {
    final hsl = HSLColor.fromColor(c);
    // Reject black / near-black (lightness < 0.22), white (lightness > 0.82), or gray/desaturated
    if (hsl.saturation < 0.28 || hsl.lightness < 0.22 || hsl.lightness > 0.82) {
      return _curatedVibrantColors[hash.abs() % _curatedVibrantColors.length];
    }
    return hsl
        .withSaturation((hsl.saturation * 1.3).clamp(0.55, 1.0))
        .withLightness(hsl.lightness.clamp(0.38, 0.56))
        .toColor();
  }

  @override
  void initState() {
    super.initState();
    _prominentColor = AppColors.accent;
    _prefs.addListener(_onPrefsChanged);
    _loadAvailableProviders();
    _loadAllCategories();

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
    if (_isTpdb) {
      final nsfw = categorizedSources().nsfw;
      final list = <({String id, String label, String? repo})>[
        if (_tpdb != null) (id: 'theporndb', label: 'ThePornDB Discovery', repo: null),
      ];
      for (final s in nsfw) {
        if (s.id != 'theporndb' && s.id != 'tpdb') {
          list.add(s);
        }
      }
      _availableProviders = list;
    } else {
      final buckets = categorizedSources();
      final list = <({String id, String label, String? repo})>[
        ...buckets.movies,
        ...buckets.anime,
      ];
      _availableProviders = list;
    }
    if (_selectedProviderId.isEmpty || !_availableProviders.any((p) => p.id == _selectedProviderId)) {
      _selectedProviderId = _availableProviders.isNotEmpty ? _availableProviders.first.id : '';
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
        maximumColorCount: 10,
      );

      final candidates = [
        pal.vibrantColor,
        pal.lightVibrantColor,
        pal.darkVibrantColor,
        ...pal.paletteColors,
      ].whereType<PaletteColor>().toList();

      candidates.sort((a, b) {
        final hslA = HSLColor.fromColor(a.color);
        final hslB = HSLColor.fromColor(b.color);
        final validA = hslA.lightness >= 0.22 && hslA.lightness <= 0.82 && hslA.saturation >= 0.28;
        final validB = hslB.lightness >= 0.22 && hslB.lightness <= 0.82 && hslB.saturation >= 0.28;
        if (validA && !validB) return -1;
        if (!validA && validB) return 1;
        return hslB.saturation.compareTo(hslA.saturation);
      });

      Color? chosen;
      for (final cand in candidates) {
        final hsl = HSLColor.fromColor(cand.color);
        if (hsl.saturation >= 0.28 && hsl.lightness >= 0.22 && hsl.lightness <= 0.82) {
          chosen = _sanitizeProminentColor(cand.color, coverUrl.hashCode);
          break;
        }
      }

      chosen ??= _curatedVibrantColors[coverUrl.hashCode.abs() % _curatedVibrantColors.length];
      if (mounted) {
        setState(() => _prominentColor = chosen!);
      }
    } catch (_) {}
  }

  void _loadAllCategories() {
    if (!mounted) return;
    _loadAvailableProviders();

    if (_isTpdb && _tpdb != null) {
      _loadTpdbContent();
    } else if (_isMixed) {
      _loadMixedContent();
    } else {
      _loadTmdbContent();
    }
    if (_selectedProviderId.isNotEmpty) {
      _fetchProviderItems(_selectedProviderId);
    }
  }

  Future<void> _fetchProviderItems(String providerId) async {
    if (!mounted || providerId.isEmpty) return;
    setState(() => _loadingProvider = true);
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
          _providerItems = items;
          _loadingProvider = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingProvider = false);
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
        if (sl.isRegistered<TitleLogoService>()) {
          sl<TitleLogoService>().prefetch(_bannerItems);
        }
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
        if (_bannerItems.isEmpty) {
          _bannerItems = items.take(6).toList();
          if (sl.isRegistered<TitleLogoService>()) {
            sl<TitleLogoService>().prefetch(_bannerItems);
          }
        }
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
        if (mixed.isNotEmpty) {
          _bannerItems = mixed.take(6).toList();
          if (sl.isRegistered<TitleLogoService>()) {
            sl<TitleLogoService>().prefetch(_bannerItems);
          }
        }
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
    final topPadding = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // Navbar height is 58.0; navbar bottom margin is (bottomInset > 0 ? bottomInset + 4 : 12.0)
    final dockBottom = (bottomInset > 0 ? bottomInset + 4 : 12.0) + 58.0 + 8.0;

    return Stack(
      children: [
        // Top right moving ambient radial glow matching mockup
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _gradientAnimCtrl,
              builder: (context, _) {
                final t = _gradientAnimCtrl.value;
                final center = Alignment(
                  0.80 + 0.12 * math.sin(t * math.pi),
                  -0.95 + 0.08 * math.cos(t * math.pi),
                );
                return Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: center,
                      radius: 1.35,
                      colors: [
                        AppColors.accent.withValues(alpha: 0.45),
                        AppColors.accent.withValues(alpha: 0.22),
                        AppColors.accent.withValues(alpha: 0.06),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.35, 0.65, 1.0],
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
            SliverToBoxAdapter(child: SizedBox(height: topPadding + 8)),
            SliverToBoxAdapter(child: _buildHeader()),
            if (_selectedCategory == 'All') ...[
              // 1. New Releases
              SliverToBoxAdapter(
                child: _buildSectionHeader(
                  title: 'New Releases',
                  onSeeAll: () => widget.onOpenSeeAll(
                    'New Releases',
                    _bannerItems.isNotEmpty ? _bannerItems : _movies,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _buildNewReleasesSection(),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 14)),

              // 2. From Providers
              SliverToBoxAdapter(
                child: _buildFromProvidersHeader(),
              ),
              SliverToBoxAdapter(
                child: _buildFromProvidersSection(),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 14)),

              // 3. Editor's Picks
              SliverToBoxAdapter(
                child: _buildSectionHeader(
                  title: "Editor's Picks",
                  onSeeAll: () => widget.onOpenSeeAll(
                    "Editor's Picks",
                    _editorsPicksItems,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _buildEditorsPicksSection(),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 14)),

              // 4. Trending Actors
              SliverToBoxAdapter(
                child: _buildSectionHeader(
                  title: _isTpdb ? 'Trending Performers' : 'Trending Actors',
                  onSeeAll: () => _openSeeAllActors(),
                ),
              ),
              SliverToBoxAdapter(
                child: _buildTrendingActorsSection(),
              ),
            ] else if (_selectedCategory == 'Movies') ...[
              SliverToBoxAdapter(
                child: _buildSectionHeader(
                  title: 'New Releases',
                  onSeeAll: () => widget.onOpenSeeAll(
                    'New Releases',
                    _bannerItems.isNotEmpty ? _bannerItems : _movies,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _buildNewReleasesSection(),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 14)),
              SliverToBoxAdapter(
                child: _buildSectionHeader(
                  title: 'Popular Movies',
                  onSeeAll: () => widget.onOpenSeeAll(
                    'Popular Movies',
                    _movies,
                    onLoadMore: _isMixed ? null : (p) => _tmdb.getTrendingMovies(page: p),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _buildMediaRow(_movies, 'discover:movies', onLoadMore: _loadMoreMovies),
              ),
            ] else if (_selectedCategory == 'Series') ...[
              SliverToBoxAdapter(
                child: _buildSectionHeader(
                  title: 'Popular Series',
                  onSeeAll: () => widget.onOpenSeeAll(
                    'Popular Series',
                    _series,
                    onLoadMore: (p) => _tmdb.getPopularSeries(page: p),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _buildEditorsPicksSection(),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 14)),
              SliverToBoxAdapter(
                child: _buildSectionHeader(
                  title: 'All Series',
                  onSeeAll: () => widget.onOpenSeeAll('All Series', _series),
                ),
              ),
              SliverToBoxAdapter(
                child: _buildMediaRow(_series, 'discover:series', onLoadMore: _loadMoreSeries),
              ),
            ] else if (_selectedCategory == 'Anime') ...[
              SliverToBoxAdapter(
                child: _buildSectionHeader(
                  title: 'Popular Anime',
                  onSeeAll: () => widget.onOpenSeeAll(
                    'Popular Anime',
                    _anime,
                    onLoadMore: (p) => _tmdb.getPopularAnime(page: p),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _buildMediaRow(_anime, 'discover:anime', onLoadMore: _loadMoreAnime),
              ),
            ] else if (_selectedCategory == 'Actors' || _selectedCategory == 'Performers') ...[
              SliverToBoxAdapter(
                child: _buildSectionHeader(
                  title: _isTpdb ? 'Trending Performers' : 'Trending Actors',
                  onSeeAll: () => _openSeeAllActors(),
                ),
              ),
              SliverToBoxAdapter(
                child: _buildTrendingActorsSection(),
              ),
            ] else if (_selectedCategory == 'Scenes') ...[
              SliverToBoxAdapter(
                child: _buildSectionHeader(
                  title: 'Trending Scenes',
                  onSeeAll: () => widget.onOpenSeeAll(
                    'Trending Scenes',
                    _trendingScenes,
                    onLoadMore: (p) => _tpdb?.trendingMovies(page: p) ?? Future.value([]),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _buildMediaRow(_trendingScenes, 'discover:tpdb:trending', onLoadMore: _loadMoreTrending),
              ),
            ],
            // Bottom padding so content scrolls clear of both floating search pill and navbar dock
            SliverToBoxAdapter(child: SizedBox(height: 160 + bottomInset)),
          ],
        ),

        // Bottom Floating Search Bar Pill + Filter Toggle (Fixed above navbar)
        Positioned(
          left: 16,
          right: 16,
          bottom: dockBottom,
          child: Row(
            children: [
              Expanded(child: _buildFloatingSearchBar()),
              const SizedBox(width: 12),
              _buildFloatingFilterButton(),
            ],
          ),
        ),
      ],
    );
  }
  Widget _buildHeader() {
    final categories = _isTpdb ? _tpdbCategories : _tmdbCategories;
    final accent = AppColors.accent;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Discover',
            style: AppText.display.copyWith(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _getGreeting(),
            style: AppText.body.copyWith(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 14.5,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 18),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: categories.map((cat) {
                final isSelected = cat == _selectedCategory;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedCategory = cat),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? accent : const Color(0xFF161214),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? accent : Colors.white.withValues(alpha: 0.12),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        cat,
                        style: TextStyle(
                          color: isSelected ? Colors.black : Colors.white.withValues(alpha: 0.85),
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required VoidCallback onSeeAll,
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppText.headline.copyWith(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
          if (action != null) ...[
            action,
            const SizedBox(width: 8),
          ],
          GestureDetector(
            onTap: onSeeAll,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.70),
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewReleasesSection() {
    final items = _bannerItems.isNotEmpty
        ? _bannerItems
        : (_movies.isNotEmpty ? _movies : _trendingScenes);

    if (items.isEmpty) {
      return const SizedBox(
        height: 220,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
        ),
      );
    }

    return SizedBox(
      height: 220,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          final heroTag = 'discover:new_releases:$index:${item.id}';
          return _DiscoverCinematicCard(
            item: item,
            heroTag: heroTag,
            width: 144,
            height: 220,
            onTap: () => widget.onTapItem(item, heroTag: heroTag),
            onLongPress: () => widget.onLongPressItem?.call(item, heroTag),
          );
        },
      ),
    );
  }

  Widget _buildFromProvidersHeader() {
    return _buildSectionHeader(
      title: 'From Providers',
      onSeeAll: () {
        if (_isTpdb) {
          _openTpdbProviderView(context);
        } else {
          widget.onOpenSeeAll('From Providers', _providerItems);
        }
      },
      action: GestureDetector(
        onTap: () => _openProviderSwitcher(),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            CupertinoIcons.square_stack_3d_up,
            color: Colors.white.withValues(alpha: 0.70),
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildFromProvidersSection() {
    final items = _providerItems.isNotEmpty
        ? _providerItems
        : (_trendingScenes.isNotEmpty ? _trendingScenes : _movies);

    if (items.isEmpty && _loadingProvider) {
      return const SizedBox(
        height: 175,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
        ),
      );
    }
    if (items.isEmpty) return const SizedBox.shrink();

    const rowHeight = 175.0;

    return SizedBox(
      height: rowHeight,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          final heroTag = 'discover:providers:$index:${item.id}';
          final isWide = (index % 3 == 0) || (item.heroImage != null && item.heroImage!.isNotEmpty);
          final cardWidth = isWide ? (rowHeight * 16 / 9).clamp(240.0, 290.0) : (rowHeight * 2 / 3).clamp(112.0, 118.0);

          return _DiscoverCinematicCard(
            item: item,
            heroTag: heroTag,
            width: cardWidth,
            height: rowHeight,
            preferHeroImage: isWide,
            onTap: () => widget.onTapItem(item, heroTag: heroTag),
            onLongPress: () => widget.onLongPressItem?.call(item, heroTag),
          );
        },
      ),
    );
  }

  Widget _buildEditorsPicksSection() {
    final items = _editorsPicksItems;

    if (items.isEmpty) {
      return const SizedBox(
        height: 140,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
        ),
      );
    }

    return SizedBox(
      height: 140,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          final heroTag = 'discover:editors_picks:$index:${item.id}';
          return _DiscoverCinematicCard(
            item: item,
            heroTag: heroTag,
            width: 248,
            height: 140,
            preferHeroImage: true,
            onTap: () => widget.onTapItem(item, heroTag: heroTag),
            onLongPress: () => widget.onLongPressItem?.call(item, heroTag),
          );
        },
      ),
    );
  }

  Widget _buildTrendingActorsSection() {
    final actors = _actors;

    if (actors.isEmpty) {
      return const SizedBox(
        height: 190,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
        ),
      );
    }

    return SizedBox(
      height: 190,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: actors.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final actor = actors[index];
          final heroTag = 'discover:actors:$index:${actor.id}';
          return _TrendingActorCard(
            actor: actor,
            heroTag: heroTag,
            width: 142,
            height: 190,
            onTap: () => widget.onTapPerson(actor),
            onLongPress: () => widget.onLongPressPerson?.call(actor, heroTag),
          );
        },
      ),
    );
  }

  Widget _buildMediaRow(
    List<MediaItem> items,
    String prefix, {
    VoidCallback? onLoadMore,
  }) {
    if (items.isEmpty) {
      return const SizedBox(
        height: 190,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
        ),
      );
    }

    return SizedBox(
      height: 200,
      child: NotificationListener<ScrollNotification>(
        onNotification: (scrollInfo) {
          if (onLoadMore != null &&
              scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200) {
            onLoadMore();
          }
          return false;
        },
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final item = items[index];
            final heroTag = '$prefix:$index:${item.id}';
            return _DiscoverCinematicCard(
              item: item,
              heroTag: heroTag,
              width: 132,
              height: 200,
              onTap: () => widget.onTapItem(item, heroTag: heroTag),
              onLongPress: () => widget.onLongPressItem?.call(item, heroTag),
            );
          },
        ),
      ),
    );
  }

  void _openSeeAllActors() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SeeAllActorsScreen(
          title: _isTpdb ? 'Trending Performers' : 'Trending Actors',
          initialActors: _actors,
          onLoadMore: _isTpdb ? null : (p) => _tmdb.getPopularPeople(page: p),
        ),
      ),
    );
  }

  void _openProviderSwitcher() {
    if (_isTpdb) {
      _openTpdbProviderView(context);
    } else {
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF161214),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text(
                      'Select Catalog Source',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Divider(color: Colors.white12),
                  ListTile(
                    leading: const Icon(Icons.movie_outlined, color: Colors.white70),
                    title: const Text('TMDB (Movies & Series)', style: TextStyle(color: Colors.white)),
                    trailing: !_isTpdb ? Icon(Icons.check_circle_rounded, color: AppColors.accent) : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      if (_isTpdb) {
                        _prefs.setSource(CatalogSource.tmdb);
                        setState(() {
                          _selectedCategory = 'All';
                        });
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.explicit_outlined, color: Colors.white70),
                    title: const Text('ThePornDB', style: TextStyle(color: Colors.white)),
                    trailing: _isTpdb ? Icon(Icons.check_circle_rounded, color: AppColors.accent) : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      if (!_isTpdb) {
                        _prefs.setSource(CatalogSource.thePornDb);
                        setState(() {
                          _selectedCategory = 'All';
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
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

  Widget _buildFloatingSearchBar() {
    return GestureDetector(
      onTap: widget.onTapSearch,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1A1D),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
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
              color: Colors.white.withValues(alpha: 0.60),
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Search movies, series, anime...',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingFilterButton() {
    return GestureDetector(
      onTap: widget.onOpenFilters,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.accent,
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.tune_rounded,
            color: Colors.black,
            size: 22,
          ),
        ),
      ),
    );
  }
}

/// Modern cinematic card with full image, subtle dark bottom gradient vignette,
/// and uppercase serif letter-spaced stylized title matching mockup design
class _DiscoverCinematicCard extends StatefulWidget {
  const _DiscoverCinematicCard({
    required this.item,
    required this.heroTag,
    required this.width,
    required this.height,
    required this.onTap,
    this.onLongPress,
    this.preferHeroImage = false,
  });

  final MediaItem item;
  final String heroTag;
  final double width;
  final double height;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool preferHeroImage;

  @override
  State<_DiscoverCinematicCard> createState() => _DiscoverCinematicCardState();
}

class _DiscoverCinematicCardState extends State<_DiscoverCinematicCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final imageUrl = widget.preferHeroImage
        ? (widget.item.heroImage ?? widget.item.cover)
        : (widget.item.cover ?? widget.item.heroImage);

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
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: const Color(0xFF161214),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl != null && imageUrl.isNotEmpty)
                  Hero(
                    tag: widget.heroTag,
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      httpHeaders: widget.item.coverHeaders,
                      fit: BoxFit.cover,
                      cacheManager: AppImageCache.cacheManagerOrDefault,
                      errorWidget: (_, __, ___) => Container(
                        color: const Color(0xFF1E1A1D),
                        child: const Icon(Icons.movie_outlined, color: Colors.white24, size: 32),
                      ),
                    ),
                  )
                else
                  Container(
                    color: const Color(0xFF1E1A1D),
                    child: const Icon(Icons.movie_outlined, color: Colors.white24, size: 32),
                  ),

                // Cinematic bottom gradient overlay
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Color(0x22000000),
                          Color(0xCC000000),
                          Color(0xF5000000),
                        ],
                        stops: [0.35, 0.55, 0.82, 1.0],
                      ),
                    ),
                  ),
                ),

                // Uppercase letter-spaced serif title in bottom center
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 12,
                  child: Text(
                    widget.item.title.toUpperCase(),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'serif',
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.0,
                      shadows: [
                        Shadow(
                          color: Color(0xDD000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
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

/// Actor portrait card with subtle bottom vignette and bold name
class _TrendingActorCard extends StatefulWidget {
  const _TrendingActorCard({
    required this.actor,
    required this.heroTag,
    required this.width,
    required this.height,
    required this.onTap,
    this.onLongPress,
  });

  final PersonRef actor;
  final String heroTag;
  final double width;
  final double height;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  State<_TrendingActorCard> createState() => _TrendingActorCardState();
}

class _TrendingActorCardState extends State<_TrendingActorCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final photo = widget.actor.photo;

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
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color(0xFF161214),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (photo != null && photo.isNotEmpty)
                  Hero(
                    tag: widget.heroTag,
                    child: CachedNetworkImage(
                      imageUrl: photo,
                      fit: BoxFit.cover,
                      cacheManager: AppImageCache.cacheManagerOrDefault,
                      errorWidget: (_, __, ___) => Container(
                        color: const Color(0xFF1E1A1D),
                        child: const Icon(Icons.person_rounded, color: Colors.white24, size: 36),
                      ),
                    ),
                  )
                else
                  Container(
                    color: const Color(0xFF1E1A1D),
                    child: const Icon(Icons.person_rounded, color: Colors.white24, size: 36),
                  ),

                // Subtle bottom gradient vignette
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Color(0x88000000),
                          Color(0xDD000000),
                        ],
                        stops: [0.60, 0.85, 1.0],
                      ),
                    ),
                  ),
                ),

                // Actor name
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Text(
                    widget.actor.name,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      shadows: [
                        Shadow(
                          color: Color(0xDD000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
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

/// Compatibility wrapper for _DiscoverWiderCard used in _TpdbProviderScreen
class _DiscoverWiderCard extends StatelessWidget {
  const _DiscoverWiderCard({
    required this.item,
    required this.heroTag,
    required this.width,
    required this.height,
    required this.onTap,
    this.onLongPress,
  });

  final MediaItem item;
  final String heroTag;
  final double width;
  final double height;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return _DiscoverCinematicCard(
      item: item,
      heroTag: heroTag,
      width: width,
      height: height,
      preferHeroImage: true,
      onTap: onTap,
      onLongPress: onLongPress,
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
