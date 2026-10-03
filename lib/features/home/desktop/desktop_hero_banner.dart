import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/models/media_item.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';

/// Full-bleed cinematic desktop hero.
///
/// This is intentionally desktop-only: phone/TV hero implementations remain
/// untouched. The artwork does most of the visual work, while the lower and
/// left scrims let the content rows feel like they grow naturally out of the
/// hero instead of ending at a hard edge.
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
    final width = MediaQuery.sizeOf(context).width;
    final heroHeight = (width * 0.43).clamp(520.0, 650.0).toDouble();

    return SizedBox(
      height: heroHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (backdrop != null && backdrop.isNotEmpty)
            CachedNetworkImage(
              imageUrl: backdrop,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              fadeInDuration: const Duration(milliseconds: 220),
              placeholder: (_, _) => Container(color: AppColors.bg),
              errorWidget: (_, _, _) => Container(color: AppColors.bg),
            )
          else
            Container(color: AppColors.bg),

          // Keep the artwork strong on the right while making the copy area
          // readable without a visible rectangular overlay.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: const [0.0, 0.34, 0.62, 1.0],
                  colors: [
                    Colors.black.withValues(alpha: 0.82),
                    Colors.black.withValues(alpha: 0.48),
                    Colors.black.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Strong bottom fade — the hero should visually melt into the rows.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.46, 0.72, 0.9, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.18),
                    AppColors.bg.withValues(alpha: 0.78),
                    AppColors.bg,
                  ],
                ),
              ),
            ),
          ),

          // Quiet top vignette behind the global desktop nav.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 150,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.58),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            left: 56,
            bottom: 78,
            right: 40,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _metaLabel('CINIO ORIGINAL', accent: true),
                      if (item.year != null && item.year!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _metaLabel(item.year!),
                      ],
                      if (item.rating != null && item.rating! > 0) ...[
                        const SizedBox(width: 12),
                        const Icon(Icons.star_rounded,
                            size: 16, color: Color(0xFFFFC400)),
                        const SizedBox(width: 4),
                        Text(
                          item.rating!.toStringAsFixed(1),
                          style: AppText.caption.copyWith(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 46,
                      fontWeight: FontWeight.w800,
                      height: 1.03,
                      letterSpacing: -1.1,
                      shadows: [
                        Shadow(
                          color: Colors.black,
                          blurRadius: 18,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Watch now on Cinio with multiple streaming sources, high resolution playback, and custom subtitle support.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body.copyWith(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 14,
                      height: 1.45,
                      shadows: const [
                        Shadow(color: Colors.black, blurRadius: 8),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      _PlayButton(onTap: onPlay),
                      const SizedBox(width: 10),
                      _IconButton(
                        icon: Icons.info_outline_rounded,
                        label: 'More info',
                        onTap: onMoreInfo,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaLabel(String text, {bool accent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent
            ? AppColors.accent.withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
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
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
          decoration: BoxDecoration(
            color: _hovered ? Colors.white.withValues(alpha: 0.9) : Colors.white,
            borderRadius: BorderRadius.circular(7),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow_rounded, color: Colors.black, size: 24),
              SizedBox(width: 7),
              Text(
                'Play',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 15,
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

class _IconButton extends StatefulWidget {
  const _IconButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
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
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, color: Colors.white, size: 20),
              const SizedBox(width: 7),
              Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
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
