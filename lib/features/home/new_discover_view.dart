import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/cache/app_image_cache.dart';
import '../../core/di/injector.dart';
import '../../core/metadata/theporndb.dart';
import '../../core/metadata/tmdb_discover_service.dart';
import '../../core/models/media_item.dart';
import '../../core/models/person.dart';
import '../../core/prefs/catalog_source_prefs.dart';
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
  final bool showBack;

  @override
  State<NewDiscoverView> createState() => _NewDiscoverViewState();
}

class _NewDiscoverViewState extends State<NewDiscoverView> {
  final _tmdb = sl<TmdbDiscoverService>();
  final _prefs = sl<CatalogSourcePrefs>();
  ThePornDb? get _tpdb => sl.isRegistered<ThePornDb>() ? sl<ThePornDb>() : null;

  // Movies
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

  // Actors
  List<PersonRef> _actors = [];

  // Banner
  MediaItem? _bannerMovie;

  @override
  void initState() {
    super.initState();
    _loadAllCategories();
  }

  bool get _isTpdb => _prefs.source == CatalogSource.thePornDb;

  Future<void> _loadAllCategories() async {
    try {
      if (_isTpdb && _tpdb != null) {
        await _loadTpdbContent();
      } else {
        await _loadTmdbContent();
      }
    } catch (_) {
      // Keep fallbacks
    } finally {
      if (mounted) {
        setState(() {});
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

    if (_latestMovies.isNotEmpty) {
      _bannerMovie = _latestMovies.first;
    } else if (_trendingMovies.isNotEmpty) {
      _bannerMovie = _trendingMovies.first;
    }
  }

  Future<void> _loadTpdbContent() async {
    final tpdb = _tpdb!;
    final results = await Future.wait([
      tpdb.movies(orderBy: 'recently_created').catchError((_) => <MediaItem>[]),
      tpdb.trendingMovies().catchError((_) => <MediaItem>[]),
      tpdb.popularMovies().catchError((_) => <MediaItem>[]),
      tpdb.performers().catchError((_) => <MediaItem>[]),
    ]);

    _latestMovies = results[0];
    _trendingMovies = results[1];
    _topRatedMovies = results[2];

    _popularSeries = _trendingMovies;
    _recentSeries = _latestMovies;
    _topRatedSeries = _topRatedMovies;

    final performers = results[3];
    _actors = performers
        .map((p) => PersonRef(
              id: 0,
              externalId: p.id.replaceFirst('tpdb:performer:', ''),
              source: PersonSource.thePornDbPerformer,
              name: p.title,
              photo: p.cover,
            ))
        .toList();

    if (_latestMovies.isNotEmpty) {
      _bannerMovie = _latestMovies.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Scrollable content
        Positioned.fill(
          child: RefreshIndicator(
            onRefresh: _loadAllCategories,
            color: AppColors.accent,
            backgroundColor: AppColors.surface,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Title Bar
                  _buildHeader(),
                  const SizedBox(height: 18),

                  // 1. Movies Section
                  _buildSectionHeader(
                    title: 'Movies',
                    showViewAll: false,
                  ),
                  const SizedBox(height: 12),
                  _buildThreeCardRow(
                    card1Title: 'Latest Releases',
                    card1Subtitle: '${_latestMovies.length > 20 ? 36 : _latestMovies.length} new movies',
                    card1Item: _latestMovies.isNotEmpty ? _latestMovies.first : null,
                    card1Tap: () => widget.onOpenSeeAll(
                      'Latest Releases',
                      _latestMovies,
                      onLoadMore: (p) => _isTpdb
                          ? _tpdb!.movies(page: p, orderBy: 'recently_created')
                          : _tmdb.getLatestMovies(page: p),
                    ),
                    card2Title: 'Trending Now',
                    card2Subtitle: 'Popular this week',
                    card2Item: _trendingMovies.isNotEmpty ? _trendingMovies.first : null,
                    card2Tap: () => widget.onOpenSeeAll(
                      'Trending Now',
                      _trendingMovies,
                      onLoadMore: (p) => _isTpdb
                          ? _tpdb!.trendingMovies(page: p)
                          : _tmdb.getTrendingMovies(page: p),
                    ),
                    card3Title: 'Top Rated',
                    card3Subtitle: 'Critically acclaimed',
                    card3Item: _topRatedMovies.isNotEmpty ? _topRatedMovies.first : null,
                    card3Tap: () => widget.onOpenSeeAll(
                      'Top Rated',
                      _topRatedMovies,
                      onLoadMore: (p) => _isTpdb
                          ? _tpdb!.popularMovies(page: p)
                          : _tmdb.getTopRatedMovies(page: p),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 2. Series Section
                  _buildSectionHeader(
                    title: 'Series',
                    showViewAll: true,
                    onViewAll: () => widget.onOpenSeeAll(
                      'Series',
                      _popularSeries,
                      onLoadMore: (p) => _tmdb.getPopularSeries(page: p),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildThreeCardRow(
                    card1Title: 'Popular Series',
                    card1Subtitle: 'Binge-worthy picks',
                    card1Item: _popularSeries.isNotEmpty ? _popularSeries.first : null,
                    card1Tap: () => widget.onOpenSeeAll(
                      'Popular Series',
                      _popularSeries,
                      onLoadMore: (p) => _tmdb.getPopularSeries(page: p),
                    ),
                    card2Title: 'New Episodes',
                    card2Subtitle: 'Recently added',
                    card2Item: _recentSeries.isNotEmpty
                        ? (_recentSeries.length > 1 ? _recentSeries[1] : _recentSeries.first)
                        : null,
                    card2Tap: () => widget.onOpenSeeAll(
                      'New Episodes',
                      _recentSeries,
                      onLoadMore: (p) => _tmdb.getRecentSeries(page: p),
                    ),
                    card3Title: 'Top Series',
                    card3Subtitle: 'Fan favourites',
                    card3Item: _topRatedSeries.isNotEmpty ? _topRatedSeries.first : null,
                    card3Tap: () => widget.onOpenSeeAll(
                      'Top Series',
                      _topRatedSeries,
                      onLoadMore: (p) => _tmdb.getTopRatedSeries(page: p),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 3. Anime Section
                  _buildSectionHeader(
                    title: 'Anime',
                    showViewAll: true,
                    onViewAll: () => widget.onOpenSeeAll(
                      'Anime',
                      _popularAnime,
                      onLoadMore: (p) => _tmdb.getPopularAnime(page: p),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildThreeCardRow(
                    card1Title: 'Popular Anime',
                    card1Subtitle: 'Most watched',
                    card1Item: _popularAnime.isNotEmpty ? _popularAnime.first : null,
                    card1Tap: () => widget.onOpenSeeAll(
                      'Popular Anime',
                      _popularAnime,
                      onLoadMore: (p) => _tmdb.getPopularAnime(page: p),
                    ),
                    card2Title: 'New Seasons',
                    card2Subtitle: 'Latest anime series',
                    card2Item: _recentAnime.isNotEmpty ? _recentAnime.first : null,
                    card2Tap: () => widget.onOpenSeeAll(
                      'New Seasons',
                      _recentAnime,
                      onLoadMore: (p) => _tmdb.getNewAnime(page: p),
                    ),
                    card3Title: 'Top Anime',
                    card3Subtitle: 'All-time favourites',
                    card3Item: _topRatedAnime.isNotEmpty ? _topRatedAnime.first : null,
                    card3Tap: () => widget.onOpenSeeAll(
                      'Top Anime',
                      _topRatedAnime,
                      onLoadMore: (p) => _tmdb.getTopAnime(page: p),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 4. Actors Section
                  _buildSectionHeader(
                    title: 'Actors',
                    showViewAll: true,
                    onViewAll: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FavoriteActorsScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  _buildActorsRow(),
                  const SizedBox(height: 24),

                  // 5. New Releases Banner
                  _buildSectionHeader(
                    title: 'New Releases',
                    showViewAll: true,
                    onViewAll: () => widget.onOpenSeeAll(
                      'New Releases',
                      _latestMovies,
                      onLoadMore: (p) => _tmdb.getLatestMovies(page: p),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildNewReleasesBanner(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),

        // 6. Floating Search Bar at Bottom
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: _buildBottomSearchBar(),
        ),
      ],
    );
  }

  // ── Header (Title + Filters) ─────────────────────────────────────────────
  Widget _buildHeader() {
    return Row(
      children: [
        if (widget.showBack) ...[
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            'Discover',
            style: AppText.display.copyWith(
              fontSize: 29,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: widget.onOpenFilters,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.tune_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }

  // ── Section Header ────────────────────────────────────────────────────────
  Widget _buildSectionHeader({
    required String title,
    required bool showViewAll,
    VoidCallback? onViewAll,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: -0.2,
          ),
        ),
        if (showViewAll)
          InkWell(
            onTap: onViewAll,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                'View all',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── 3-Card Category Row ───────────────────────────────────────────────────
  Widget _buildThreeCardRow({
    required String card1Title,
    required String card1Subtitle,
    required MediaItem? card1Item,
    required VoidCallback card1Tap,
    required String card2Title,
    required String card2Subtitle,
    required MediaItem? card2Item,
    required VoidCallback card2Tap,
    required String card3Title,
    required String card3Subtitle,
    required MediaItem? card3Item,
    required VoidCallback card3Tap,
  }) {
    return Row(
      children: [
        Expanded(
          child: _buildCategoryCard(
            title: card1Title,
            subtitle: card1Subtitle,
            item: card1Item,
            onTap: card1Tap,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildCategoryCard(
            title: card2Title,
            subtitle: card2Subtitle,
            item: card2Item,
            onTap: card2Tap,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildCategoryCard(
            title: card3Title,
            subtitle: card3Subtitle,
            item: card3Item,
            onTap: card3Tap,
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryCard({
    required String title,
    required String subtitle,
    required MediaItem? item,
    required VoidCallback onTap,
  }) {
    final posterUrl = item?.cover;

    return AspectRatio(
      aspectRatio: 0.72,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: AppColors.surface,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Background Poster
                if (posterUrl != null && posterUrl.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: posterUrl,
                    cacheManager: AppImageCache.manager,
                    httpHeaders: item?.coverHeaders,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(color: AppColors.surface2),
                    errorWidget: (_, _, _) => Container(color: AppColors.surface2),
                  )
                else
                  Container(color: AppColors.surface2),

                // Smooth dark gradient overlay
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.15),
                        Colors.black.withValues(alpha: 0.78),
                        Colors.black.withValues(alpha: 0.96),
                      ],
                      stops: const [0.35, 0.58, 0.82, 1.0],
                    ),
                  ),
                ),

                // Bottom Labels
                Positioned(
                  left: 9,
                  right: 9,
                  bottom: 10,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.8,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w400,
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
    );
  }

  // ── Actors Circular Avatar Row ───────────────────────────────────────────
  Widget _buildActorsRow() {
    if (_actors.isEmpty) {
      return const SizedBox(height: 90);
    }

    return SizedBox(
      height: 105,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _actors.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final actor = _actors[index];
          return InkWell(
            borderRadius: BorderRadius.circular(36),
            onTap: () => widget.onTapPerson(actor),
            child: SizedBox(
              width: 72,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 1.2,
                      ),
                    ),
                    child: ClipOval(
                      child: actor.photo != null && actor.photo!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: actor.photo!,
                              cacheManager: AppImageCache.manager,
                              fit: BoxFit.cover,
                              placeholder: (_, _) => Container(color: AppColors.surface2),
                              errorWidget: (_, _, _) => Container(
                                color: AppColors.surface2,
                                child: const Icon(Icons.person, color: Colors.white54),
                              ),
                            )
                          : Container(
                              color: AppColors.surface2,
                              child: const Icon(Icons.person, color: Colors.white54),
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    actor.name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── New Releases Cinematic Banner ────────────────────────────────────────
  Widget _buildNewReleasesBanner() {
    final banner = _bannerMovie;
    final coverUrl = banner?.cover;

    return AspectRatio(
      aspectRatio: 2.35,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: AppColors.surface,
          child: InkWell(
            onTap: () {
              if (banner != null) widget.onTapItem(banner);
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (coverUrl != null && coverUrl.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: coverUrl,
                    cacheManager: AppImageCache.manager,
                    httpHeaders: banner?.coverHeaders,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(color: AppColors.surface2),
                    errorWidget: (_, _, _) => Container(color: AppColors.surface2),
                  )
                else
                  Container(color: AppColors.surface2),

                // Cinematic Gradient Overlay
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.3),
                        Colors.black.withValues(alpha: 0.88),
                      ],
                      stops: const [0.35, 0.65, 1.0],
                    ),
                  ),
                ),

                // Title + Dots
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 14,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          banner?.title ?? 'Avatar: The Way of Water',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.35),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.35),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Floating Bottom Search Bar ───────────────────────────────────────────
  Widget _buildBottomSearchBar() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTapSearch,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF16161A),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                color: Colors.white.withValues(alpha: 0.75),
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Search movies, series, actors...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ),
              Icon(
                Icons.mic_none_rounded,
                color: Colors.white.withValues(alpha: 0.75),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
