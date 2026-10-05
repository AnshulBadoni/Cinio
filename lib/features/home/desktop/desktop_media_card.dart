import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/di/injector.dart';
import '../../../core/models/media_item.dart';
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
  });

  final MediaItem item;
  final VoidCallback onTap;
  final double width;
  final double height;
  final bool landscape;

  @override
  State<DesktopMediaCard> createState() => _DesktopMediaCardState();
}

class _DesktopMediaCardState extends State<DesktopMediaCard> {
  bool _hovered = false;

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
    final cover = item.cover;
    final progress = _progress();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.width,
          height: widget.height + (widget.landscape ? 48 : 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: widget.width,
                height: widget.height,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.landscape ? 10 : 9),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (cover != null && cover.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: cover,
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

                      if (item.subCount != null && item.subCount! > 0)
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
