import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injector.dart';
import '../../../core/models/home_section.dart';
import '../../../core/models/media_item.dart';
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
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (_homeCubit.state.sections == null) {
      _homeCubit.load();
    }
  }

  @override
  void dispose() {
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

          return CustomScrollView(
            controller: _scrollController,
            physics: const ClampingScrollPhysics(),
            slivers: [
              // ── Full-Bleed Hero Carousel at Top ─────────────────────
              if (carouselItems.isNotEmpty)
                SliverToBoxAdapter(
                  child: DesktopHeroBanner(
                    items: carouselItems,
                    onPlay: _openDetail,
                    onMoreInfo: _openDetail,
                  ),
                )
              else
                const SliverToBoxAdapter(child: SizedBox(height: 80)),

              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              // ── Media Rows with Portrait Posters & Clean Titles ───
              SliverList.builder(
                itemCount: sections.length,
                itemBuilder: (context, index) {
                  final section = sections[index];
                  return DesktopMediaRow(
                    title: section.title,
                    items: section.items,
                    onTap: _openDetail,
                    onSeeAll: () => _openSeeAll(section),
                  );
                },
              ),

              const SliverToBoxAdapter(child: _Footer()),
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

class _Footer extends StatelessWidget {
  const _Footer();

  static const _links = <String>[
    'Audio Description',
    'Help Centre',
    'Gift Cards',
    'Media Centre',
    'Investor Relations',
    'Jobs',
    'Terms of Use',
    'Privacy',
    'Legal Notices',
    'Cookie Preferences',
    'Corporate Information',
    'Contact Us',
  ];

  @override
  Widget build(BuildContext context) {
    const linkStyle = TextStyle(
      color: AppColors.textTertiary,
      fontSize: 13,
      height: 1.4,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 40, 56, 56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final icon in const [
                Icons.facebook_rounded,
                Icons.camera_alt_outlined,
                Icons.alternate_email_rounded,
                Icons.play_circle_outline_rounded,
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 22),
                  child: Icon(icon, size: 20, color: AppColors.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: 26),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Wrap(
              spacing: 26,
              runSpacing: 12,
              children: [
                for (final link in _links)
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text(link, style: linkStyle),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text(
            '© ${DateTime.now().year} Cinio. All rights reserved.',
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}