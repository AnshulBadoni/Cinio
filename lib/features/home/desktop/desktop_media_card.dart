import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/di/injector.dart';
import '../../../core/metadata/tmdb.dart';
import '../../../core/models/media_item.dart';
import '../../../core/playback/resume_store.dart';
import '../../../core/playback/watch_history.dart';
import '../../../core/theme/app_colors.dart';

/// Desktop media card with two intentional visual variants:
/// - portrait: 2:3 poster
/// - landscape: 16:9 backdrop-style tile
///
/// Artwork is always kept at its native aspect ratio by using BoxFit.cover.
/// A landscape row must therefore use landscape artwork when available; this
/// widget never stretches a poster to fill the landscape tile.
class DesktopMediaCard extends StatefulWidget {
  const DesktopMediaCard({
    super.key,
    required this.item,
    required this.onTap,
    this.width = 165,
    this.height = 275,
    this.landscape = false,
    this.showTitle = true,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final double width;
  final double height;
  final bool landscape;
  final bool showTitle;

  @override
  State<DesktopMediaCard> createState() => _DesktopMediaCardState();
}

class _DesktopMediaCardState extends State<DesktopMediaCard> {
  static final Map<String, String> _backdropCache = {};
  bool _hovered = false;
  String? _fetchedBackdrop;

  @override
  void initState() {
    super.initState();
    if (widget.landscape &&
        (widget.item.heroImage == null || widget.item.heroImage!.isEmpty)) {
      _resolveLandscapeBackdrop();
    }
  }

  @override
  void didUpdateWidget(covariant DesktopMediaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.landscape &&
        widget.item.id != oldWidget.item.id &&
        (widget.item.heroImage == null || widget.item.heroImage!.isEmpty)) {
      _resolveLandscapeBackdrop();
    }
  }

  Future<void> _resolveLandscapeBackdrop() async {
    final item = widget.item;
    if (_backdropCache.containsKey(item.id)) {
      setState(() => _fetchedBackdrop = _backdropCache[item.id]);
      return;
    }
    final tmdbId = item.tmdbId;
    if (tmdbId != null && tmdbId > 0) {
      try {
        final dio = sl<Dio>();
        final path = item.tmdbIsTv ? 'tv/$tmdbId' : 'movie/$tmdbId';
        final res = await dio.get<Map<String, dynamic>>(
          'https://${Tmdb.host}/3/$path',
          queryParameters: {'api_key': Tmdb.apiKey},
        );
        final bg = res.data?['backdrop_path']?.toString();
        if (bg != null && bg.isNotEmpty) {
          final url = '${Tmdb.img}/w780$bg';
          _backdropCache[item.id] = url;
          if (mounted) setState(() => _fetchedBackdrop = url);
          return;
        }
      } catch (_) {}
    }

    // Fallback: search TMDB by title to find real 16:9 backdrop
    try {
      final dio = sl<Dio>();
      final cleanTitle = item.englishTitle ?? item.title;
      final res = await dio.get<Map<String, dynamic>>(
        'https://${Tmdb.host}/3/search/multi',
        queryParameters: {
          'api_key': Tmdb.apiKey,
          'query': cleanTitle,
        },
      );
      final results = res.data?['results'] as List?;
      if (results != null && results.isNotEmpty) {
        for (final r in results) {
          if (r is Map && r['backdrop_path'] != null) {
            final bg = r['backdrop_path'].toString();
            if (bg.isNotEmpty) {
              final url = '${Tmdb.img}/w780$bg';
              _backdropCache[item.id] = url;
              if (mounted) setState(() => _fetchedBackdrop = url);
              return;
            }
          }
        }
      }
    } catch (_) {}
  }

  bool _isWatched() {
    if (sl.isRegistered<WatchHistory>()) {
      try {
        final all = sl<WatchHistory>().all();
        final itemTitle = widget.item.title.trim().toLowerCase();
        for (final entry in all) {
          final matchesId = entry.showId == widget.item.id;
          final matchesTitle = entry.showTitle.trim().toLowerCase() == itemTitle;
          if (matchesId || matchesTitle) {
            if (entry.finished || entry.progress >= 0.90) return true;
          }
        }
      } catch (_) {}
    }
    if (sl.isRegistered<ResumeStore>()) {
      try {
        final resume = sl<ResumeStore>();
        final mark = resume.get(widget.item.sourceId, widget.item.url, widget.item.id);
        if (mark != null && mark.finished) return true;
      } catch (_) {}
    }
    return false;
  }

  double? _progress() {
    if (!sl.isRegistered<WatchHistory>()) return null;
    try {
      final recent = sl<WatchHistory>().recent(limit: 30);
      for (final entry in recent) {
        if (entry.showId == widget.item.id) return entry.progress;
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final landscapeUrl = item.heroImage != null && item.heroImage!.isNotEmpty
        ? item.heroImage
        : (_fetchedBackdrop ?? _backdropCache[item.id]);

    // For landscape cards, ONLY use genuine landscape art (never stretch a tall 2:3 cover)
    final imageUrl = widget.landscape
        ? landscapeUrl
        : (item.cover != null && item.cover!.isNotEmpty
            ? item.cover
            : item.heroImage);
    final progress = _progress();
    final isWatched = _isWatched();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.width,
          height: widget.height + (widget.showTitle ? 48 : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: widget.width,
                height: widget.height,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.landscape ? 10 : 8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (imageUrl != null && imageUrl.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: widget.landscape ? 640 : 360,
                          memCacheHeight: widget.landscape ? 360 : 560,
                          fadeInDuration: const Duration(milliseconds: 120),
                          placeholder: (_, _) =>
                              Container(color: AppColors.surface),
                          errorWidget: (_, _, _) => Container(
                            color: AppColors.surface,
                            child: const Icon(
                              Icons.broken_image_rounded,
                              color: AppColors.textTertiary,
                              size: 30,
                            ),
                          ),
                        )
                      else if (widget.landscape && item.cover != null && item.cover!.isNotEmpty)
                        // Never stretch tall poster: show darkened blurred backdrop with centered poster
                        Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: item.cover!,
                              fit: BoxFit.cover,
                              memCacheWidth: 640,
                              placeholder: (_, _) => Container(color: AppColors.surface),
                              errorWidget: (_, _, _) => Container(color: AppColors.surface),
                            ),
                            Positioned.fill(
                              child: Container(color: Colors.black.withValues(alpha: 0.65)),
                            ),
                            Center(
                              child: CachedNetworkImage(
                                imageUrl: item.cover!,
                                fit: BoxFit.contain,
                                memCacheHeight: 360,
                              ),
                            ),
                          ],
                        )
                      else
                        Container(
                          color: AppColors.surface,
                          child: const Icon(
                            Icons.movie_rounded,
                            color: AppColors.textTertiary,
                            size: 34,
                          ),
                        ),

                      // A restrained readability gradient, not a glow.
                      if (widget.landscape)
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Color(0xCC000000),
                                ],
                              ),
                            ),
                          ),
                        ),

                      if (_hovered)
                        Positioned.fill(
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.28),
                          ),
                        ),

                      if (_hovered)
                        Center(
                          child: Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.94),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.black,
                              size: 27,
                            ),
                          ),
                        ),

                      // Watched checkmark badge on top-left (matching reference)
                      if (isWatched)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C5CFC),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.50),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1.5),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                          ),
                        )
                      else if (item.subCount != null && item.subCount! > 0)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: _Badge('+${item.subCount}'),
                        )
                      else if (item.quality != null && item.quality!.isNotEmpty)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: _Badge(item.quality!),
                        ),

                      if (progress != null && progress > 0)
                        Positioned(
                          left: 9,
                          right: 9,
                          bottom: 7,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: SizedBox(
                              height: 3,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: ColoredBox(
                                      color: Colors.white.withValues(alpha: 0.30),
                                    ),
                                  ),
                                  FractionallySizedBox(
                                    widthFactor: progress.clamp(0.0, 1.0),
                                    child: ColoredBox(color: AppColors.accent),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      if (widget.landscape)
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: progress != null && progress > 0 ? 16 : 10,
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (widget.showTitle) ...[
                const SizedBox(height: 8),
                if (!widget.landscape)
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (!widget.landscape) ...[
                  const SizedBox(height: 3),
                  Text(
                    _metadata(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.52),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _metadata(MediaItem item) {
    final parts = <String>[];
    if (item.year != null && item.year!.isNotEmpty) parts.add(item.year!);
    if (item.rating != null && item.rating! > 0) {
      parts.add('★ ${item.rating!.toStringAsFixed(1)}');
    }
    return parts.join(' · ');
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
