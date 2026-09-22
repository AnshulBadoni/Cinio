import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/di/injector.dart';
import '../../core/mode/content_mode.dart';
import '../../core/mode/content_mode_cubit.dart';
import '../../core/models/provider_info.dart';
import '../../core/playback/watch_history.dart';
import '../../core/reading/read_history.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/content_row.dart';
import '../../core/ui/continue_card.dart';
import '../../core/ui/poster_card.dart';

/// Home's "Continue Watching" / "Continue Reading" sliver. Anime mode renders
/// the original [WatchHistory]-backed row exactly as before; reading modes
/// (manga/novel) swap in a [ReadHistory]-backed row with the same card chrome.
/// Split out of [_HomeView] purely so it's independently widget-testable —
/// the surrounding Home screen carries update-check/network side effects that
/// have no place in this row's tests.
///
/// Reactive to [ContentModeCubit] (not just re-read once) so flipping modes
/// from Home's own header swaps the row immediately, even when the mode
/// switch doesn't also change the active source (which is what normally
/// triggers a HomeCubit rebuild).
///
/// This widget is just the thin reactive shell (Hive box guard +
/// ValueListenableBuilder); the actual row chrome lives in
/// [ContinueWatchingRow] / [ContinueReadingRow] below, split out so tests can
/// pump the rendered content directly against a resolved list instead of a
/// live Hive box.
class ContinueSection extends StatelessWidget {
  const ContinueSection({
    super.key,
    required this.loggedIn,
    required this.onResume,
    required this.onLongPress,
    required this.onSeeAll,
    required this.onResumeReading,
    required this.onLongPressReading,
  });

  final bool loggedIn;
  final void Function(HistoryEntry) onResume;
  final void Function(HistoryEntry) onLongPress;
  final VoidCallback onSeeAll;
  final void Function(ReadEntry) onResumeReading;
  final void Function(ReadEntry) onLongPressReading;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ContentModeCubit, ContentMode>(
      bloc: sl<ContentModeCubit>(),
      builder: (context, mode) =>
          mode.isReading ? _readingRow(mode) : _watchingRow(),
    );
  }

  // ── Continue Watching (anime / movie / series) ─────────────────────────────

  Widget _watchingRow() {
    if (!(loggedIn && Hive.isBoxOpen(WatchHistory.boxName))) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return ValueListenableBuilder(
      valueListenable: Hive.box<Map>(WatchHistory.boxName).listenable(),
      builder: (context, _, _) => ContinueWatchingRow(
        history: sl<WatchHistory>().recent(),
        onSeeAll: onSeeAll,
        onResume: onResume,
        onLongPress: onLongPress,
      ),
    );
  }

  // ── Continue Reading (manga/novel) ────────────────────────────────────────

  Widget _readingRow(ContentMode mode) {
    if (!(loggedIn && Hive.isBoxOpen(ReadHistory.boxName))) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final type = mode == ContentMode.manga
        ? ProviderType.manga
        : ProviderType.novel;
    return ValueListenableBuilder(
      valueListenable: Hive.box<Map>(ReadHistory.boxName).listenable(),
      builder: (context, _, _) => ContinueReadingRow(
        history: sl<ReadHistory>().recent(type: type),
        onResumeReading: onResumeReading,
        onLongPress: onLongPressReading,
        onSeeAll: onSeeAll,
      ),
    );
  }
}

/// Continue Watching row using standard portrait poster cards identical in size
/// and styling to Trending / Popular / New Releases rows.
class ContinueWatchingRow extends StatelessWidget {
  const ContinueWatchingRow({
    super.key,
    required this.history,
    required this.onSeeAll,
    required this.onResume,
    required this.onLongPress,
  });

  final List<HistoryEntry> history;
  final VoidCallback onSeeAll;
  final void Function(HistoryEntry) onResume;
  final void Function(HistoryEntry) onLongPress;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: ContentRow(
          title: 'Continue Watching',
          itemWidth: 140,
          itemHeight: 236,
          onSeeAll: onSeeAll,
          itemCount: history.length,
          itemBuilder: (c, i) {
            final e = history[i];
            return _ContinueWatchingPosterCard(
              entry: e,
              onTap: () => onResume(e),
              onLongPress: () => onLongPress(e),
            );
          },
        ),
      ),
    );
  }
}

/// Portrait PosterCard wrapper with a centered circular progress & resume overlay.
class _ContinueWatchingPosterCard extends StatelessWidget {
  const _ContinueWatchingPosterCard({
    required this.entry,
    required this.onTap,
    required this.onLongPress,
  });

  final HistoryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Episode badge for episodic series. Movies (no episodeNumber) return null.
  String? _episodeBadge(HistoryEntry entry) {
    final epNum = entry.episodeNumber;
    if (epNum != null && epNum > 0) {
      return 'EP ${epNum.toInt()}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PosterCard(
          title: entry.showTitle,
          imageUrl: entry.cover,
          headers: entry.coverHeaders,
          cellWidth: 140,
          qualityBadge: _episodeBadge(entry),
          onTap: onTap,
          onLongPress: onLongPress,
        ),
        // Playback progress ring centered over the poster image area (~190px height)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 190,
          child: IgnorePointer(
            child: Center(
              child: _ResumePlayIndicator(progress: entry.progress),
            ),
          ),
        ),
      ],
    );
  }
}

/// Circular playback progress ring with a centered play triangle and translucent backplate.
class _ResumePlayIndicator extends StatelessWidget {
  const _ResumePlayIndicator({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    const double size = 44.0;
    const double strokeWidth = 3.0;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Translucent dark disc for contrast over any poster art
          Container(
            width: size - strokeWidth * 2,
            height: size - strokeWidth * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.55),
            ),
          ),
          // Circular progress ring representing entry.progress
          CircularProgressIndicator(
            value: progress.clamp(0.0, 1.0).toDouble(),
            strokeWidth: strokeWidth,
            strokeCap: StrokeCap.round,
            backgroundColor: Colors.white.withValues(alpha: 0.25),
            color: AppColors.accent,
          ),
          // Centered play triangle (offset slightly right for optical balance)
          const Padding(
            padding: EdgeInsets.only(left: 2.0),
            child: Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

/// Continue Reading row content, given an already-resolved [history] list —
/// no Hive access of its own.
class ContinueReadingRow extends StatelessWidget {
  const ContinueReadingRow({
    super.key,
    required this.history,
    required this.onResumeReading,
    this.onLongPress,
    this.onSeeAll,
  });

  final List<ReadEntry> history;
  final void Function(ReadEntry) onResumeReading;
  final void Function(ReadEntry)? onLongPress;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: ContentRow(
          title: 'Continue Reading',
          itemWidth: 236,
          itemHeight: 76,
          onSeeAll: onSeeAll,
          itemCount: history.length,
          itemBuilder: (c, i) {
            final e = history[i];
            final progress = e.total > 0
                ? (e.pos / e.total).clamp(0.0, 1.0)
                : 0.0;
            return ContinueReadingCard(
              title: e.title,
              imageUrl: e.cover,
              headers: e.coverHeaders,
              progress: progress,
              subtitle: e.chapterNumber != null
                  ? 'Chapter ${e.chapterNumber!.toInt()}'
                  : null,
              onTap: () => onResumeReading(e),
              onLongPress: onLongPress == null ? null : () => onLongPress!(e),
            );
          },
        ),
      ),
    );
  }
}
