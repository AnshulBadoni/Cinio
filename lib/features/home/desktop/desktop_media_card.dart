import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/models/media_item.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';

/// Reusable high-performance desktop media card adhering to the Netflix
/// desktop concept: 1.05x hover scale, snappy 120ms animation, downscaled
/// memory cache (memCacheWidth/memCacheHeight) to eliminate GPU/RAM stutter,
/// and clean typography.
class DesktopMediaCard extends StatefulWidget {
  const DesktopMediaCard({
    super.key,
    required this.item,
    required this.onTap,
    this.width = 175,
    this.height = 260,
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

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _hovered
                    ? Colors.white.withValues(alpha: 0.8)
                    : Colors.white.withValues(alpha: 0.06),
                width: _hovered ? 1.5 : 1,
              ),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.65),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ── Poster Image ──────────────────────────────────
                if (cover != null && cover.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: cover,
                    fit: BoxFit.cover,
                    memCacheWidth: 350,
                    memCacheHeight: 520,
                    fadeInDuration: const Duration(milliseconds: 120),
                    placeholder: (_, _) => Container(
                      color: AppColors.surface,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ),
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

                // ── Bottom Gradient Vignette ──────────────────────
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.55, 0.82, 1.0],
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.6),
                          Colors.black.withValues(alpha: 0.95),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Hover Play Indicator ──────────────────────────
                if (_hovered)
                  Center(
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.black,
                        size: 28,
                      ),
                    ),
                  ),

                // ── Title & Meta Text ─────────────────────────────
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          shadows: const [
                            Shadow(color: Colors.black, blurRadius: 4),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (item.rating != null && item.rating! > 0) ...[
                            const Icon(
                              Icons.star_rounded,
                              size: 13,
                              color: Color(0xFFFFB800),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              item.rating!.toStringAsFixed(1),
                              style: AppText.caption.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (item.year != null && item.year!.isNotEmpty)
                            Text(
                              item.year!,
                              style: AppText.caption.copyWith(
                                fontSize: 11,
                                color: AppColors.textTertiary,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
