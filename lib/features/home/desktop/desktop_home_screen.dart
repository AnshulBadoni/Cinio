import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/di/injector.dart';
import '../../../core/models/home_section.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/provider_info.dart';
import '../../../core/playback/my_list.dart';
import '../../../core/playback/watch_history.dart';
import '../../../core/theme/app_colors.dart';
import '../../detail/detail_screen.dart';
import '../../shell/desktop_nav_bar.dart';
import '../cubit/home_cubit.dart';
import '../see_all_screen.dart';
import 'desktop_hero_banner.dart';
import 'desktop_media_row.dart';

class DesktopHomeScreen extends StatefulWidget {
  const DesktopHomeScreen({
    super.key,
    this.selectedCategory = DesktopNavCategory.home,
  });

  final DesktopNavCategory selectedCategory;

  @override
  State<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends State<DesktopHomeScreen> {
  final HomeCubit _homeCubit = sl<HomeCubit>();
  final MyListStore _myList = sl<MyListStore>();
  final WatchHistory _watchHistory = sl<WatchHistory>();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _myList.revision.addListener(_onStateChanged);
    if (Hive.isBoxOpen(WatchHistory.boxName)) {
      Hive.box<Map>(WatchHistory.boxName).listenable().addListener(_onStateChanged);
    }
    if (_homeCubit.state.sections == null) {
      _homeCubit.load();
    }
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _myList.revision.removeListener(_onStateChanged);
    if (Hive.isBoxOpen(WatchHistory.boxName)) {
      Hive.box<Map>(WatchHistory.boxName).listenable().removeListener(_onStateChanged);
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _openDetail(MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DetailScreen(item: item)),
    );
  }

  void _openSeeAll(HomeSection section) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SeeAllScreen(
          title: section.title,
          items: section.items,
          onTap: _openDetail,
        ),
      ),
    );
  }

  List<HomeSection> _filterSections(List<HomeSection> raw) {
    return raw;
  }

  List<MediaItem> _buildCarouselItems(
    List<HomeSection> sections,
    List<MediaItem> heroItems,
  ) {
    final result = <MediaItem>[];
    final seenIds = <String>{};

    void add(MediaItem item) {
      if (item.title.isNotEmpty && seenIds.add(item.id)) {
        result.add(item);
      }
    }

    // 1. Take distinct top items from heroItems
    for (final it in heroItems) {
      add(it);
      if (result.length >= 4) break;
    }

    // 2. Interleave from diverse sections (TV Shows, Movies, Trending) to guarantee variety
    for (final sec in sections) {
      for (final it in sec.items) {
        add(it);
        if (result.length >= 8) break;
      }
      if (result.length >= 8) break;
    }

    if (result.isEmpty && heroItems.isNotEmpty) {
      return heroItems.take(6).toList();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: BlocBuilder<HomeCubit, HomeState>(
        bloc: _homeCubit,
        builder: (context, state) {
          final rawSections = state.sections ?? const <HomeSection>[];

          if (state.loading && rawSections.isEmpty) {
            return const _FullScreenLoader();
          }

          if (rawSections.isEmpty) {
            return _EmptyState(onRetry: () => _homeCubit.load(reset: true));
          }

          final sections = _filterSections(rawSections);
          final carouselItems = _buildCarouselItems(sections, state.heroItems);
          final myListItems = _myList.all();

          final recentHistory = Hive.isBoxOpen(WatchHistory.boxName)
              ? _watchHistory.recent()
              : const <HistoryEntry>[];

          final continueItems = recentHistory.map((e) {
            int? tmdbId;
            if (e.sourceId == 'tmdb:catalog') {
              final match = RegExp(r'/((?:tv|movie))/([0-9]+)').firstMatch(e.showUrl);
              if (match != null) tmdbId = int.tryParse(match.group(2)!);
            }
            return MediaItem(
              id: e.showId,
              title: e.showTitle,
              url: e.showUrl,
              sourceId: e.sourceId,
              cover: e.cover,
              heroImage: (e.thumbnail != null && e.thumbnail!.isNotEmpty)
                  ? e.thumbnail
                  : null,
              coverHeaders: e.coverHeaders,
              type: ProviderType.movie,
              malId: e.malId,
              tmdbIsTv: e.sourceId == 'tmdb:catalog' && e.showUrl.contains('/tv/'),
              tmdbId: tmdbId,
            );
          }).toList();

          // Exclude duplicate My List and Continue Watching from backend sections
          final otherSections = sections.where((s) {
            final t = s.title.trim().toLowerCase();
            return t != 'my list' && t != 'watchlist' && !t.contains('continue watching');
          }).toList();

          // First row: Continue Watching row with wide thumbnails (or first backend section if no history)
          final Widget? heroBottomRow;
          final List<HomeSection> remainingSections;

          if (continueItems.isNotEmpty) {
            heroBottomRow = DesktopMediaRow(
              title: 'CONTINUE WATCHING',
              items: continueItems,
              onTap: _openDetail,
              landscape: true,
              showTitles: false,
              padding: const EdgeInsets.only(bottom: 8),
            );
            remainingSections = [
              if (myListItems.isNotEmpty)
                HomeSection(
                  title: 'My List',
                  items: myListItems,
                ),
              ...otherSections,
            ];
          } else if (otherSections.isNotEmpty) {
            final first = otherSections.first;
            final isLandscape = (first.title.toLowerCase().contains('continue') ||
                    first.title.toLowerCase().contains('watch again')) &&
                first.items.any((it) => it.heroImage != null && it.heroImage!.isNotEmpty);
            heroBottomRow = DesktopMediaRow(
              title: first.title.toUpperCase(),
              items: first.items,
              onTap: _openDetail,
              landscape: isLandscape,
              showTitles: false,
              padding: const EdgeInsets.only(bottom: 8),
            );
            remainingSections = [
              if (myListItems.isNotEmpty)
                HomeSection(
                  title: 'My List',
                  items: myListItems,
                ),
              ...otherSections.skip(1),
            ];
          } else {
            heroBottomRow = null;
            remainingSections = [
              if (myListItems.isNotEmpty)
                HomeSection(
                  title: 'My List',
                  items: myListItems,
                ),
            ];
          }

          return CustomScrollView(
            controller: _scrollController,
            physics: const ClampingScrollPhysics(),
            slivers: [
              // ── Full-Bleed Fullscreen Hero Carousel with Embedded First Row ──
              if (carouselItems.isNotEmpty)
                SliverToBoxAdapter(
                  child: DesktopHeroBanner(
                    items: carouselItems,
                    onPlay: _openDetail,
                    onMoreInfo: _openDetail,
                    bottomRow: heroBottomRow,
                  ),
                )
              else
                const SliverToBoxAdapter(child: SizedBox(height: 80)),

              // ── Remaining Media Rows with High-Res Posters ─────────
              SliverList.builder(
                itemCount: remainingSections.length,
                itemBuilder: (context, index) {
                  final section = remainingSections[index];
                  final title = section.title.toLowerCase();
                  // Only rows with actual 16:9 episode screenshots should be landscape
                  final isLandscape = (title.contains('continue watching') ||
                          title.contains('watch again')) &&
                      section.items.any((it) => it.heroImage != null && it.heroImage!.isNotEmpty);
                  return DesktopMediaRow(
                    title: section.title.toUpperCase(),
                    items: section.items,
                    onTap: _openDetail,
                    onSeeAll: () => _openSeeAll(section),
                    landscape: isLandscape,
                  );
                },
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 56)),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _FullScreenLoader extends StatelessWidget {
  const _FullScreenLoader();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 34,
        height: 34,
        child: CircularProgressIndicator(
          color: AppColors.accent,
          strokeWidth: 2.6,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 48,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 16),
          const Text(
            'Something went wrong',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "We couldn't load this page. Please try again.",
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text(
              'Try again',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}