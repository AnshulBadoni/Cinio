import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../core/cache/app_image_cache.dart';
import '../../../core/di/injector.dart';
import '../../../core/metadata/theporndb.dart';
import '../../../core/metadata/tmdb_discover_service.dart';
import '../../../core/models/media_item.dart';
import '../../../core/playback/my_list.dart';
import '../../../core/playback/playback_prefs.dart';
import '../../../core/repository/source_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../detail/detail_screen.dart';
import '../../sources/sources_screen.dart';

/// Desktop-native Discover & Search Screen designed after the modern streaming reference:
/// • Top atmospheric filter bar: Search field · Genre multi-select · Year · IMDb Rating · Red Search button.
/// • Masonry content grid: Mixed rhythm of wide (16:9) backdrop cards and tall (2:3) poster cards.
/// • TPDB items strictly formatted in tall poster orientation.
/// • Inline watchlist "+" toggle and smooth hover micro-interactions.
class DesktopDiscoverScreen extends StatefulWidget {
  const DesktopDiscoverScreen({
    super.key,
    required this.searchController,
    this.onOpenDetail,
  });

  final TextEditingController searchController;
  final ValueChanged<MediaItem>? onOpenDetail;

  @override
  State<DesktopDiscoverScreen> createState() => _DesktopDiscoverScreenState();
}

class _DesktopDiscoverScreenState extends State<DesktopDiscoverScreen>
    with SingleTickerProviderStateMixin {
  final MyListStore _myList = sl<MyListStore>();
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _skeletonCtrl;
  late final Animation<double> _skeletonAnim;

  List<MediaItem> _items = [];
  bool _loading = false;
  int _currentPage = 1;
  bool _hasMore = true;

  // Filters
  final Set<String> _selectedGenres = {};
  String _selectedYear = 'All';
  String _selectedRating = 'All';
  String _selectedSource = 'Mixed';
  bool _genreMenuOpen = false;

  static const List<String> _sources = [
    'Mixed',
    'TMDB',
    'TPDB',
    'Providers',
  ];

  static const List<List<String>> _genreColumns = [
    [
      'Romance',
      'Comedy',
      'Children & Family',
      'Award-Winning',
      'Classics',
      'Documentary',
      'Shorts',
      'Crime',
    ],
    [
      'Sci-Fi',
      'Action',
      'Adventure',
      'Fantasy',
      'Horror',
      'Mystery',
      'Drama',
      'Thriller',
    ],
    [
      'Anime',
      'Animation',
      'Music & Musicals',
      'Sports',
      'Stand-Up',
      'Netflix Production',
      'TV Shows',
    ],
  ];

  static const List<String> _years = [
    'All',
    '2026',
    '2025',
    '2024',
    '2023',
    '2022',
    '2021',
    '2020',
    '2010s',
    '2000s',
    '1990s',
  ];

  static const List<String> _ratings = [
    'All',
    '9.0+',
    '8.5+',
    '8.0+',
    '7.5+',
    '7.0+',
    '6.0+',
  ];

  @override
  void initState() {
    super.initState();
    _skeletonCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _skeletonAnim = CurvedAnimation(parent: _skeletonCtrl, curve: Curves.easeInOut);

    widget.searchController.addListener(_onSearchQueryChanged);
    _scrollController.addListener(_onScroll);
    _loadInitialItems();
  }

  void _startSkeletonAnimation() {
    if (!_skeletonCtrl.isAnimating) {
      _skeletonCtrl.repeat(reverse: true);
    }
  }

  void _stopSkeletonAnimation() {
    if (_skeletonCtrl.isAnimating) {
      _skeletonCtrl.stop();
    }
  }

  @override
  void dispose() {
    _skeletonCtrl.dispose();
    widget.searchController.removeListener(_onSearchQueryChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchQueryChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      if (!_loading && _hasMore) {
        _loadMoreItems();
      }
    }
  }

  List<MediaItem> _interleave(List<MediaItem> a, List<MediaItem> b) {
    final out = <MediaItem>[];
    var i = 0, j = 0;
    while (i < a.length || j < b.length) {
      if (i < a.length) out.add(a[i++]);
      if (j < b.length) out.add(b[j++]);
    }
    return out;
  }

  Future<List<MediaItem>> _fetchItemsForSource({
    required String source,
    required String query,
    required int page,
  }) async {
    switch (source) {
      case 'TMDB':
        final tmdb = sl<TmdbDiscoverService>();
        if (query.isNotEmpty) {
          return await tmdb.search(query: query, type: 'all', page: page);
        } else {
          return await tmdb.discover(catalog: 'trending', type: 'all', page: page);
        }
      case 'TPDB':
        if (!sl.isRegistered<ThePornDb>()) return [];
        final tpdb = sl<ThePornDb>();
        return await tpdb.movies(
          page: page,
          query: query.isNotEmpty ? query : null,
        );
      case 'Providers':
        if (!sl.isRegistered<SourceRepository>()) return [];
        final repo = sl<SourceRepository>();
        if (query.isNotEmpty) {
          try {
            return await repo.searchAll(query);
          } catch (_) {
            return [];
          }
        } else {
          try {
            final sections = await repo.home();
            return sections.expand((s) => s.items).toList();
          } catch (_) {
            return [];
          }
        }
      case 'Mixed':
      default:
        final tmdb = sl<TmdbDiscoverService>();
        final tmdbFuture = query.isNotEmpty
            ? tmdb.search(query: query, type: 'all', page: page)
            : tmdb.discover(catalog: 'trending', type: 'all', page: page);

        Future<List<MediaItem>> tpdbFuture = Future.value(<MediaItem>[]);
        if (sl.isRegistered<ThePornDb>()) {
          tpdbFuture = sl<ThePornDb>().movies(
            page: page,
            query: query.isNotEmpty ? query : null,
          );
        }

        final res = await Future.wait([
          tmdbFuture.catchError((_) => <MediaItem>[]),
          tpdbFuture.catchError((_) => <MediaItem>[]),
        ]);
        return _interleave(res[0], res[1]);
    }
  }

  Future<void> _loadInitialItems() async {
    _startSkeletonAnimation();
    setState(() {
      _loading = true;
      _items = [];
      _currentPage = 1;
      _hasMore = true;
    });

    final query = widget.searchController.text.trim();
    List<MediaItem> results = [];

    try {
      results = await _fetchItemsForSource(
        source: _selectedSource,
        query: query,
        page: 1,
      );
    } catch (_) {
      results = [];
    }

    if (mounted) {
      _stopSkeletonAnimation();
      setState(() {
        _items = _applyClientFilters(results);
        _loading = false;
        _hasMore = results.isNotEmpty;
      });
    }
  }

  Future<void> _loadMoreItems() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);

    final nextPage = _currentPage + 1;
    final query = widget.searchController.text.trim();
    List<MediaItem> results = [];

    try {
      results = await _fetchItemsForSource(
        source: _selectedSource,
        query: query,
        page: nextPage,
      );
    } catch (_) {
      results = [];
    }

    if (mounted) {
      setState(() {
        _currentPage = nextPage;
        _items.addAll(_applyClientFilters(results));
        _loading = false;
        _hasMore = results.isNotEmpty;
      });
    }
  }

  List<MediaItem> _applyClientFilters(List<MediaItem> list) {
    if (_selectedGenres.isEmpty && _selectedYear == 'All' && _selectedRating == 'All') {
      return list;
    }

    final isProviders = _selectedSource == 'Providers';

    return list.where((item) {
      // 1. Genre filter
      if (_selectedGenres.isNotEmpty) {
        if (item.genres.isNotEmpty) {
          final matchesGenre = item.genres.any((g) {
            final lower = g.toLowerCase();
            return _selectedGenres.any((sel) => lower.contains(sel.toLowerCase()));
          });
          if (!matchesGenre) return false;
        } else if (!isProviders) {
          return false;
        }
      }

      // 2. Year filter
      if (_selectedYear != 'All') {
        final y = item.year ?? '';
        if (y.isNotEmpty) {
          if (_selectedYear.endsWith('s')) {
            final decade = int.tryParse(_selectedYear.replaceAll('s', '')) ?? 0;
            final itemYear = int.tryParse(y) ?? 0;
            if (itemYear < decade || itemYear >= decade + 10) return false;
          } else if (y != _selectedYear) {
            return false;
          }
        } else if (!isProviders) {
          return false;
        }
      }

      // 3. Rating filter
      if (_selectedRating != 'All') {
        if (item.rating != null && item.rating! > 0) {
          final minRating = double.tryParse(_selectedRating.replaceAll('+', '')) ?? 0.0;
          final rating = item.rating ?? 0.0;
          if (rating < minRating) return false;
        } else if (!isProviders) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  void _triggerSearch() {
    setState(() => _genreMenuOpen = false);
    _loadInitialItems();
  }

  void _openDetail(MediaItem item) {
    if (widget.onOpenDetail != null) {
      widget.onOpenDetail!(item);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => DetailScreen(item: item)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = (width / 260).floor().clamp(3, 6);

    return ColoredBox(
      color: AppColors.bg,
      child: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Top padding for the floating transparent desktop navbar
              const SliverToBoxAdapter(child: SizedBox(height: 84)),

              // ── Top Filter Bar Matching Reference Screenshot ────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 12),
                  child: _buildFilterBar(),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 14)),

              // ── Shimmering Masonry Skeleton Loader ───────────────
              if (_loading && _items.isEmpty)
                SliverPadding(
                  key: const ValueKey('discover-skeleton-padding'),
                  padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 8),
                  sliver: SliverMasonryGrid.count(
                    key: const ValueKey('discover-skeleton-grid'),
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childCount: crossAxisCount * 2 + 2,
                    itemBuilder: (context, index) {
                      return _MasonrySkeletonCard(
                        key: ValueKey('skeleton-card-$index'),
                        animation: _skeletonAnim,
                        index: index,
                      );
                    },
                  ),
                )

              // ── Masonry Grid of Mixed Wide / Tall Posters ─────────
              else if (_items.isNotEmpty)
                SliverPadding(
                  key: const ValueKey('discover-content-padding'),
                  padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 8),
                  sliver: SliverMasonryGrid.count(
                    key: const ValueKey('discover-content-grid'),
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return _MasonryCard(
                        key: ValueKey('content-card-${item.id}-$index'),
                        item: item,
                        index: index,
                        isBookmarked: _myList.contains(item),
                        onBookmarkToggle: () {
                          setState(() {
                            if (_myList.contains(item)) {
                              _myList.remove(item);
                            } else {
                              _myList.add(item);
                            }
                          });
                        },
                        onTap: () => _openDetail(item),
                      );
                    },
                    childCount: _items.length,
                  ),
                )
              else if (!_loading)
                SliverFillRemaining(
                  key: const ValueKey('discover-empty-state'),
                  hasScrollBody: false,
                  child: Center(
                    child: Builder(
                      builder: (context) {
                        final isProviders = _selectedSource == 'Providers';
                        final hasProviders = sl.isRegistered<SourceRepository>() &&
                            sl<SourceRepository>().loadedSources.isNotEmpty;

                        if (isProviders && !hasProviders) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.extension_outlined,
                                size: 48,
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No providers installed on Desktop',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Install Zangetsu JS providers or add Stremio addons in Settings to search',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.50),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 18),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFE50914),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                icon: const Icon(Icons.extension_outlined, size: 18),
                                label: const Text(
                                  'Open Providers',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const SourcesScreen(),
                                    ),
                                  );
                                },
                              ),
                            ],
                          );
                        }

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            HugeIcon(
                              icon: HugeIcons.strokeRoundedSearch01,
                              size: 48,
                              color: Colors.white.withValues(alpha: 0.35),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No titles found',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              isProviders
                                  ? 'No matching results from installed providers'
                                  : 'Try adjusting your search or filters',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.50),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),

              // Bottom Loading Spinner (Pagination only)
              if (_loading && _items.isNotEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 36),
                    child: Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          color: Color(0xFFE50914),
                          strokeWidth: 2.4,
                        ),
                      ),
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 60)),
            ],
          ),

          // ── Frosted Floating Genre Dropdown Overlay ─────────────────
          if (_genreMenuOpen)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _genreMenuOpen = false),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.35),
                  child: Stack(
                    children: [
                      Positioned(
                        top: 155,
                        left: 56 + 260 + 16, // aligned with Genre button
                        child: GestureDetector(
                          onTap: () {}, // catch tap
                          child: _buildGenreDropdownPopup(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Top Filter Controls Bar (Search · Genre ˅ · Year ⬍ · IMDb rating ˅ · Search)
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildFilterBar() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 1. Search Box
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Search',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.50),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 1,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: widget.searchController,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search title, actor, studio…',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.38),
                            fontSize: 12.5,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onSubmitted: (_) => _triggerSearch(),
                      ),
                    ),
                    if (widget.searchController.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          widget.searchController.clear();
                          _triggerSearch();
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                      )
                    else
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedSearch01,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 14),

        // 2. Genre Dropdown Button
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Genre',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.50),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => setState(() => _genreMenuOpen = !_genreMenuOpen),
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _selectedGenres.isNotEmpty
                            ? const Color(0xFFE50914).withValues(alpha: 0.6)
                            : Colors.white.withValues(alpha: 0.12),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _selectedGenres.isEmpty
                                ? 'Genre'
                                : 'Genre (${_selectedGenres.length})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _selectedGenres.isNotEmpty
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.72),
                              fontSize: 12.5,
                              fontWeight: _selectedGenres.isNotEmpty
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        Icon(
                          _genreMenuOpen
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: Colors.white.withValues(alpha: 0.60),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 14),

        // 3. Year Dropdown
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Year',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.50),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _selectedYear != 'All'
                        ? const Color(0xFFE50914).withValues(alpha: 0.6)
                        : Colors.white.withValues(alpha: 0.12),
                    width: 1,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedYear,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF1E1E1E),
                    icon: Icon(
                      Icons.unfold_more_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.60),
                    ),
                    items: _years.map((y) {
                      return DropdownMenuItem<String>(
                        value: y,
                        child: Text(
                          y == 'All' ? 'Year' : y,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 12.5,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedYear = val);
                        _triggerSearch();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 14),

        // 4. IMDb Rating Dropdown
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'IMDb Rating',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.50),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _selectedRating != 'All'
                        ? const Color(0xFFE50914).withValues(alpha: 0.6)
                        : Colors.white.withValues(alpha: 0.12),
                    width: 1,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedRating,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF1E1E1E),
                    icon: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.60),
                    ),
                    items: _ratings.map((r) {
                      return DropdownMenuItem<String>(
                        value: r,
                        child: Text(
                          r == 'All' ? 'IMDb rating' : r,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 12.5,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedRating = val);
                        _triggerSearch();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 14),

        // 5. Source Dropdown (Mixed, TMDB, TPDB, Providers)
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Source',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.50),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _selectedSource != 'Mixed'
                        ? const Color(0xFFE50914).withValues(alpha: 0.6)
                        : Colors.white.withValues(alpha: 0.12),
                    width: 1,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedSource,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF1E1E1E),
                    icon: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.60),
                    ),
                    items: _sources.map((s) {
                      return DropdownMenuItem<String>(
                        value: s,
                        child: Text(
                          s,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 12.5,
                            fontWeight: s == _selectedSource
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedSource = val);
                        _triggerSearch();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 18),

        // 6. Solid Red Search Button
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _triggerSearch,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 36),
              decoration: BoxDecoration(
                color: const Color(0xFFE50914),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE50914).withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Text(
                'Search',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Multi-column Frosted Genre Popup Overlay Matching Reference UI
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildGenreDropdownPopup() {
    return Container(
      width: 490,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF191919).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.65),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final column in _genreColumns)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final g in column)
                        _genreCheckboxItem(g),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () {
                  setState(() => _selectedGenres.clear());
                  _triggerSearch();
                },
                child: Text(
                  'Clear all',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  setState(() => _genreMenuOpen = false);
                  _triggerSearch();
                },
                child: const Text('Apply', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _genreCheckboxItem(String genre) {
    final selected = _selectedGenres.contains(genre);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            if (selected) {
              _selectedGenres.remove(genre);
            } else {
              _selectedGenres.add(genre);
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5.5, horizontal: 4),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 15,
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  genre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.65),
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
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

// ─────────────────────────────────────────────────────────────────────────────
// Shimmering Masonry Skeleton Card for Desktop UI
// ─────────────────────────────────────────────────────────────────────────────

class _MasonrySkeletonCard extends StatelessWidget {
  const _MasonrySkeletonCard({
    super.key,
    required this.animation,
    required this.index,
  });

  final Animation<double> animation;
  final int index;

  @override
  Widget build(BuildContext context) {
    final isWide = (index % 5 == 0) || (index % 5 == 2);
    final aspectRatio = isWide ? (16 / 9) : (2 / 3);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final shimmerAlpha = 0.28 + 0.22 * animation.value;
          final baseColor = AppColors.surface2.withValues(alpha: shimmerAlpha);

          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: Container(
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    // Bottom subtle dark vignette
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.45, 1.0],
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.38),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Placeholder bottom title bars and action button
                    Positioned(
                      left: 12,
                      right: 10,
                      bottom: 10,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  height: 12,
                                  width: isWide ? 140 : 100,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(
                                      alpha: 0.10 + 0.08 * animation.value,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  height: 10,
                                  width: isWide ? 85 : 55,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(
                                      alpha: 0.06 + 0.06 * animation.value,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(
                                alpha: 0.08 + 0.06 * animation.value,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Masonry Content Card (Wide 16:9 or Tall 2:3 with TPDB tall guarantee)
// ─────────────────────────────────────────────────────────────────────────────

class _MasonryCard extends StatefulWidget {
  const _MasonryCard({
    super.key,
    required this.item,
    required this.index,
    required this.isBookmarked,
    required this.onBookmarkToggle,
    required this.onTap,
  });

  final MediaItem item;
  final int index;
  final bool isBookmarked;
  final VoidCallback onBookmarkToggle;
  final VoidCallback onTap;

  @override
  State<_MasonryCard> createState() => _MasonryCardState();
}

class _MasonryCardState extends State<_MasonryCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isTpdb = item.sourceId.startsWith('tpdb:');
    final hasBackdrop = item.heroImage != null &&
        item.heroImage!.isNotEmpty &&
        item.heroImage != item.cover;

    // Signature masonry rhythm: TPDB is strictly tall posters (2:3).
    // All other sources (TMDB, Mixed, Providers) alternate wide (16:9) backdrop cards
    // and tall (2:3) poster cards for a lively, well-proportioned masonry grid.
    final isWide = !isTpdb && ((widget.index % 5 == 0) || (widget.index % 5 == 2));
    final double aspectRatio = isWide ? (16 / 9) : (2 / 3);
    final imageUrl = (isWide && hasBackdrop ? item.heroImage : item.cover) ?? item.cover ?? '';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered ? 1.025 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 1. Artwork
                  if (imageUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: imageUrl,
                      cacheManager: AppImageCache.manager,
                      httpHeaders: item.coverHeaders,
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      memCacheWidth: isWide ? 640 : 420,
                      placeholder: (_, _) => Container(color: AppColors.surface2),
                      errorWidget: (_, _, _) => Container(
                        color: AppColors.surface2,
                        child: const Center(
                          child: Icon(Icons.movie_rounded, color: AppColors.textTertiary, size: 28),
                        ),
                      ),
                    )
                  else
                    Container(color: AppColors.surface2),

                  // 2. Bottom Scrim for Title Legibility
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.45, 0.72, 1.0],
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.35),
                              Colors.black.withValues(alpha: 0.90),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 3. Hover Subtle Dim & Center Play Icon
                  if (_hovered)
                    Container(
                      color: Colors.black.withValues(alpha: 0.22),
                      child: Center(
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.65),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.30), width: 1.2),
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                    ),

                  // 4. Bottom Title & Bookmark "+" Button (Matching Reference)
                  Positioned(
                    left: 12,
                    right: 10,
                    bottom: 10,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: sl<PlaybackPrefs>().hideTitles
                              ? const SizedBox.shrink()
                              : Text(
                                  item.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.1,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black87,
                                        blurRadius: 8,
                                        offset: Offset(0, 1.5),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                        const SizedBox(width: 8),

                        // Frosted Circle "+" Toggle
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: widget.onBookmarkToggle,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: widget.isBookmarked
                                    ? const Color(0xFFE50914)
                                    : Colors.black.withValues(alpha: 0.55),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.35),
                                  width: 1,
                                ),
                              ),
                              child: Icon(
                                widget.isBookmarked
                                    ? Icons.check_rounded
                                    : Icons.add_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
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
}
