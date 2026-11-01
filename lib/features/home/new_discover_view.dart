import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../core/cache/app_image_cache.dart';
import '../../core/di/injector.dart';
import '../../core/metadata/theporndb.dart';
import '../../core/metadata/tmdb_discover_service.dart';
import '../../core/models/media_item.dart';
import '../../core/models/person.dart';
import '../../core/prefs/catalog_source_prefs.dart';
import '../../core/repository/source_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../people/favorite_actors_screen.dart';

/// Modern Discover Page matching the curated visual categories design.
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
    this.showBack = false,
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
  final bool showBack;

  @override
  State<NewDiscoverView> createState() => _NewDiscoverViewState();
}

class _NewDiscoverViewState extends State<NewDiscoverView> {
  final _tmdb = sl<TmdbDiscoverService>();
  final _prefs = sl<CatalogSourcePrefs>();
  ThePornDb? get _tpdb => sl.isRegistered<ThePornDb>() ? sl<ThePornDb>() : null;
  SourceRepository get _repo => sl<SourceRepository>();

  // Movies / Scenes
  List<MediaItem> _latestMovies = [];
  List<MediaItem> _trendingMovies = [];
  List<MediaItem> _topRatedMovies = [];

  // Series
  List<MediaItem> _popularSeries = [];
  List<MediaItem> _recentSeries = [];
  List<MediaItem> _topRatedSeries = [];

  // Anime
  List<MediaItem> _popularAnime = [];
  List<MediaItem> _recentAnime = [];
  List<MediaItem> _topRatedAnime = [];

  // Actors / Performers
  List<PersonRef> _actors = [];

  // Banner Carousel items
  List<MediaItem> _bannerItems = [];

  // Provider items (for TPDB mode)
  List<MediaItem> _providerItems = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onPrefsChanged);
    _loadAllCategories();
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefsChanged);
    super.dispose();
  }

  void _onPrefsChanged() {
    if (mounted) {
      _loadAllCategories();
    }
  }

  CatalogSource get _source => _prefs.source;
  bool get _isTpdb => _source == CatalogSource.thePornDb;
  bool get _isMixed => _source == CatalogSource.mixed;

  Future<void> _loadAllCategories() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      if (_isTpdb && _tpdb != null) {
        await _loadTpdbContent();
      } else if (_isMixed) {
        await _loadMixedContent();
      } else {
        await _loadTmdbContent();
      }
    } catch (_) {
      // Keep fallbacks
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadTmdbContent() async {
    final results = await Future.wait([
      _tmdb.getLatestMovies().catchError((_) => <MediaItem>[]),
      _tmdb.getTrendingMovies().catchError((_) => <MediaItem>[]),
      _tmdb.getTopRatedMovies().catchError((_) => <MediaItem>[]),
      _tmdb.getPopularSeries().catchError((_) => <MediaItem>[]),
      _tmdb.getRecentSeries().catchError((_) => <MediaItem>[]),
      _tmdb.getTopRatedSeries().catchError((_) => <MediaItem>[]),
      _tmdb.getPopularAnime().catchError((_) => <MediaItem>[]),
      _tmdb.getNewAnime().catchError((_) => <MediaItem>[]),
      _tmdb.getTopAnime().catchError((_) => <MediaItem>[]),
      _tmdb.getPopularPeople().catchError((_) => <PersonRef>[]),
    ]);

    _latestMovies = results[0] as List<MediaItem>;
    _trendingMovies = results[1] as List<MediaItem>;
    _topRatedMovies = results[2] as List<MediaItem>;

    _popularSeries = results[3] as List<MediaItem>;
    _recentSeries = results[4] as List<MediaItem>;
    _topRatedSeries = results[5] as List<MediaItem>;

    _popularAnime = results[6] as List<MediaItem>;
    _recentAnime = results[7] as List<MediaItem>;
    _topRatedAnime = results[8] as List<MediaItem>;

    _actors = results[9] as List<PersonRef>;

    // Banner: TMDB latest or trending
    final bannerSource = _latestMovies.isNotEmpty ? _latestMovies : _trendingMovies;
    _bannerItems = bannerSource.take(6).toList();
  }

  Future<void> _loadTpdbContent() async {
    final tpdb = _tpdb!;
    final futures = <Future<dynamic>>[
      tpdb.popularMovies().catchError((_) => <MediaItem>[]),
      tpdb.trendingMovies().catchError((_) => <MediaItem>[]),
      tpdb.topRatedMovies().catchError((_) => <MediaItem>[]),
      tpdb.performers().catchError((_) => <MediaItem>[]),
      _loadProviderHomeItems().catchError((_) => <MediaItem>[]),
    ];

    final results = await Future.wait(futures);

    _popularSeries = [];
    _recentSeries = [];
    _topRatedSeries = [];
    _popularAnime = [];
    _recentAnime = [];
    _topRatedAnime = [];

    _topRatedMovies = results[0] as List<MediaItem>; // Popular
    _trendingMovies = results[1] as List<MediaItem>; // Trending
    _latestMovies = results[2] as List<MediaItem>; // Top Rated

    final performers = results[3] as List<MediaItem>;
    _actors = performers
        .map((p) => PersonRef(
              id: 0,
              externalId: p.id.replaceFirst('tpdb:performer:', ''),
              source: PersonSource.thePornDbPerformer,
              name: p.title,
              photo: p.cover,
            ))
        .toList();

    _providerItems = results[4] as List<MediaItem>;
    _bannerItems = _providerItems.isNotEmpty
        ? _providerItems.take(6).toList()
        : _trendingMovies.take(6).toList();
  }

  Future<void> _loadMixedContent() async {
    final tpdb = _tpdb;
    final results = await Future.wait([
      _tmdb.getLatestMovies().catchError((_) => <MediaItem>[]),
      _tmdb.getTrendingMovies().catchError((_) => <MediaItem>[]),
      _tmdb.getTopRatedMovies().catchError((_) => <MediaItem>[]),
      _tmdb.getPopularSeries().catchError((_) => <MediaItem>[]),
      _tmdb.getRecentSeries().catchError((_) => <MediaItem>[]),
      _tmdb.getTopRatedSeries().catchError((_) => <MediaItem>[]),
      _tmdb.getPopularAnime().catchError((_) => <MediaItem>[]),
      _tmdb.getNewAnime().catchError((_) => <MediaItem>[]),
      _tmdb.getTopAnime().catchError((_) => <MediaItem>[]),
      _tmdb.getPopularPeople().catchError((_) => <PersonRef>[]),
      if (tpdb != null) ...[
        tpdb.movies(orderBy: 'recently_created').catchError((_) => <MediaItem>[]),
        tpdb.trendingMovies().catchError((_) => <MediaItem>[]),
        tpdb.topRatedMovies().catchError((_) => <MediaItem>[]),
        tpdb.performers().catchError((_) => <MediaItem>[]),
      ] else ...[
        Future.value(<MediaItem>[]),
        Future.value(<MediaItem>[]),
        Future.value(<MediaItem>[]),
        Future.value(<MediaItem>[]),
      ],
    ]);

    final tmdbLatest = results[0] as List<MediaItem>;
    final tmdbTrending = results[1] as List<MediaItem>;
    final tmdbTopRated = results[2] as List<MediaItem>;

    _popularSeries = results[3] as List<MediaItem>;
    _recentSeries = results[4] as List<MediaItem>;
    _topRatedSeries = results[5] as List<MediaItem>;

    _popularAnime = results[6] as List<MediaItem>;
    _recentAnime = results[7] as List<MediaItem>;
    _topRatedAnime = results[8] as List<MediaItem>;

    final tmdbActors = results[9] as List<PersonRef>;

    final tpdbRecent = results[10] as List<MediaItem>;
    final tpdbTrending = results[11] as List<MediaItem>;
    final tpdbTopRated = results[12] as List<MediaItem>;
    final tpdbPerformers = results[13] as List<MediaItem>;

    // Interleave movies
    _latestMovies = _interleaveItems(tmdbLatest, tpdbRecent);
    _trendingMovies = _interleaveItems(tmdbTrending, tpdbTrending);
    _topRatedMovies = _interleaveItems(tmdbTopRated, tpdbTopRated);

    // Interleave actors
    final tpdbActors = tpdbPerformers
        .map((p) => PersonRef(
              id: 0,
              externalId: p.id.replaceFirst('tpdb:performer:', ''),
              source: PersonSource.thePornDbPerformer,
              name: p.title,
              photo: p.cover,
            ))
        .toList();
    _actors = _interleavePeople(tmdbActors, tpdbActors);

    final bannerSource = _latestMovies.isNotEmpty ? _latestMovies : _trendingMovies;
    _bannerItems = bannerSource.take(6).toList();
  }

  Future<List<MediaItem>> _loadProviderHomeItems() async {
    try {
      final sections = await _repo.home();
      final out = <MediaItem>[];
      for (final sec in sections) {
        out.addAll(sec.items);
        if (out.length >= 10) break;
      }
      return out;
    } catch (_) {
      return <MediaItem>[];
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
    return Stack(
      children: [
        CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildTopBar()),
            if (_isTpdb) ...[
              // TPDB mode: Popular, Trending, Top Rated, Performers, Provider banner
              SliverToBoxAdapter(
                child: _buildCategorySection(
                  title: 'Popular',
                  subtitle: 'Most watched videos',
                  items: _topRatedMovies,
                  categoryName: 'Popular',
                  onSeeAll: () => widget.onOpenSeeAll('Popular', _topRatedMovies,
                      onLoadMore: (p) => _tpdb?.popularMovies(page: p) ?? Future.value([])),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 22)),
              SliverToBoxAdapter(
                child: _buildCategorySection(
                  title: 'Trending',
                  subtitle: 'Hot this week',
                  items: _trendingMovies,
                  categoryName: 'Trending Now',
                  onSeeAll: () => widget.onOpenSeeAll('Trending Now', _trendingMovies,
                      onLoadMore: (p) => _tpdb?.trendingMovies(page: p) ?? Future.value([])),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 22)),
              SliverToBoxAdapter(
                child: _buildCategorySection(
                  title: 'Top Rated',
                  subtitle: 'Highest rated scenes',
                  items: _latestMovies,
                  categoryName: 'Top Rated',
                  onSeeAll: () => widget.onOpenSeeAll('Top Rated', _latestMovies,
                      onLoadMore: (p) => _tpdb?.topRatedMovies(page: p) ?? Future.value([])),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 22)),
              SliverToBoxAdapter(
                child: _buildActorsSection(
                  title: 'Actors',
                  onSeeAll: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const FavoriteActorsScreen(),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(
                child: _buildBannerSection(
                  title: 'Provider',
                  items: _bannerItems,
                  onSeeAll: () => widget.onOpenSeeAll('Provider', _bannerItems),
                ),
              ),
            ] else ...[
              // TMDB & Mixed Mode
              SliverToBoxAdapter(
                child: _buildThreeCardsRow(
                  title: 'Movies',
                  cards: [
                    _CardInfo(
                      title: 'Latest Releases',
                      subtitle: '${_latestMovies.length > 20 ? 36 : _latestMovies.length} new movies',
                      items: _latestMovies,
                      onLoadMore: _isMixed ? null : (p) => _tmdb.getLatestMovies(page: p),
                    ),
                    _CardInfo(
                      title: 'Trending Now',
                      subtitle: 'Popular this week',
                      items: _trendingMovies,
                      onLoadMore: _isMixed ? null : (p) => _tmdb.getTrendingMovies(page: p),
                    ),
                    _CardInfo(
                      title: 'Top Rated',
                      subtitle: 'Critically acclaimed',
                      items: _topRatedMovies,
                      onLoadMore: _isMixed ? null : (p) => _tmdb.getTopRatedMovies(page: p),
                    ),
                  ],
                  onSeeAll: () => widget.onOpenSeeAll('Movies', _trendingMovies),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 22)),
              SliverToBoxAdapter(
                child: _buildThreeCardsRow(
                  title: 'Series',
                  cards: [
                    _CardInfo(
                      title: 'Popular Series',
                      subtitle: 'Binge-worthy picks',
                      items: _popularSeries,
                      onLoadMore: (p) => _tmdb.getPopularSeries(page: p),
                    ),
                    _CardInfo(
                      title: 'New Episodes',
                      subtitle: 'Recently added',
                      items: _recentSeries,
                      onLoadMore: (p) => _tmdb.getRecentSeries(page: p),
                    ),
                    _CardInfo(
                      title: 'Top Series',
                      subtitle: 'Fan favourites',
                      items: _topRatedSeries,
                      onLoadMore: (p) => _tmdb.getTopRatedSeries(page: p),
                    ),
                  ],
                  onSeeAll: () => widget.onOpenSeeAll('Series', _popularSeries),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 22)),
              SliverToBoxAdapter(
                child: _buildThreeCardsRow(
                  title: 'Anime',
                  cards: [
                    _CardInfo(
                      title: 'Popular Anime',
                      subtitle: 'Most watched',
                      items: _popularAnime,
                      onLoadMore: (p) => _tmdb.getPopularAnime(page: p),
                    ),
                    _CardInfo(
                      title: 'New Seasons',
                      subtitle: 'Latest anime series',
                      items: _recentAnime,
                      onLoadMore: (p) => _tmdb.getNewAnime(page: p),
                    ),
                    _CardInfo(
                      title: 'Top Anime',
                      subtitle: 'All-time favourites',
                      items: _topRatedAnime,
                      onLoadMore: (p) => _tmdb.getTopAnime(page: p),
                    ),
                  ],
                  onSeeAll: () => widget.onOpenSeeAll('Anime', _popularAnime),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 22)),
              SliverToBoxAdapter(
                child: _buildActorsSection(
                  title: 'Actors',
                  onSeeAll: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const FavoriteActorsScreen(),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(
                child: _buildBannerSection(
                  title: 'New Releases',
                  items: _bannerItems,
                  onSeeAll: () => widget.onOpenSeeAll('New Releases', _bannerItems),
                ),
              ),
            ],
            // Padding at the bottom for floating search pill
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),

        // Bottom Floating Search Bar Pill
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: SafeArea(
            top: false,
            child: _buildFloatingSearchBar(),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
      child: Row(
        children: [
          if (widget.showBack || widget.onBack != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: widget.onBack,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ),
          Text(
            'Discover',
            style: AppText.headline.copyWith(
              fontSize: 27,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: widget.onOpenFilters,
            icon: const Icon(
              Icons.tune_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  /// Section Header with the round button and > chevron icon from home screen
  Widget _buildSectionHeader({
    required String title,
    required VoidCallback onSeeAll,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: AppText.headline.copyWith(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          _GlassChevronButton(onTap: onSeeAll),
        ],
      ),
    );
  }

  Widget _buildThreeCardsRow({
    required String title,
    required List<_CardInfo> cards,
    required VoidCallback onSeeAll,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(title: title, onSeeAll: onSeeAll),
        const SizedBox(height: 10),
        SizedBox(
          height: 215,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final card = cards[index];
              final firstItem = card.items.isNotEmpty ? card.items.first : null;
              final heroTag = 'discover:${title.toLowerCase()}:$index:${card.title}';
              return SizedBox(
                width: 145,
                child: _CategoryCard(
                  title: card.title,
                  subtitle: card.subtitle,
                  item: firstItem,
                  heroTag: heroTag,
                  onTap: () {
                    if (card.items.isNotEmpty) {
                      widget.onOpenSeeAll(
                        card.title,
                        card.items,
                        onLoadMore: card.onLoadMore,
                      );
                    }
                  },
                  onLongPress: firstItem != null
                      ? () => widget.onLongPressItem?.call(firstItem, heroTag)
                      : null,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCategorySection({
    required String title,
    required String subtitle,
    required List<MediaItem> items,
    required String categoryName,
    required VoidCallback onSeeAll,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(title: title, onSeeAll: onSeeAll),
        const SizedBox(height: 10),
        SizedBox(
          height: 215,
          child: items.isEmpty
              ? _buildSkeletonRow()
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: items.length.clamp(0, 15),
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final heroTag = 'discover:cat:$title:$index:${item.id}';
                    return SizedBox(
                      width: 145,
                      child: _CategoryCard(
                        title: item.title,
                        subtitle: item.year ?? '',
                        item: item,
                        heroTag: heroTag,
                        onTap: () => widget.onTapItem(item),
                        onLongPress: () =>
                            widget.onLongPressItem?.call(item, heroTag),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildActorsSection({
    required String title,
    required VoidCallback onSeeAll,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(title: title, onSeeAll: onSeeAll),
        const SizedBox(height: 12),
        SizedBox(
          height: 124,
          child: _actors.isEmpty
              ? _buildActorsSkeleton()
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _actors.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final actor = _actors[index];
                    final heroTag = 'discover:actor:$index:${actor.id}:${actor.name}';
                    return SizedBox(
                      width: 88,
                      child: GestureDetector(
                        onTap: () => widget.onTapPerson(actor),
                        onLongPress: () =>
                            widget.onLongPressPerson?.call(actor, heroTag),
                        behavior: HitTestBehavior.opaque,
                        child: Column(
                          children: [
                            Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  width: 1.2,
                                ),
                              ),
                              child: ClipOval(
                                child: actor.photo != null && actor.photo!.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: actor.photo!,
                                        fit: BoxFit.cover,
                                        cacheManager: AppImageCache.cacheManagerOrDefault,
                                        errorWidget: (_, _, _) => Container(
                                          color: AppColors.surface2,
                                          child: const Icon(
                                            Icons.person_rounded,
                                            color: AppColors.textTertiary,
                                            size: 34,
                                          ),
                                        ),
                                      )
                                    : Container(
                                        color: AppColors.surface2,
                                        child: const Icon(
                                          Icons.person_rounded,
                                          color: AppColors.textTertiary,
                                          size: 34,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              actor.name,
                              style: AppText.caption.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
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
        _buildSectionHeader(title: title, onSeeAll: onSeeAll),
        const SizedBox(height: 10),
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

  Widget _buildFloatingSearchBar() {
    return GestureDetector(
      onTap: widget.onTapSearch,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: const Color(0xFF16161B),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(
              Icons.search_rounded,
              color: Colors.white70,
              size: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Search movies, series, actors...',
                style: AppText.body.copyWith(
                  color: Colors.white60,
                  fontSize: 14,
                ),
              ),
            ),
            const Icon(
              Icons.mic_none_rounded,
              color: Colors.white70,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonRow() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      scrollDirection: Axis.horizontal,
      itemCount: 4,
      separatorBuilder: (_, _) => const SizedBox(width: 12),
      itemBuilder: (_, _) => Container(
        width: 145,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildActorsSkeleton() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      scrollDirection: Axis.horizontal,
      itemCount: 5,
      separatorBuilder: (_, _) => const SizedBox(width: 14),
      itemBuilder: (_, _) => Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surface2,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 60,
            height: 12,
            color: AppColors.surface2,
          ),
        ],
      ),
    );
  }
}

class _CardInfo {
  _CardInfo({
    required this.title,
    required this.subtitle,
    required this.items,
    this.onLoadMore,
  });

  final String title;
  final String subtitle;
  final List<MediaItem> items;
  final Future<List<MediaItem>> Function(int)? onLoadMore;
}

/// Category Card displaying title, subtitle, and dynamic poster background
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.title,
    required this.subtitle,
    required this.item,
    required this.heroTag,
    required this.onTap,
    this.onLongPress,
  });

  final String title;
  final String subtitle;
  final MediaItem? item;
  final String heroTag;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final imageUrl = item?.cover;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF18181E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 0.8,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Poster Image
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
                Container(
                  color: const Color(0xFF1E1E26),
                ),

              // Gradient Overlay
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.05),
                        Colors.black.withValues(alpha: 0.35),
                        Colors.black.withValues(alpha: 0.88),
                      ],
                      stops: const [0.35, 0.65, 1.0],
                    ),
                  ),
                ),
              ),

              // Bottom Title & Subtitle
              Positioned(
                left: 10,
                right: 10,
                bottom: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppText.headline.copyWith(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        shadows: const [
                          Shadow(
                            color: Colors.black,
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: AppText.caption.copyWith(
                        fontSize: 11,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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

/// Auto-advancing Banner Carousel with animated pagination dots
class _NewReleasesCarousel extends StatefulWidget {
  const _NewReleasesCarousel({
    required this.items,
    required this.onTap,
    this.onLongPress,
  });

  final List<MediaItem> items;
  final void Function(MediaItem) onTap;
  final void Function(MediaItem, String heroTag)? onLongPress;

  @override
  State<_NewReleasesCarousel> createState() => _NewReleasesCarouselState();
}

class _NewReleasesCarouselState extends State<_NewReleasesCarousel> {
  late final PageController _pageController;
  Timer? _timer;
  int _currentPage = 0;

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
    if (oldWidget.items.length != widget.items.length) {
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
    if (widget.items.isEmpty) {
      return Container(
        height: 150,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(16),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 154,
        decoration: BoxDecoration(
          color: const Color(0xFF16161D),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 0.8,
          ),
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
                final imageUrl = item.cover;
                final heroTag = 'discover:banner:$index:${item.id}';

                return GestureDetector(
                  onTap: () => widget.onTap(item),
                  onLongPress: () => widget.onLongPress?.call(item, heroTag),
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

                      // Gradient Overlay
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.4),
                                Colors.black.withValues(alpha: 0.85),
                              ],
                              stops: const [0.3, 0.65, 1.0],
                            ),
                          ),
                        ),
                      ),

                      // Title
                      Positioned(
                        left: 16,
                        bottom: 14,
                        right: 80,
                        child: Text(
                          item.title,
                          style: AppText.headline.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: Colors.white,
                            shadows: const [
                              Shadow(
                                color: Colors.black,
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // Animated Pagination Dots at bottom-right
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
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0x6618181E),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
                width: 0.65,
              ),
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
