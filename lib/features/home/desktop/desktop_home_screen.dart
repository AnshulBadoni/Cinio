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
import 'desktop_top_nav.dart';

class DesktopHomeScreen extends StatefulWidget {
  const DesktopHomeScreen({super.key});

  @override
  State<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends State<DesktopHomeScreen> {
  final HomeCubit _homeCubit = sl<HomeCubit>();
  final ScrollController _scrollController = ScrollController();

  double _navOpacity = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    if (_homeCubit.state.sections == null) {
      _homeCubit.load();
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    final next = (_scrollController.offset / 220).clamp(0.0, 1.0);
    if ((next - _navOpacity).abs() > 0.01) {
      setState(() => _navOpacity = next);
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: BlocBuilder<HomeCubit, HomeState>(
        bloc: _homeCubit,
        builder: (context, state) {
          final sections = state.sections ?? const <HomeSection>[];

          if (state.loading && sections.isEmpty) {
            return const _FullScreenLoader();
          }

          if (sections.isEmpty) {
            // Removed 'const' here because onRetry is a function
            return _EmptyState(onRetry: () => _homeCubit.load(reset: true));
          }

          final featured = state.heroItems.isNotEmpty
              ? state.heroItems.first
              : sections.first.items.firstOrNull;

          return Stack(
            children: [
              Positioned.fill(
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
                  slivers: [
                    if (featured != null)
                      SliverToBoxAdapter(
                        child: DesktopHeroBanner(
                          item: featured,
                          onPlay: () => _openDetail(featured),
                          onMoreInfo: () => _openDetail(featured),
                        ),
                      )
                    else
                      const SliverToBoxAdapter(child: SizedBox(height: 84)),
                    const SliverToBoxAdapter(child: SizedBox(height: 6)),
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
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: DesktopTopNav(opacity: _navOpacity),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Helper Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _FullScreenLoader extends StatelessWidget {
  const _FullScreenLoader();

  @override
  Widget build(BuildContext context) {
    // Removed 'const' from Center because AppColors.accent is not a compile-time constant
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
  // Removed 'const' because onRetry is a VoidCallback (function)
  _EmptyState({required this.onRetry});

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
      padding: const EdgeInsets.fromLTRB(56, 16, 56, 56),
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
            '© ${DateTime.now().year} Streamly. All rights reserved.',
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