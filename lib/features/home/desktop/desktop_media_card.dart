import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/models/media_item.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';

/// Landscape 16:9 desktop media card. Mobile and TV cards are untouched.
class DesktopMediaCard extends StatefulWidget {
  const DesktopMediaCard({
    super.key,
    required this.item,
    required this.onTap,
    this.width = 290,
    this.height = 163,
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
          scale: _hovered ? 1.025 : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: widget.width,
            height: widget.height,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _hovered
                    ? Colors.white.withValues(alpha: 0.24)
                    : Colors.white.withValues(alpha: 0.05),
              ),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.55),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (cover != null && cover.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: cover,
                    fit: BoxFit.cover,
                    memCacheWidth: (widget.width * 2).round(),
                    memCacheHeight: (widget.height * 2).round(),
                    fadeInDuration: const Duration(milliseconds: 120),
                    placeholder: (_, _) => Container(color: AppColors.surface),
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

                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.32, 0.68, 1],
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.2),
                          Colors.black.withValues(alpha: 0.92),
                        ],
                      ),
                    ),
                  ),
                ),

                if (_hovered)
                  Center(
                    child: AnimatedOpacity(
                      opacity: _hovered ? 1 : 0,
                      duration: const Duration(milliseconds: 100),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.black,
                          size: 28,
                        ),
                      ),
                    ),
                  ),

                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 10,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.body.copyWith(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                shadows: const [
                                  Shadow(color: Colors.black, blurRadius: 5),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (item.rating != null && item.rating! > 0) ...[
                                  const Icon(
                                    Icons.star_rounded,
                                    size: 13,
                                    color: Color(0xFFFFC400),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    item.rating!.toStringAsFixed(1),
                                    style: AppText.caption.copyWith(
                                      color: Colors.white.withValues(alpha: 0.9),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                                if (item.year != null && item.year!.isNotEmpty) ...[
                                  const SizedBox(width: 7),
                                  Text(
                                    item.year!,
                                    style: AppText.caption.copyWith(
                                      color: Colors.white.withValues(alpha: 0.62),
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedOpacity(
                        opacity: _hovered ? 1 : 0,
                        duration: const Duration(milliseconds: 120),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.58),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            size: 18,
                            color: Colors.white,
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
    );
  }
}
