import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/metadata/favorite_people_store.dart';
import '../../core/metadata/people_service.dart';
import '../../core/models/media_item.dart';
import '../../core/models/person.dart';
import '../../core/models/provider_info.dart';
import '../../core/models/watch_status.dart';
import '../../core/playback/list_status_store.dart';
import '../../core/playback/my_list.dart';
import '../../core/playback/playback_prefs.dart';
import '../../core/repository/source_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/trailer/trailer_service.dart';
import '../../core/ui/native_cover_provider.dart';
import '../../core/ui/poster_quick_actions.dart';
import '../../core/ui/states.dart';
import '../detail/detail_screen.dart';
import '../home/see_all_screen.dart';
import '../trailer/trailer_screen.dart';
import 'person_page.dart';
import 'provider_videos_screen.dart';

/// Dedicated Studio Profile Page designed for production companies & brands.
/// Distinct from actor profiles: features widescreen cinematic studio backdrops,
/// floating brand logos, production metadata, studio quick actions, flagship
/// filmography, TV shows, and starring performers.
class StudioPage extends StatefulWidget {
  const StudioPage({
    super.key,
    required this.studio,
    this.sourceId,
    this.heroTag,
  });

  final PersonRef studio;
  final String? sourceId;
  final String? heroTag;

  static Route<void> route(
    PersonRef studio, {
    String? sourceId,
    String? heroTag,
  }) =>
      MaterialPageRoute<void>(
        builder: (_) => StudioPage(
          studio: studio,
          sourceId: sourceId,
          heroTag: heroTag,
        ),
      );

  @override
  State<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends State<StudioPage> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _heroStretch = ValueNotifier<double>(0.0);
  final ValueNotifier<double> _scrollOffset = ValueNotifier<double>(0.0);

  PersonProfile? _profile;
  bool _loading = true;
  final List<PersonWork> _works = [];
  final List<MediaItem> _providerResults = [];
  int _page = 1;
  bool _hasMore = true;
  bool _aboutExpanded = false;
  bool _isFav = false;

  @override
  void initState() {
    super.initState();
    _isFav = sl<FavoritePeopleStore>().isFavorite(widget.studio);
    _scrollController.addListener(_onScroll);
    _loadProfile();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _heroStretch.dispose();
    _scrollOffset.dispose();
    super.dispose();
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    _scrollOffset.value = offset;
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    final profile = await sl<PeopleService>().load(widget.studio);
    if (!mounted) return;

    if (profile != null) {
      _works.addAll(profile.works);
    }
    setState(() {
      _profile = profile;
      _loading = false;
    });

    if (profile != null && profile.providerVideos.isNotEmpty) {
      _providerResults.addAll(
        profile.providerVideos.map((pv) => MediaItem(
          id: pv.catalogId != null ? 'tpdb:scene:${pv.catalogId}' : 'scene:${pv.title.hashCode}',
          title: pv.title,
          cover: pv.cover,
          heroImage: pv.backdrop,
          url: 'tpdb://scene/${pv.catalogId ?? ''}',
          type: ProviderType.movie,
          sourceId: 'tpdb:scene',
          year: pv.releaseDate != null && pv.releaseDate!.length >= 4
              ? pv.releaseDate!.substring(0, 4)
              : null,
        )),
      );
    }
  }

  void _toggleFavorite() async {
    final store = sl<FavoritePeopleStore>();
    await store.toggleFavorite(widget.studio);
    if (!mounted) return;
    setState(() {
      _isFav = store.isFavorite(widget.studio);
    });
    _snack(_isFav ? 'Added ${widget.studio.name} to Favorite Studios' : 'Removed from Favorite Studios');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _playRandom() {
    final candidates = _works.isNotEmpty ? _works : (_profile?.providerVideos ?? const <PersonWork>[]);
    if (candidates.isEmpty) {
      _snack('No releases found to play');
      return;
    }
    final shuffled = List<PersonWork>.from(candidates)..shuffle();
    final chosen = shuffled.first;
    _openWork(chosen);
  }

  Future<void> _playTrailer() async {
    if (!sl.isRegistered<TrailerService>()) {
      _snack('Trailers unavailable');
      return;
    }
    final pool = _works.isNotEmpty ? _works : (_profile?.works ?? const []);
    if (pool.isEmpty) {
      _snack('No releases available for trailer');
      return;
    }
    _snack('Finding trailer…');
    final topWork = pool.first;
    try {
      final isTpdb = widget.studio.source == PersonSource.thePornDbStudio;
      final source = await sl<TrailerService>().resolveTrailer(
        title: topWork.title,
        type: ProviderType.movie,
        year: topWork.releaseDate != null && topWork.releaseDate!.length >= 4
            ? topWork.releaseDate!.substring(0, 4)
            : null,
        tmdbId: (!isTpdb && topWork.catalogId != null)
            ? int.tryParse(topWork.catalogId!)
            : null,
        isTv: topWork.isTv,
        tpdbId: isTpdb ? topWork.catalogId : null,
      );
      if (!mounted) return;
      if (source != null) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TrailerScreen(
            title: '${widget.studio.name} — ${topWork.title}',
            source: source,
          ),
        ));
      } else {
        _snack('No trailer found for this studio');
      }
    } catch (_) {
      if (mounted) _snack('Couldn’t open trailer');
    }
  }

  void _openWork(PersonWork work) {
    final item = _mediaItemForWork(work);
    Navigator.of(context).push(DetailScreen.route(item));
  }

  MediaItem _mediaItemForWork(PersonWork work) {
    final isTv = work.isTv;
    final isTpdb = widget.studio.source == PersonSource.thePornDbStudio;
    final cid = work.catalogId;
    final id = cid != null && cid.isNotEmpty
        ? (isTpdb ? 'tpdb:movie:$cid' : (isTv ? 'tmdb:tv:$cid' : 'tmdb:movie:$cid'))
        : (isTv ? 'tv:${work.title.hashCode}' : 'work:${work.title.hashCode}');
    final url = cid != null && cid.isNotEmpty
        ? (isTpdb ? 'tpdb://movie/$cid' : (isTv ? 'tmdb://tv/$cid' : 'tmdb://movie/$cid'))
        : '';
    final sourceId = isTpdb ? 'tpdb:catalog' : 'tmdb:catalog';

    return MediaItem(
      id: id,
      title: work.title,
      cover: work.cover,
      heroImage: work.backdrop,
      url: url,
      type: ProviderType.movie,
      sourceId: sourceId,
      tmdbId: int.tryParse(cid ?? ''),
      tmdbIsTv: isTv,
      year: work.releaseDate != null && work.releaseDate!.length >= 4
          ? work.releaseDate!.substring(0, 4)
          : null,
    );
  }

  Future<void> _showMediaItemQuickActions(MediaItem item, {String? heroTag}) async {
    final myList = sl<MyListStore>();
    final listStatus = sl<ListStatusStore>();
    final inLibrary = myList.contains(item) || listStatus.statusOf(item) != null;
    final watched = listStatus.statusOf(item) == WatchStatus.completed;

    await showPosterQuickActions(
      context,
      item: item,
      heroTag: heroTag ?? 'studio-quick:${item.id}',
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

  void _openSeeAllWorks(String title, List<PersonWork> initialWorks) {
    final initialItems = initialWorks.map(_mediaItemForWork).toList();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SeeAllScreen(
          title: title,
          items: initialItems,
          initialPage: _page,
          onTap: (item) {
            Navigator.of(context).push(DetailScreen.route(item));
          },
          onLongPress: (item) => _showMediaItemQuickActions(item),
          onLoadMore: (page) async {
            final more = await sl<PeopleService>().loadWorks(widget.studio, page: page);
            return more.map(_mediaItemForWork).toList();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    final isTpdb = widget.studio.source == PersonSource.thePornDbStudio;
    final totalCount = _works.length;

    final logo = p?.photo ?? widget.studio.photo;
    final backdrop = (p?.photos.isNotEmpty == true)
        ? p!.photos.first
        : (logo ?? '');

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis == Axis.vertical) {
            if (notification.metrics.pixels < 0) {
              _heroStretch.value = (-notification.metrics.pixels).clamp(0.0, 320.0);
            } else if (_heroStretch.value > 0) {
              _heroStretch.value = 0.0;
            }
          }
          return false;
        },
        child: CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            // Pinned widescreen brand banner
            _buildSliverHeader(backdrop, logo, totalCount, isTpdb),

            // Content
            if (_loading) ...[
              SliverToBoxAdapter(child: _buildSkeletonLoader()),
            ] else if (p == null && _works.isEmpty) ...[
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.business_outlined,
                  message: 'Couldn’t load studio catalog',
                ),
              ),
            ] else ...[
              // Flagship Popular Releases
              if (_works.isNotEmpty)
                _buildSectionRail('Popular Releases', _works.take(12).toList()),

              // Latest Releases
              if (_works.length > 6)
                _buildSectionRail('Latest Releases', _works.reversed.take(12).toList()),

              // TV Series (if TMDB studio has series)
              if (_works.any((w) => w.isTv))
                _buildSectionRail(
                  'TV Series & Shows',
                  _works.where((w) => w.isTv).take(12).toList(),
                ),

              // Studio Scenes & Clips (for TPDB studios)
              if (_providerResults.isNotEmpty)
                _buildScenesSection(),

              // Top Performers & Cast
              if (p != null && p.related.isNotEmpty)
                _buildCastSection(p.related),

              // About Studio
              if (p?.description != null && p!.description!.trim().isNotEmpty)
                SliverToBoxAdapter(child: _buildAboutSection(p.description!)),

              const SliverToBoxAdapter(child: SizedBox(height: 60)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSliverHeader(String backdropUrl, String? logoUrl, int totalCount, bool isTpdb) {
    final topPadding = MediaQuery.paddingOf(context).top;
    final expandedHeight = 310.0 + topPadding;

    return SliverAppBar(
      pinned: true,
      elevation: 0,
      backgroundColor: AppColors.bg,
      expandedHeight: expandedHeight,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Center(
          child: GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.50),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
            ),
          ),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: ValueListenableBuilder<double>(
          valueListenable: _heroStretch,
          builder: (context, stretch, _) {
            final scale = 1.0 + (stretch / 400.0).clamp(0.0, 0.40);
            return Stack(
              fit: StackFit.expand,
              children: [
                // 1. Widescreen Backdrop Image
                if (backdropUrl.isNotEmpty)
                  Transform.scale(
                    scale: scale,
                    alignment: Alignment.topCenter,
                    child: CachedNetworkImage(
                      imageUrl: backdropUrl,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorWidget: (_, __, ___) => Container(color: AppColors.surface2),
                    ),
                  )
                else
                  Container(color: AppColors.surface2),

                // 2. Cinematic Gradient Overlay
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.black.withValues(alpha: 0.55),
                          AppColors.bg.withValues(alpha: 0.95),
                          AppColors.bg,
                        ],
                        stops: const [0.0, 0.45, 0.85, 1.0],
                      ),
                    ),
                  ),
                ),

                // 3. Studio Brand Information
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Studio Logo / Icon
                      if (logoUrl != null && logoUrl.isNotEmpty)
                        Container(
                          height: 58,
                          constraints: const BoxConstraints(maxWidth: 180),
                          margin: const EdgeInsets.only(bottom: 10),
                          child: CachedNetworkImage(
                            imageUrl: logoUrl,
                            fit: BoxFit.contain,
                            errorWidget: (_, __, ___) => const Icon(Icons.business_rounded, size: 40, color: Colors.white70),
                          ),
                        )
                      else
                        Container(
                          width: 52,
                          height: 52,
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.business_rounded, size: 28, color: Colors.white),
                        ),

                      // Studio Name
                      Text(
                        widget.studio.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.4,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Subtitle / Headquarters metadata
                      Text(
                        _profile?.subtitle ?? (isTpdb ? 'Adult Production Studio' : 'Production Studio'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.72),
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Quick Action Trio (Shuffle / Trailer / Favorite)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildStudioActionBtn(
                            icon: Icons.shuffle_rounded,
                            label: 'Random',
                            onTap: _playRandom,
                          ),
                          const SizedBox(width: 14),
                          _buildStudioActionBtn(
                            icon: Icons.play_arrow_rounded,
                            label: 'Trailer',
                            primary: true,
                            onTap: _playTrailer,
                          ),
                          const SizedBox(width: 14),
                          _buildStudioActionBtn(
                            icon: _isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            label: 'Favorite',
                            iconColor: _isFav ? const Color(0xFFFF2D55) : Colors.white,
                            onTap: _toggleFavorite,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStudioActionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
    Color? iconColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: primary
              ? Colors.white
              : Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.20),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: primary ? Colors.black : (iconColor ?? Colors.white),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: primary ? Colors.black : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionRail(String title, List<PersonWork> works) {
    if (works.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                GestureDetector(
                  onTap: () => _openSeeAllWorks(title, _works),
                  child: Text(
                    'See All',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: works.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, idx) {
                final work = works[idx];
                final item = _mediaItemForWork(work);
                return GestureDetector(
                  onTap: () => _openWork(work),
                  onLongPress: () => _showMediaItemQuickActions(item),
                  child: SizedBox(
                    width: 120,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: work.cover != null && work.cover!.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: work.cover!,
                                    fit: BoxFit.cover,
                                    width: 120,
                                    errorWidget: (_, __, ___) => Container(color: AppColors.surface2),
                                  )
                                : Container(color: AppColors.surface2),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          work.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        if (work.releaseDate != null && work.releaseDate!.length >= 4)
                          Text(
                            work.releaseDate!.substring(0, 4),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.55),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScenesSection() {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Featured Scenes & Clips',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      ProviderVideosScreen.route(
                        title: '${widget.studio.name} Scenes',
                        personName: widget.studio.name,
                        initialItems: _providerResults,
                        isTpdb: true,
                      ),
                    );
                  },
                  child: Text(
                    'See All',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _providerResults.take(10).length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, idx) {
                final item = _providerResults[idx];
                final img = item.heroImage ?? item.cover;
                return GestureDetector(
                  onTap: () => Navigator.of(context).push(DetailScreen.route(item)),
                  onLongPress: () => _showMediaItemQuickActions(item),
                  child: SizedBox(
                    width: 220,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (img != null && img.isNotEmpty)
                                  CachedNetworkImage(
                                    imageUrl: img,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(color: AppColors.surface2),
                                  )
                                else
                                  Container(color: AppColors.surface2),
                                Positioned(
                                  bottom: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.70),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text('SCENE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCastSection(List<PersonRef> performers) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 22, 18, 10),
            child: Text(
              'Starring Cast & Performers',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.3,
              ),
            ),
          ),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: performers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, idx) {
                final p = performers[idx];
                return GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(PersonPage.route(p));
                  },
                  child: SizedBox(
                    width: 78,
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 34,
                          backgroundColor: AppColors.surface2,
                          backgroundImage: p.photo != null && p.photo!.isNotEmpty
                              ? CachedNetworkImageProvider(p.photo!)
                              : null,
                          child: p.photo == null || p.photo!.isEmpty
                              ? const Icon(Icons.person, color: Colors.white38)
                              : null,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          p.name,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutSection(String desc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'About Studio',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: _aboutExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: Text(
              desc,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.white.withValues(alpha: 0.75),
                height: 1.45,
              ),
            ),
            secondChild: Text(
              desc,
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.white.withValues(alpha: 0.75),
                height: 1.45,
              ),
            ),
          ),
          if (desc.length > 140)
            GestureDetector(
              onTap: () => setState(() => _aboutExpanded = !_aboutExpanded),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _aboutExpanded ? 'Show less' : 'Read more',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSkeletonLoader() {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Container(
            height: 180,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            height: 180,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ],
      ),
    );
  }
}
