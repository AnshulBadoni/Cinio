import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injector.dart';
import '../../../core/models/home_section.dart';
import '../../../core/models/media_item.dart';
import '../../../core/theme/app_colors.dart';
import '../../detail/detail_screen.dart';
import '../cubit/home_cubit.dart';
import '../see_all_screen.dart';
import 'desktop_hero_banner.dart';
import 'desktop_media_row.dart';

/// Full-screen desktop home screen modeled on the Netflix desktop experience:
/// Full-bleed cinematic hero banner at the top, followed by horizontal
/// media rows with hover pagination arrows and smooth mouse scrolling.
class DesktopHomeScreen extends StatefulWidget {
  const DesktopHomeScreen({super.key});

  @override
  State<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends State<DesktopHomeScreen> {
  final HomeCubit _homeCubit = sl<HomeCubit>();

  @override
  void initState() {
    super.initState();
    if (_homeCubit.state.sections == null) {
      _homeCubit.load();
    }
  }

  void _openDetail(MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetailScreen(item: item),
      ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: BlocBuilder<HomeCubit, HomeState>(
        bloc: _homeCubit,
        builder: (context, state) {
          final sections = state.sections;

          if (state.loading && (sections == null || sections.isEmpty)) {
            return Center(
              child: CircularProgressIndicator(
                color: AppColors.accent,
                strokeWidth: 2.5,
              ),
            );
          }

          if (sections == null || sections.isEmpty) {
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
                    'No content available',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => _homeCubit.load(reset: true),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      side: BorderSide(color: AppColors.accent),
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          // Drive Hero banner from the first item of the first section
          final featuredItem = state.heroItems.isNotEmpty
              ? state.heroItems.first
              : sections.first.items.firstOrNull;

          return CustomScrollView(
            slivers: [
              // ── Hero Banner ───────────────────────────────
              if (featuredItem != null)
                SliverToBoxAdapter(
                  child: DesktopHeroBanner(
                    item: featuredItem,
                    onPlay: () => _openDetail(featuredItem),
                    onMoreInfo: () => _openDetail(featuredItem),
                  ),
                ),

              // ── Horizontal Content Rows ───────────────────
              SliverPadding(
                padding: const EdgeInsets.only(top: 8, bottom: 48),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final section = sections[index];
                      return DesktopMediaRow(
                        title: section.title,
                        items: section.items,
                        onTap: _openDetail,
                        onSeeAll: () => _openSeeAll(section),
                      );
                    },
                    childCount: sections.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
