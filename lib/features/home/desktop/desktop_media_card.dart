import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/di/injector.dart';
import '../../../core/models/media_item.dart';
import '../../../core/playback/watch_history.dart';
import '../../../core/theme/app_colors.dart';

/// Portrait 2:3 desktop media card matching modern streaming service designs
/// (Netflix/Apple concept, with poster artwork, centered play overlay,
/// resume progress bar, and clean typography underneath).
class DesktopMediaCard extends StatefulWidget {
  const DesktopMediaCard({
    super.key,
    required this.item,
    required this.onTap,
    this.width = 165,
    this.height = 248,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final double width;
  final double height;

  @override
  State<DesktopMediaCard> createState() => _DesktopMediaCardState();
}

class _DesktopMediaCardState extends State<DesktopMediaCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final cover = item.cover;

    // Check if there is watch progress for this item
    double? progress;
    if (sl.isRegistered<WatchHistory>()) {
      try {
        final recent = sl<WatchHistory>().recent(limit: 30);
        for (final entry in recent) {
          if (entry.showId == item.id) {
            progress = entry.progress;
            break;
          }
        }
      } catch (_) {}
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Poster Container ─────────────────────────────────
              AnimatedScale(
                scale: _hovered ? 1.03 : 1.0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: widget.width,
                  height: widget.height,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _hovered
                          ? Colors.white.withValues(alpha: 0.28)
                          : Colors.white.withValues(alpha: 0.08),
                      width: 1,
                    ),
                    boxShadow: _hovered
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.60),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ]
                        : null,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Poster Artwork
                      if (cover != null && cover.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: cover,
                          fit: BoxFit.cover,
                          memCacheWidth: 350,
                          memCacheHeight: 520,
                          fadeInDuration: const Duration(milliseconds: 140),
                          placeholder: (_, _) => Container(color: AppColors.surface),
                          errorWidget: (_, _, _) => Container(
                            color: AppColors.surface,
                            child: const Icon(
                              Icons.broken_image_rounded,
                              color: AppColors.textTertiary,
                              size: 32,
                            ),
                          ),
                        )
                      else
                        Container(
                          color: AppColors.surface,
                          child: const Icon(
                            Icons.movie_rounded,
                            color: AppColors.textTertiary,
                            size: 36,
                          ),
                        ),

                      // Centered Frosted Play Button (matches reference UI)
                      Center(
                        child: AnimatedOpacity(
                          opacity: _hovered ? 1.0 : (progress != null ? 0.85 : 0.0),
                          duration: const Duration(milliseconds: 160),
                          child: AnimatedScale(
                            scale: _hovered ? 1.06 : 0.95,
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.easeOutCubic,
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withValues(alpha: 0.45),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.40),
                                  width: 1.2,
                                ),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Top-left badge (Episode count / Quality)
                      if (item.subCount != null && item.subCount! > 0)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              '+${item.subCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                      else if (item.quality != null && item.quality!.isNotEmpty)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              item.quality!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),

                      // Bottom Resume Progress Bar (matches reference UI like Dahmer & Silo)
                      if (progress != null && progress > 0)
                        Positioned(
                          left: 10,
                          right: 10,
                          bottom: 8,
                          child: Container(
                            height: 3.5,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: progress.clamp(0.0, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 9),

              // ── Title Underneath Card ─────────────────────────────
              Text(
                item.title,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  height: 1.25,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
