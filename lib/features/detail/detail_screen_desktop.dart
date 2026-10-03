part of 'detail_screen.dart';

/// Desktop-native Detail Screen:
/// • Cinematic widescreen backdrop with AUTO-PLAYING MUTED TRAILER (Netflix style).
/// • Fluid two-column desktop arrangement with high information density.
/// • Instant episode selection with thumbnails, descriptions, and progress bars.
/// • Smooth desktop hover effects and responsive reflow.
class DetailScreenDesktop extends StatefulWidget {
  const DetailScreenDesktop({super.key, required this.item});
  final MediaItem item;

  @override
  State<DetailScreenDesktop> createState() => _DetailScreenDesktopState();
}

class _DetailScreenDesktopState extends State<DetailScreenDesktop> {
  final MyListStore _myList = sl<MyListStore>();
  final ResumeStore _resume = sl<ResumeStore>();
  final ScrollController _scrollController = ScrollController();

  TrailerSource? _trailerSource;
  bool _trailerResolving = false;
  String? _trailerKey;

  @override
  void initState() {
    super.initState();
    final detail = context.read<DetailCubit>().state.detail;
    if (detail != null) {
      _resolveTrailerIfNeeded(detail);
    }
  }

  void _resolveTrailerIfNeeded(MediaDetail detail) {
    final key = '${detail.sourceId}:${detail.id}:${detail.title}';
    if (_trailerKey == key || _trailerResolving) return;
    _trailerKey = key;
    _trailerResolving = true;

    sl<TrailerService>()
        .resolveTrailer(
          title: detail.title,
          englishTitle: detail.englishTitle,
          type: detail.type,
          year: detail.year,
        )
        .then((source) {
      if (!mounted) return;
      if (source != null && source != _trailerSource) {
        setState(() => _trailerSource = source);
      }
    }).catchError((_) {
      // Trailer resolution is optional; fallback to static backdrop
    }).whenComplete(() {
      if (mounted) _trailerResolving = false;
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
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: BlocConsumer<DetailCubit, DetailState>(
        listener: (context, state) {
          final detail = state.detail;
          if (detail != null) {
            _resolveTrailerIfNeeded(detail);
          }
        },
        builder: (context, state) {
          final detail = state.detail;

          if (state.status == DetailStatus.loading || detail == null) {
            return const Center(
              child: CircularProgressIndicator(
                color: AppColors.defaultAccent,
                strokeWidth: 2.5,
              ),
            );
          }

          final episodes = detail.episodes;
          final isSeries = detail.isSeries;
          final backdropUrl = detail.cover ?? widget.item.cover;

          return CustomScrollView(
            controller: _scrollController,
            slivers: [
              // ── Top Navigation Bar Header ───────────────────────
              SliverToBoxAdapter(
                child: _topAppBar(detail),
              ),

              // ── Cinematic Backdrop with Auto-Playing Trailer ─────
              SliverToBoxAdapter(
                child: _backdropTrailerHeader(detail, backdropUrl),
              ),

              // ── Content Info & Action Section ────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
                  child: _metaAndActionSection(detail, episodes),
                ),
              ),

              // ── Episodes / Seasons Section (For TV / Series) ─────
              if (isSeries && episodes.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 12),
                    child: _episodesHeader(detail, episodes),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 12),
                  sliver: _episodesGrid(detail, episodes),
                ),
              ],

              const SliverToBoxAdapter(
                child: SizedBox(height: 60),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _topAppBar(MediaDetail detail) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: AppColors.bg,
      child: Row(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: const Row(
                children: [
                  Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Back',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              detail.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _backdropTrailerHeader(MediaDetail detail, String? backdropUrl) {
    final hasTrailer = _trailerSource != null;

    return Container(
      height: 440,
      width: double.infinity,
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // If trailer is resolved, show auto-playing muted trailer
          if (hasTrailer)
            _HeroTrailer(
              trailer: _trailerSource!,
              collapsed: false,
              placeholder: _backdropCover(backdropUrl),
            )
          else
            _backdropCover(backdropUrl),

          // Vignette gradient blending into background
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.4, 0.75, 1.0],
                    colors: [
                      Colors.transparent,
                      AppColors.bg.withValues(alpha: 0.65),
                      AppColors.bg,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _backdropCover(String? backdropUrl) {
    if (backdropUrl != null && backdropUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: backdropUrl,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        memCacheWidth: 1440,
        placeholder: (_, _) => Container(color: AppColors.surface),
        errorWidget: (_, _, _) => Container(color: AppColors.surface),
      );
    }
    return Container(color: AppColors.surface);
  }

  Widget _metaAndActionSection(MediaDetail detail, List<Episode> episodes) {
    final isBookmarked = _myList.contains(widget.item);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Poster Card
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 200,
            height: 300,
            color: AppColors.surface,
            child: widget.item.cover != null
                ? CachedNetworkImage(
                    imageUrl: widget.item.cover!,
                    fit: BoxFit.cover,
                    memCacheWidth: 400,
                    memCacheHeight: 600,
                  )
                : const Icon(Icons.movie_rounded, color: AppColors.textTertiary, size: 48),
          ),
        ),

        const SizedBox(width: 36),

        // Right Column: Title, Metadata, Overview, Action Buttons
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                detail.title,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),

              const SizedBox(height: 10),

              // Badges & Meta
              Row(
                children: [
                  if (detail.year != null && detail.year!.isNotEmpty) ...[
                    _metaChip(detail.year!),
                    const SizedBox(width: 8),
                  ],
                  if (detail.rating != null && detail.rating! > 0) ...[
                    const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFFB800)),
                    const SizedBox(width: 4),
                    Text(
                      detail.rating!.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (detail.isSeries)
                    _metaChip('${episodes.length} Episodes'),
                ],
              ),

              const SizedBox(height: 16),

              // Overview / Synopsis
              if (detail.description != null && detail.description!.isNotEmpty)
                Text(
                  detail.description!,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),

              const SizedBox(height: 24),

              // Action Buttons Row
              Row(
                children: [
                  // Play S1 E1 or Resume Button
                  if (episodes.isNotEmpty)
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => _playEpisode(detail, episodes, 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_arrow_rounded, color: Colors.black, size: 24),
                              SizedBox(width: 8),
                              Text(
                                'Watch Now',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(width: 14),

                  // My List Toggle
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isBookmarked) {
                            _myList.remove(widget.item);
                          } else {
                            _myList.add(widget.item);
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isBookmarked
                                  ? Icons.bookmark_added_rounded
                                  : Icons.bookmark_add_outlined,
                              color: isBookmarked ? AppColors.defaultAccent : Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isBookmarked ? 'In My List' : 'Add to List',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metaChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _episodesHeader(MediaDetail detail, List<Episode> episodes) {
    return Row(
      children: [
        const Text(
          'Episodes',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const Spacer(),
        // Episode count
        Text(
          '${episodes.length} Total',
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _episodesGrid(MediaDetail detail, List<Episode> episodes) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        mainAxisExtent: 100,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final ep = episodes[index];
          final title = ep.title.isNotEmpty ? ep.title : 'Episode ${ep.number}';
          final epNum = (ep.number != null && ep.number! > 0) ? '${ep.number}' : '${index + 1}';

          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _playEpisode(detail, episodes, index),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1,
                  ),
                ),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // Number Badge
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          epNum,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Title & Description
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            ep.url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.play_circle_outline_rounded,
                      color: Colors.white70,
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        childCount: episodes.length,
      ),
    );
  }
}
