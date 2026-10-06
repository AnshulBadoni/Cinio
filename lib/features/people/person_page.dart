import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/metadata/favorite_people_store.dart';
import '../../core/metadata/people_service.dart';
import '../../core/metadata/theporndb.dart';
import '../../core/models/media_item.dart';
import '../../core/models/person.dart';
import '../../core/models/provider_info.dart';
import '../../core/models/watch_status.dart';
import '../../core/playback/list_status_store.dart';
import '../../core/playback/my_list.dart';
import '../../core/repository/source_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/trailer/trailer_service.dart';
import '../../core/ui/native_cover_provider.dart';
import '../../core/ui/poster_quick_actions.dart';
import '../../core/ui/states.dart';
import '../detail/detail_screen.dart';
import '../home/see_all_screen.dart';
import '../trailer/trailer_screen.dart';
import 'provider_videos_screen.dart';

/// Redesigned Actor Profile Page with cinematic hero header,
/// quick action trio (Shuffle / Trailer / Favorite), and organized
/// carousels (Popular, Latest, Movies, Series, Provider Videos, Related, Bio).
class PersonPage extends StatefulWidget {
  const PersonPage({
    super.key,
    required this.person,
    this.sourceId,
    this.heroTag,
  });

  final PersonRef person;

  /// The source to search when a title on this page is tapped. Null → active.
  final String? sourceId;

  /// Hero animation tag for the actor's profile photo.
  final String? heroTag;

  static Route<void> route(
    PersonRef person, {
    String? sourceId,
    String? heroTag,
  }) =>
      MaterialPageRoute<void>(
        builder: (_) => PersonPage(
          person: person,
          sourceId: sourceId,
          heroTag: heroTag,
        ),
      );

  @override
  State<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage> {
  final ScrollController _scrollController = ScrollController();
  PersonProfile? _profile;
  bool _loading = true;
  final List<PersonWork> _works = [];
  final List<MediaItem> _providerResults = [];
  bool _loadingProviders = false;
  int _page = 1;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _bioExpanded = false;
  bool _isFav = false;

  @override
  void initState() {
    super.initState();
    _isFav = sl<FavoritePeopleStore>().isFavorite(widget.person);
    _scrollController.addListener(_onScroll);
    _loadProfile();
    _loadProviderVideos();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final p = await sl<PeopleService>().load(widget.person);
    if (!mounted) return;
    setState(() {
      _profile = p;
      _loading = false;
      if (p != null) {
        _works.addAll(p.works);
        _hasMore = p.works.length >= 30 &&
            (widget.person.source == PersonSource.thePornDbPerformer ||
                widget.person.source == PersonSource.thePornDbStudio ||
                widget.person.source == PersonSource.tmdb);
      }
    });
  }

  Future<void> _loadProviderVideos() async {
    setState(() => _loadingProviders = true);
    try {
      List<MediaItem> results;
      final isTpdb = widget.person.source == PersonSource.thePornDbPerformer ||
          widget.person.source == PersonSource.thePornDbStudio;

      if (isTpdb) {
        // TPDB performers/studios: only search adult / NSFW sources
        if (widget.sourceId != null &&
            sl<SourceRepository>().isAdultSource(widget.sourceId!)) {
          results = await sl<SourceRepository>().search(
            widget.person.name,
            sourceId: widget.sourceId,
          );
        } else {
          results = await sl<SourceRepository>().searchAdult(widget.person.name);
        }
      } else {
        // TMDB actors: search standard sources as configured
        if (widget.sourceId != null &&
            widget.sourceId != 'tmdb:catalog' &&
            !widget.sourceId!.startsWith('tpdb:')) {
          results = await sl<SourceRepository>().search(
            widget.person.name,
            sourceId: widget.sourceId,
          );
        } else {
          results = await sl<SourceRepository>().searchAll(widget.person.name);
        }
      }
      if (!mounted) return;
      setState(() {
        _providerResults
          ..clear()
          ..addAll(results);
        _loadingProviders = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingProviders = false);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll >= maxScroll - 300) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    final nextPage = _page + 1;
    final more =
        await sl<PeopleService>().loadWorks(widget.person, page: nextPage);
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (more.isEmpty) {
        _hasMore = false;
      } else {
        _page = nextPage;
        final existingIds = {for (final w in _works) w.catalogId ?? w.title};
        for (final w in more) {
          if (existingIds.add(w.catalogId ?? w.title)) {
            _works.add(w);
          }
        }
        if (more.length < 30) {
          _hasMore = false;
        }
      }
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _toggleFavorite() async {
    await sl<FavoritePeopleStore>().toggleFavorite(widget.person);
    if (!mounted) return;
    setState(() {
      _isFav = sl<FavoritePeopleStore>().isFavorite(widget.person);
    });
    _snack(_isFav
        ? 'Added ${widget.person.name} to Favorites'
        : 'Removed from Favorites');
  }

  void _playRandom() {
    final pool = _works.isNotEmpty ? _works : (_profile?.works ?? const []);
    if (pool.isEmpty) {
      _snack('No titles available to play');
      return;
    }
    final picked = (pool.toList()..shuffle()).first;
    _openWork(picked);
  }

  Future<void> _playTrailer() async {
    final pool = _works.isNotEmpty ? _works : (_profile?.works ?? const []);
    if (pool.isEmpty) {
      _snack('No titles available for trailer');
      return;
    }
    _snack('Finding trailer…');
    final topWork = pool.first;
    try {
      final isTpdb =
          widget.person.source == PersonSource.thePornDbPerformer ||
              widget.person.source == PersonSource.thePornDbStudio;
      final source = await sl<TrailerService>().resolveTrailer(
        title: topWork.title,
        type: ProviderType.movie,
        year: topWork.releaseDate != null && topWork.releaseDate!.length >= 4
            ? topWork.releaseDate!.substring(0, 4)
            : null,
        tmdbId: (widget.person.source == PersonSource.tmdb &&
                topWork.catalogId != null)
            ? int.tryParse(topWork.catalogId!)
            : null,
        isTv: topWork.isTv,
        tpdbId: isTpdb ? topWork.catalogId : null,
      );
      if (!mounted) return;
      if (source != null) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TrailerScreen(
            title: '${widget.person.name} — ${topWork.title}',
            source: source,
          ),
        ));
      } else {
        _snack('No trailer found for this actor');
      }
    } catch (_) {
      if (mounted) _snack('Couldn’t open trailer');
    }
  }

  Future<void> _openWork(PersonWork w, {String? heroTag}) async {
    _snack('Opening “${w.title}”…');
    try {
      if (widget.person.source == PersonSource.thePornDbPerformer ||
          widget.person.source == PersonSource.thePornDbStudio) {
        MediaItem? match;
        if (w.catalogId != null && w.catalogId!.isNotEmpty) {
          match = MediaItem(
            id: 'tpdb:movie:${w.catalogId}',
            title: w.title,
            cover: w.cover,
            url: 'tpdb://movie/${w.catalogId}',
            type: ProviderType.movie,
            sourceId: 'tpdb:catalog',
          );
        } else {
          final results = await sl<ThePornDb>().search(w.title);
          if (!mounted) return;
          final wanted = normalizeTitle(w.title);
          for (final candidate in results) {
            if (normalizeTitle(candidate.title) == wanted) {
              match = candidate;
              break;
            }
          }
        }
        if (match == null) {
          _snack('“${w.title}” isn’t in ThePornDB');
          return;
        }
        Navigator.of(context).push(DetailScreen.route(match, heroTag: heroTag));
        return;
      }

      if (widget.person.source == PersonSource.tmdb) {
        if (widget.sourceId != null && widget.sourceId != 'tmdb:catalog') {
          final results = await sl<SourceRepository>()
              .search(w.title, sourceId: widget.sourceId);
          if (!mounted) return;
          final match = bestTitleMatch(
            results,
            w.title,
            altTitle: w.romaji,
            wantedMalId: w.malId,
          );
          if (match != null) {
            Navigator.of(context).push(DetailScreen.route(match, heroTag: heroTag));
            return;
          }
        }
        final tmdbId = int.tryParse(w.catalogId ?? '');
        final match = MediaItem(
          id: tmdbId != null
              ? 'tmdb:${w.isTv ? 'tv' : 'movie'}:$tmdbId'
              : 'search:${w.title}',
          title: w.title,
          cover: w.cover,
          url: tmdbId != null
              ? 'tmdb://${w.isTv ? 'tv' : 'movie'}/$tmdbId'
              : 'search://${w.title}',
          type: ProviderType.movie,
          sourceId: 'tmdb:catalog',
          tmdbId: tmdbId,
          tmdbIsTv: w.isTv,
        );
        Navigator.of(context).push(DetailScreen.route(match, heroTag: heroTag));
        return;
      }

      final results = await sl<SourceRepository>()
          .search(w.title, sourceId: widget.sourceId);
      if (!mounted) return;
      final match = bestTitleMatch(
        results,
        w.title,
        altTitle: w.romaji,
        wantedMalId: w.malId,
      );
      if (match == null) {
        _snack('“${w.title}” isn’t on this source');
        return;
      }
      Navigator.of(context).push(DetailScreen.route(match, heroTag: heroTag));
    } catch (_) {
      if (mounted) _snack('Couldn’t open “${w.title}”');
    }
  }

  MediaItem _mediaItemForWork(PersonWork w) {
    final isTpdb = widget.person.source == PersonSource.thePornDbPerformer ||
        widget.person.source == PersonSource.thePornDbStudio;
    if (isTpdb) {
      final cid = w.catalogId;
      return MediaItem(
        id: cid != null ? 'tpdb:movie:$cid' : 'tpdb:movie:${w.title}',
        title: w.title,
        cover: w.cover,
        url: cid != null ? 'tpdb://movie/$cid' : 'tpdb://movie/${w.title}',
        type: ProviderType.movie,
        sourceId: 'tpdb:catalog',
      );
    }
    final tmdbId = int.tryParse(w.catalogId ?? '');
    return MediaItem(
      id: tmdbId != null
          ? 'tmdb:${w.isTv ? 'tv' : 'movie'}:$tmdbId'
          : 'search:${w.title}',
      title: w.title,
      cover: w.cover,
      url: tmdbId != null
          ? 'tmdb://${w.isTv ? 'tv' : 'movie'}/$tmdbId'
          : 'search://${w.title}',
      type: ProviderType.movie,
      sourceId: 'tmdb:catalog',
      tmdbId: tmdbId,
      tmdbIsTv: w.isTv,
    );
  }

  Future<void> _showWorkQuickActions(PersonWork w, String heroTag) async {
    final item = _mediaItemForWork(w);
    await _showMediaItemQuickActions(item, heroTag: heroTag);
  }

  Future<void> _showMediaItemQuickActions(MediaItem item, {String? heroTag}) async {
    final myList = sl<MyListStore>();
    final listStatus = sl<ListStatusStore>();
    final inLibrary = myList.contains(item) || listStatus.statusOf(item) != null;
    final watched = listStatus.statusOf(item) == WatchStatus.completed;

    await showPosterQuickActions(
      context,
      item: item,
      heroTag: heroTag ?? 'item-quick:${item.id}',
      inLibrary: inLibrary,
      watched: watched,
      onPlay: () => Navigator.of(context).push(DetailScreen.route(item, heroTag: heroTag)),
      onInfo: () => Navigator.of(context).push(DetailScreen.route(item, heroTag: heroTag)),
      onMarkWatched: () async {
        if (!myList.contains(item)) await myList.add(item);
        await listStatus.setStatus(item, WatchStatus.completed);
        await myList.pushStatus(item);
        if (mounted) setState(() {});
      },
      onToggleLibrary: () async {
        await myList.toggle(item);
        if (!myList.contains(item)) {
          await listStatus.remove(item);
        }
        if (mounted) setState(() {});
        return myList.contains(item);
      },
    );
  }

  void _openRelated(PersonRef ref, {String? heroTag}) {
    Navigator.of(context)
        .push(PersonPage.route(ref, sourceId: widget.sourceId, heroTag: heroTag));
  }

  void _openSeeAllWorks(String title, List<PersonWork> initialWorks) {
    final initialItems = initialWorks.map(_mediaItemForWork).toList();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SeeAllScreen(
          title: title,
          items: initialItems,
          onTap: (item) {
            Navigator.of(context).push(DetailScreen.route(item));
          },
          onLongPress: (item) => _showMediaItemQuickActions(item),
          onLoadMore: (page) async {
            final more =
                await sl<PeopleService>().loadWorks(widget.person, page: page);
            return more.map(_mediaItemForWork).toList();
          },
        ),
      ),
    );
  }

  void _openSeeAllProvider(String title, List<MediaItem> items) {
    final isTpdb = widget.person.source == PersonSource.thePornDbPerformer ||
        widget.person.source == PersonSource.thePornDbStudio;
    Navigator.of(context).push(
      ProviderVideosScreen.route(
        title: title,
        personName: widget.person.name,
        initialItems: items,
        isTpdb: isTpdb,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    final isTpdb = widget.person.source == PersonSource.thePornDbPerformer ||
        widget.person.source == PersonSource.thePornDbStudio;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          // 1. Pinned & Stretching SliverAppBar mounted from Frame 1
          _buildSliverAppBar(p, isTpdb),

          // 2. Body: loading skeleton or loaded filmography
          if (_loading) ...[
            SliverToBoxAdapter(child: _buildSkeletonLoader()),
          ] else if (p == null && _works.isEmpty) ...[
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.person_off_outlined,
                message: 'Couldn’t load this profile',
              ),
            ),
          ] else ...[
            ..._buildContentSlivers(
              p ?? PersonProfile(name: widget.person.name, works: _works),
              isTpdb,
            ),
          ],

          // Bottom padding
          const SliverToBoxAdapter(child: SizedBox(height: 48)),
        ],
      ),
    );
  }

  // ── Pinned & Stretching SliverAppBar ───────────────────────────────────────

  Widget _buildSliverAppBar(PersonProfile? p, bool isTpdb) {
    final photo = p?.photo ?? widget.person.photo;
    final totalCount = _works.length;
    final metaText = _loading
        ? (isTpdb ? 'Performer' : 'Acting')
        : '${p?.subtitle ?? (isTpdb ? 'Performer' : 'Acting')} · $totalCount ${isTpdb ? 'Releases' : 'Titles'}';
    final effectiveHeroTag = widget.heroTag ??
        'person-avatar:${widget.person.source.name}:${widget.person.externalId ?? widget.person.id}';

    return SliverAppBar(
      expandedHeight: 490,
      pinned: true,
      stretch: true,
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      clipBehavior: Clip.none,
      leadingWidth: 68,
      leading: Padding(
        padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
        child: Center(
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.55),
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(CupertinoIcons.chevron_back, color: Colors.white, size: 21),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
      ),
      actions: const [],
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Background portrait with downward dark gradient blend
            Hero(
              tag: effectiveHeroTag,
              createRectTween: (begin, end) =>
                  MaterialRectArcTween(begin: begin, end: end),
              flightShuttleBuilder: (flightContext, animation, flightDirection, fromHeroContext, toHeroContext) {
                return Material(
                  color: Colors.transparent,
                  child: toHeroContext.widget,
                );
              },
              child: (photo != null && photo.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: photo,
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -0.2),
                      placeholder: (_, _) => Container(color: AppColors.surface2),
                      errorWidget: (_, _, _) => Container(color: AppColors.surface2),
                    )
                  : Container(
                      color: AppColors.surface2,
                      child: const Center(
                        child: Icon(Icons.person, size: 80, color: Colors.white24),
                      ),
                    ),
            ),

            // Multi-stop cinematic dark gradient overlay
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.50),
                    Colors.transparent,
                    Colors.transparent,
                    AppColors.bg.withValues(alpha: 0.35),
                    AppColors.bg.withValues(alpha: 0.85),
                    AppColors.bg,
                  ],
                  stops: const [0.0, 0.18, 0.45, 0.70, 0.90, 1.0],
                ),
              ),
            ),

            // Actor Name, Subtitle, and 3 Action Buttons positioned at bottom
            Positioned(
              left: 20,
              right: 20,
              bottom: 14,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    widget.person.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Circular',
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.6,
                      height: 1.1,
                      shadows: [
                        Shadow(color: Colors.black, blurRadius: 18),
                        Shadow(color: Colors.black87, blurRadius: 6),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    metaText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.75),
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // The 3 Action Buttons Trio (Shuffle / Play Trailer / Favorite)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 1. Play Random Button
                      _buildActionButton(
                        icon: Icons.shuffle_rounded,
                        size: 50,
                        iconSize: 22,
                        background: Colors.white.withValues(alpha: 0.14),
                        iconColor: Colors.white,
                        onTap: _playRandom,
                      ),
                      const SizedBox(width: 22),

                      // 2. Play Trailer (Clean Center Circle - No glow)
                      _buildActionButton(
                        icon: Icons.play_arrow_rounded,
                        size: 66,
                        iconSize: 40,
                        background: Colors.white,
                        iconColor: Colors.black,
                        onTap: _playTrailer,
                      ),
                      const SizedBox(width: 22),

                      // 3. Add to Favorite Actors Button
                      _buildActionButton(
                        icon: _isFav
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 50,
                        iconSize: 22,
                        background: Colors.white.withValues(alpha: 0.14),
                        iconColor: _isFav ? const Color(0xFFFF2D55) : Colors.white,
                        onTap: _toggleFavorite,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required double size,
    required double iconSize,
    required Color background,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: background,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(
            child: Icon(icon, color: iconColor, size: iconSize),
          ),
        ),
      ),
    );
  }

  // ── Content Slivers ────────────────────────────────────────────────────────

  List<Widget> _buildContentSlivers(PersonProfile p, bool isTpdb) {
    // Categorized filmography rows
    final popularWorks = List<PersonWork>.from(_works)
      ..sort((a, b) =>
          ((b.popularity ?? b.rating ?? 0)).compareTo(a.popularity ?? a.rating ?? 0));

    final latestWorks = List<PersonWork>.from(_works)
      ..sort((a, b) =>
          (b.releaseDate ?? '').compareTo(a.releaseDate ?? ''));

    final movieWorks = _works.where((w) => !w.isTv && !w.isScene).toList();
    final seriesWorks = _works.where((w) => w.isTv).toList();

    return [
      // 1. "Popular" Row
      if (popularWorks.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: _buildSectionHeader(
            'Popular',
            onSeeAll: () => _openSeeAllWorks('Popular', popularWorks),
          ),
        ),
        SliverToBoxAdapter(child: _buildHorizontalPosters(popularWorks)),
      ],

      // 2. "Latest" Row
      if (latestWorks.isNotEmpty && latestWorks.length > 2) ...[
        SliverToBoxAdapter(
          child: _buildSectionHeader(
            'Latest Releases',
            onSeeAll: () => _openSeeAllWorks('Latest Releases', latestWorks),
          ),
        ),
        SliverToBoxAdapter(child: _buildHorizontalPosters(latestWorks)),
      ],

      // 3. "From Provider" (Real Installed Provider Videos)
      if (_providerResults.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: _buildSectionHeader(
            'From Provider',
            onSeeAll: () => _openSeeAllProvider('From Provider', _providerResults),
          ),
        ),
        SliverToBoxAdapter(child: _buildHorizontalProviderVideos(_providerResults)),
      ] else if (_loadingProviders) ...[
        SliverToBoxAdapter(
          child: _buildSectionHeader('From Provider'),
        ),
        SliverToBoxAdapter(
          child: Container(
            height: 140,
            alignment: Alignment.center,
            child: const CupertinoActivityIndicator(color: Colors.white54),
          ),
        ),
      ],

      // 4. "Movies" Row
      if (movieWorks.isNotEmpty && movieWorks.length != popularWorks.length) ...[
        SliverToBoxAdapter(
          child: _buildSectionHeader(
            'Movies',
            onSeeAll: () => _openSeeAllWorks('Movies', movieWorks),
          ),
        ),
        SliverToBoxAdapter(child: _buildHorizontalPosters(movieWorks)),
      ],

      // 5. "Series" Row (if actor has TV credits)
      if (seriesWorks.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: _buildSectionHeader(
            'Series',
            onSeeAll: () => _openSeeAllWorks('Series', seriesWorks),
          ),
        ),
        SliverToBoxAdapter(child: _buildHorizontalPosters(seriesWorks)),
      ],

      // 6. "Related Actors" (Circular Avatars - Large)
      if (p.related.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: _buildSectionHeader(
            widget.person.source == PersonSource.anilistCharacter
                ? 'Voiced by'
                : 'Related Actors',
          ),
        ),
        SliverToBoxAdapter(child: _buildRelatedActorsRow(p.related)),
      ],

      // 7. Description / Biography Card
      if (p.description != null && p.description!.trim().isNotEmpty) ...[
        SliverToBoxAdapter(child: _buildDescriptionCard(p.description!)),
      ],
    ];
  }

  // ── Section Header with Optional 'See All' (>) ─────────────────────────────

  Widget _buildSectionHeader(String title, {VoidCallback? onSeeAll}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Icon(
                  CupertinoIcons.chevron_right,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Poster Row (Popular / Latest / Movies / Series) ─────────────────────────

  Widget _buildHorizontalPosters(List<PersonWork> list) {
    return SizedBox(
      height: 256,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, idx) {
          final w = list[idx];
          final heroTag = 'person-poster:${w.catalogId ?? w.title}:$idx';
          return GestureDetector(
            onTap: () => _openWork(w, heroTag: heroTag),
            onLongPress: () => _showWorkQuickActions(w, heroTag),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 134,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Hero(
                      tag: heroTag,
                      createRectTween: (begin, end) =>
                          MaterialRectArcTween(begin: begin, end: end),
                      child: Container(
                        width: 134,
                        height: 194,
                        color: AppColors.surface2,
                        child: (w.cover != null && w.cover!.isNotEmpty)
                            ? Image(
                                image: nativeCoverProvider(w.cover!, null),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Center(
                                  child: Icon(Icons.movie_outlined,
                                      color: Colors.white24, size: 32),
                                ),
                              )
                            : const Center(
                                child: Icon(Icons.movie_outlined,
                                    color: Colors.white24, size: 32),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    w.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (w.releaseDate != null && w.releaseDate!.isNotEmpty)
                    Text(
                      w.releaseDate!.length >= 4
                          ? w.releaseDate!.substring(0, 4)
                          : w.releaseDate!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
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

  // ── Wide 16:9 Provider Videos ("From Provider") ─────────────────────────────

  Widget _buildHorizontalProviderVideos(List<MediaItem> list) {
    return SizedBox(
      height: 205,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, idx) {
          final item = list[idx];
          final imgUrl = item.cover;
          final heroTag = 'provider-video:${item.id}:$idx';
          return GestureDetector(
            onTap: () => Navigator.of(context).push(DetailScreen.route(item, heroTag: heroTag)),
            onLongPress: () => _showMediaItemQuickActions(item, heroTag: heroTag),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 236,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Hero(
                      tag: heroTag,
                      createRectTween: (begin, end) =>
                          MaterialRectArcTween(begin: begin, end: end),
                      child: Container(
                        width: 236,
                        height: 136,
                        color: AppColors.surface2,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (imgUrl != null && imgUrl.isNotEmpty)
                              Image(
                                image: nativeCoverProvider(imgUrl, null),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  color: AppColors.surface2,
                                ),
                              ),
                            // Subtle dark gradient
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.65),
                                  ],
                                ),
                              ),
                            ),
                            // Center Play Icon watermark
                            Center(
                              child: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.60),
                                  border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.3),
                                      width: 1.2),
                                ),
                                child: const Icon(
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
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.sourceId.isNotEmpty)
                    Text(
                      item.sourceId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11.5,
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

  // ── Related Actors Row (Enlarged Circular Avatars) ─────────────────────────

  Widget _buildRelatedActorsRow(List<PersonRef> list) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(width: 18),
        itemBuilder: (context, idx) {
          final ref = list[idx];
          final heroTag = 'person-avatar:${ref.source.name}:${ref.externalId ?? ref.id}';
          return GestureDetector(
            onTap: () => _openRelated(ref, heroTag: heroTag),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 136,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipOval(
                    child: Container(
                      width: 128,
                      height: 128,
                      color: AppColors.surface2,
                      child: (ref.photo != null && ref.photo!.isNotEmpty)
                          ? Hero(
                              tag: heroTag,
                              createRectTween: (begin, end) =>
                                  MaterialRectArcTween(begin: begin, end: end),
                              flightShuttleBuilder: (flightContext, animation, flightDirection, fromHeroContext, toHeroContext) {
                                return ClipOval(child: toHeroContext.widget);
                              },
                              child: Image(
                                image: nativeCoverProvider(ref.photo!, null),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Center(
                                  child: Icon(Icons.person,
                                      color: Colors.white24, size: 54),
                                ),
                              ),
                            )
                          : const Center(
                              child: Icon(Icons.person,
                                  color: Colors.white24, size: 54),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    ref.name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Circular',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: -0.2,
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

  // ── Description / Bio Card ──────────────────────────────────────────────────

  Widget _buildDescriptionCard(String bio) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'About ${widget.person.name}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              bio,
              maxLines: _bioExpanded ? null : 4,
              overflow: _bioExpanded ? null : TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => _bioExpanded = !_bioExpanded),
              behavior: HitTestBehavior.opaque,
              child: Text(
                _bioExpanded ? 'Show less' : 'Read more',
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Skeleton Loader Below Header ───────────────────────────────────────────

  Widget _buildSkeletonLoader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              width: 110,
              height: 18,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 194,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 4,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, _) => Container(
                width: 134,
                height: 194,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
