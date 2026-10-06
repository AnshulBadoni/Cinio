import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/di/injector.dart';
import '../../core/metadata/favorite_people_store.dart';
import '../../core/metadata/people_service.dart';
import '../../core/metadata/theporndb.dart';
import '../../core/models/media_item.dart';
import '../../core/models/person.dart';
import '../../core/models/provider_info.dart';
import '../../core/repository/source_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/trailer/trailer_service.dart';
import '../../core/ui/native_cover.dart';
import '../../core/ui/states.dart';
import '../detail/detail_screen.dart';
import '../trailer/trailer_screen.dart';

/// Redesigned Actor Profile Page with cinematic hero header,
/// quick action trio (Shuffle / Trailer / Favorite), and organized
/// carousels (Popular, Latest, Movies, Series, Provider Videos, Related, Bio).
class PersonPage extends StatefulWidget {
  const PersonPage({super.key, required this.person, this.sourceId});

  final PersonRef person;

  /// The source to search when a title on this page is tapped. Null → active.
  final String? sourceId;

  static Route<void> route(PersonRef person, {String? sourceId}) =>
      MaterialPageRoute<void>(
        builder: (_) => PersonPage(person: person, sourceId: sourceId),
      );

  @override
  State<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage> {
  final ScrollController _scrollController = ScrollController();
  PersonProfile? _profile;
  bool _loading = true;
  final List<PersonWork> _works = [];
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

  void _shareProfile() {
    Clipboard.setData(ClipboardData(text: '${widget.person.name} on Cinio'));
    _snack('Copied “${widget.person.name}” to clipboard');
  }

  Future<void> _openWork(PersonWork w) async {
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
        Navigator.of(context).push(DetailScreen.route(match));
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
            Navigator.of(context).push(DetailScreen.route(match));
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
        Navigator.of(context).push(DetailScreen.route(match));
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
      Navigator.of(context).push(DetailScreen.route(match));
    } catch (_) {
      if (mounted) _snack('Couldn’t open “${w.title}”');
    }
  }

  void _openRelated(PersonRef ref) {
    Navigator.of(context)
        .push(PersonPage.route(ref, sourceId: widget.sourceId));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : _profile == null
              ? const EmptyState(
                  icon: Icons.person_off_outlined,
                  message: 'Couldn’t load this profile',
                )
              : _buildContent(_profile!),
    );
  }

  Widget _buildContent(PersonProfile p) {
    final isTpdb = widget.person.source == PersonSource.thePornDbPerformer ||
        widget.person.source == PersonSource.thePornDbStudio;

    // Categorized filmography rows
    final popularWorks = List<PersonWork>.from(_works)
      ..sort((a, b) =>
          ((b.popularity ?? b.rating ?? 0)).compareTo(a.popularity ?? a.rating ?? 0));

    final latestWorks = List<PersonWork>.from(_works)
      ..sort((a, b) =>
          (b.releaseDate ?? '').compareTo(a.releaseDate ?? ''));

    final movieWorks = _works.where((w) => !w.isTv && !w.isScene).toList();
    final seriesWorks = _works.where((w) => w.isTv).toList();
    final providerVideos = p.providerVideos.isNotEmpty
        ? p.providerVideos
        : _works.where((w) => w.backdrop != null || w.isScene).toList();

    return CustomScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      slivers: [
        // 1. Full-bleed Hero Header
        SliverToBoxAdapter(
          child: _buildHeroHeader(p, isTpdb),
        ),

        // 2. "Popular" Row
        if (popularWorks.isNotEmpty) ...[
          SliverToBoxAdapter(child: _buildSectionHeader('Popular')),
          SliverToBoxAdapter(child: _buildHorizontalPosters(popularWorks)),
        ],

        // 3. "Latest" Row
        if (latestWorks.isNotEmpty && latestWorks.length > 2) ...[
          SliverToBoxAdapter(child: _buildSectionHeader('Latest Releases')),
          SliverToBoxAdapter(child: _buildHorizontalPosters(latestWorks)),
        ],

        // 4. "From Provider" (Wider 16:9 Video Cards)
        if (providerVideos.isNotEmpty) ...[
          SliverToBoxAdapter(child: _buildSectionHeader('From Provider')),
          SliverToBoxAdapter(child: _buildHorizontalWideVideos(providerVideos)),
        ],

        // 5. "Movies" Row
        if (movieWorks.isNotEmpty && movieWorks.length != popularWorks.length) ...[
          SliverToBoxAdapter(child: _buildSectionHeader('Movies')),
          SliverToBoxAdapter(child: _buildHorizontalPosters(movieWorks)),
        ],

        // 6. "Series" Row (if actor has TV credits)
        if (seriesWorks.isNotEmpty) ...[
          SliverToBoxAdapter(child: _buildSectionHeader('Series')),
          SliverToBoxAdapter(child: _buildHorizontalPosters(seriesWorks)),
        ],

        // 7. "Related Actors" (Circular Avatars)
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

        // 8. Description / Biography Card
        if (p.description != null && p.description!.trim().isNotEmpty) ...[
          SliverToBoxAdapter(child: _buildDescriptionCard(p.description!)),
        ],

        // Bottom padding
        const SliverToBoxAdapter(child: SizedBox(height: 48)),
      ],
    );
  }

  // ── Hero Header ────────────────────────────────────────────────────────────

  Widget _buildHeroHeader(PersonProfile p, bool isTpdb) {
    final photo = p.photo ?? widget.person.photo;
    final totalCount = _works.length;
    final metaText =
        '${p.subtitle ?? (isTpdb ? 'Performer' : 'Acting')} · $totalCount ${isTpdb ? 'Releases' : 'Titles'}';

    return Stack(
      children: [
        // Background portrait with downward dark gradient blend
        SizedBox(
          height: 390,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (photo != null && photo.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: photo,
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, -0.4),
                  placeholder: (_, _) =>
                      Container(color: AppColors.surface2),
                  errorBuilder: (_, _, _) =>
                      Container(color: AppColors.surface2),
                )
              else
                Container(
                  color: AppColors.surface2,
                  child: const Center(
                    child: Icon(Icons.person, size: 80, color: Colors.white24),
                  ),
                ),

              // Multi-stop cinematic dark gradient overlay
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.45),
                      Colors.transparent,
                      AppColors.bg.withValues(alpha: 0.70),
                      AppColors.bg,
                    ],
                    stops: const [0.0, 0.35, 0.75, 1.0],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Floating Top Navigation Bar
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildGlassCircleBtn(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => Navigator.of(context).pop(),
                ),
                _buildGlassCircleBtn(
                  icon: Icons.share_rounded,
                  onTap: _shareProfile,
                ),
              ],
            ),
          ),
        ),

        // Actor Name, Subtitle, and 3 Action Buttons positioned at the bottom of the hero
        Positioned(
          left: 20,
          right: 20,
          bottom: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                widget.person.name.toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.5,
                  height: 1.1,
                  shadows: [
                    Shadow(color: Colors.black, blurRadius: 12),
                    Shadow(color: Colors.black87, blurRadius: 4),
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
                    size: 48,
                    iconSize: 22,
                    background: Colors.white.withValues(alpha: 0.14),
                    iconColor: Colors.white,
                    onTap: _playRandom,
                  ),
                  const SizedBox(width: 20),

                  // 2. Play Trailer (Prominent Center Circle)
                  _buildActionButton(
                    icon: Icons.play_arrow_rounded,
                    size: 64,
                    iconSize: 38,
                    background: Colors.white,
                    iconColor: Colors.black,
                    hasGlow: true,
                    onTap: _playTrailer,
                  ),
                  const SizedBox(width: 20),

                  // 3. Add to Favorite Actors Button
                  _buildActionButton(
                    icon: _isFav
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 48,
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
    );
  }

  Widget _buildGlassCircleBtn({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: Colors.black.withValues(alpha: 0.35),
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(icon, color: Colors.white, size: 20),
            ),
          ),
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
    bool hasGlow = false,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: background,
        boxShadow: hasGlow
            ? [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.35),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 8,
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

  // ── Section Header ─────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
      ),
    );
  }

  // ── Poster Row (Popular / Latest / Movies / Series) ─────────────────────────

  Widget _buildHorizontalPosters(List<PersonWork> list) {
    return SizedBox(
      height: 195,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, idx) {
          final w = list[idx];
          return GestureDetector(
            onTap: () => _openWork(w),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 112,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 112,
                      height: 152,
                      color: AppColors.surface2,
                      child: (w.cover != null && w.cover!.isNotEmpty)
                          ? Image(
                              image: nativeCoverProvider(w.cover!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Center(
                                child: Icon(Icons.movie_outlined,
                                    color: Colors.white24, size: 28),
                              ),
                            )
                          : const Center(
                              child: Icon(Icons.movie_outlined,
                                  color: Colors.white24, size: 28),
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    w.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
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
                        fontSize: 11,
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

  // ── Wide 16:9 Video Cards ("From Provider") ─────────────────────────────────

  Widget _buildHorizontalWideVideos(List<PersonWork> list) {
    return SizedBox(
      height: 156,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, idx) {
          final w = list[idx];
          final imgUrl = w.backdrop ?? w.cover ?? '';
          return GestureDetector(
            onTap: () => _openWork(w),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 210,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 210,
                      height: 118,
                      color: AppColors.surface2,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (imgUrl.isNotEmpty)
                            Image(
                              image: nativeCoverProvider(imgUrl),
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
                              width: 38,
                              height: 38,
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
                                size: 24,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    w.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (w.subtitle != null && w.subtitle!.isNotEmpty)
                    Text(
                      w.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
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

  // ── Related Actors Row (Circular Avatars) ──────────────────────────────────

  Widget _buildRelatedActorsRow(List<PersonRef> list) {
    return SizedBox(
      height: 130,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, idx) {
          final ref = list[idx];
          return GestureDetector(
            onTap: () => _openRelated(ref),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 82,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipOval(
                    child: Container(
                      width: 76,
                      height: 76,
                      color: AppColors.surface2,
                      child: (ref.photo != null && ref.photo!.isNotEmpty)
                          ? Image(
                              image: nativeCoverProvider(ref.photo!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Center(
                                child: Icon(Icons.person,
                                    color: Colors.white24, size: 36),
                              ),
                            )
                          : const Center(
                              child: Icon(Icons.person,
                                  color: Colors.white24, size: 36),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ref.name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
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
                style: const TextStyle(
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
}
