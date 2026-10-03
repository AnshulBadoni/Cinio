import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/models/media_item.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';

/// Cinematic widescreen desktop hero banner modeled directly on the
/// Netflix desktop concept: high-impact backdrop, smooth fade vignettes,
/// title typography, tags, and solid Play + frosted More Info buttons.
class DesktopHeroBanner extends StatelessWidget {
  const DesktopHeroBanner({
    super.key,
    required this.item,
    required this.onPlay,
    required this.onMoreInfo,
  });

  final MediaItem item;
  final VoidCallback onPlay;
  final VoidCallback onMoreInfo;

  @override
  Widget build(BuildContext context) {
    final backdrop = item.cover;

    return SizedBox(
      height: 540,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Backdrop Artwork ──────────────────────────────
          if (backdrop != null && backdrop.isNotEmpty)
            CachedNetworkImage(
              imageUrl: backdrop,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              fadeInDuration: const Duration(milliseconds: 200),
              placeholder: (_, _) => Container(color: AppColors.surface),
              errorWidget: (_, _, _) => Container(color: AppColors.surface),
            )
          else
            Container(color: AppColors.surface),

          // ── Cinematic Vignettes (Left & Bottom) ───────────
          // 1. Left-to-right fade for text readability
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: const [0.0, 0.45, 0.85],
                  colors: [
                    AppColors.bg.withValues(alpha: 0.96),
                    AppColors.bg.withValues(alpha: 0.65),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // 2. Bottom fade to blend seamlessly into content rows
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.5, 0.82, 1.0],
                  colors: [
                    Colors.transparent,
                    AppColors.bg.withValues(alpha: 0.7),
                    AppColors.bg,
                  ],
                ),
              ),
            ),
          ),

          // 3. Top subtle vignette for navigation bar contrast
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 120,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── Hero Content (Title, Badges, Overview, CTAs) ──
          Positioned(
            left: 48,
            bottom: 60,
            width: 580,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Tag Badges
                Row(
                  children: [
                    _badge('FEATURED', isAccent: true),
                    const SizedBox(width: 8),
                    if (item.year != null && item.year!.isNotEmpty)
                      _badge(item.year!),
                    const SizedBox(width: 8),
                    if (item.rating != null && item.rating! > 0) ...[
                      const Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: Color(0xFFFFB800),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.rating!.toStringAsFixed(1),
                        style: AppText.caption.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 14),

                // Main Title
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.15,
                    letterSpacing: -0.5,
                    shadows: [
                      Shadow(
                        color: Colors.black,
                        blurRadius: 16,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Synopsis
                Text(
                  'Watch now on Cinio with multiple streaming sources, high resolution playback, and custom subtitle support.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body.copyWith(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.4,
                    shadows: const [
                      Shadow(color: Colors.black, blurRadius: 8),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  children: [
                    // Solid White "Play" Button
                    _PlayButton(onTap: onPlay),
                    const SizedBox(width: 14),

                    // Frosted Glass "More Info" Button
                    _MoreInfoButton(onTap: onMoreInfo),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, {bool isAccent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isAccent
            ? AppColors.accent.withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _PlayButton extends StatefulWidget {
  const _PlayButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withValues(alpha: 0.85)
                : Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow_rounded, color: Colors.black, size: 26),
              SizedBox(width: 8),
              Text(
                'Play',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreInfoButton extends StatefulWidget {
  const _MoreInfoButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_MoreInfoButton> createState() => _MoreInfoButtonState();
}

class _MoreInfoButtonState extends State<_MoreInfoButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withValues(alpha: 0.28)
                : Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline_rounded, color: Colors.white, size: 22),
              SizedBox(width: 8),
              Text(
                'More Info',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
