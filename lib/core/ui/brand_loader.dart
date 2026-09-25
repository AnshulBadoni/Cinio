import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'cinio_title_style.dart';

/// Cinematic progressive title loader.
///
/// Features:
/// - Base layer: Title in its distinct cinematic typographic style, dimmed (translucent).
/// - Fill layer: The exact title in vibrant solid/gradient color, revealed via a horizontal
///   clip mask according to [progress] (or smooth gentle opacity pulse when indeterminate).
/// - Contextual status: Displays [label] ("Finding best source…") or live stream
///   telemetry ([speed] • [buffered] • [quality]) with clean dot separators and NO emojis/glow.
/// - No separate loader bar line: The title itself is the progress visual.
class BrandLoader extends StatefulWidget {
  const BrandLoader({
    super.key,
    this.title,
    this.label,
    this.speed,
    this.buffered,
    this.quality,
    this.progress,
    this.fontSize = 26.0,
  });

  final String? title;
  final String? label;
  final String? speed;
  final String? buffered;
  final String? quality;
  final double? progress;
  final double fontSize;

  @override
  State<BrandLoader> createState() => _BrandLoaderState();
}

class _BrandLoaderState extends State<BrandLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title?.trim();
    if (title != null && title.isNotEmpty) {
      return _buildTitleLoader(title);
    }
    return _buildFallbackLoader();
  }

  Widget _buildTitleLoader(String title) {
    final preset = CinioTitleStyle.presetFor(title);
    final cfg = CinioTitleStyle.configFor(
      preset: preset,
      accent: AppColors.accent,
      fontSize: widget.fontSize,
    );

    final displayTitle = cfg.uppercase ? title.toUpperCase() : title;
    final cleanShadows = const [
      Shadow(color: Color(0x99000000), offset: Offset(0, 2), blurRadius: 4),
    ];

    // Status / telemetry text
    final parts = <String>[];
    if (widget.speed != null && widget.speed!.trim().isNotEmpty) {
      parts.add(widget.speed!.trim());
    }
    if (widget.buffered != null && widget.buffered!.trim().isNotEmpty) {
      parts.add('${widget.buffered!.trim()} buffered');
    }
    if (widget.quality != null && widget.quality!.trim().isNotEmpty) {
      parts.add(widget.quality!.trim());
    }
    final statusText = parts.isNotEmpty
        ? parts.join('  •  ')
        : (widget.label?.trim().isNotEmpty ?? false)
            ? widget.label!.trim()
            : '';

    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              if (widget.progress != null) {
                final fillFactor = widget.progress!.clamp(0.0, 1.0);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Base Dimmed Title Layer
                    Text(
                      displayTitle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: cfg.baseStyle.copyWith(
                        color: Colors.white.withValues(alpha: 0.22),
                        shadows: cleanShadows,
                      ),
                    ),

                    // Active Filled Title Layer (Clipped Horizontally)
                    ClipRect(
                      clipper: _HorizontalFillClipper(fillFactor),
                      child: ShaderMask(
                        shaderCallback: (bounds) =>
                            cfg.gradient.createShader(bounds),
                        child: Text(
                          displayTitle,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: cfg.baseStyle.copyWith(
                            color: Colors.white,
                            shadows: cleanShadows,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              // Indeterminate (finding source): Gentle breathing opacity pulse without clipping wipes
              final pulse = 0.35 + 0.55 * (0.5 + 0.5 * math.sin(_c.value * 2 * math.pi));
              return Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    displayTitle,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: cfg.baseStyle.copyWith(
                      color: Colors.white.withValues(alpha: 0.18),
                      shadows: cleanShadows,
                    ),
                  ),
                  Opacity(
                    opacity: pulse.clamp(0.0, 1.0),
                    child: ShaderMask(
                      shaderCallback: (bounds) =>
                          cfg.gradient.createShader(bounds),
                      child: Text(
                        displayTitle,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: cfg.baseStyle.copyWith(
                          color: Colors.white,
                          shadows: cleanShadows,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          if (statusText.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              statusText,
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFallbackLoader() {
    final statusText = (widget.label?.trim().isNotEmpty ?? false)
        ? widget.label!.trim()
        : 'Loading…';

    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              if (widget.progress != null) {
                final fillFactor = widget.progress!.clamp(0.0, 1.0);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      'CINIO',
                      textAlign: TextAlign.center,
                      style: AppText.display.copyWith(
                        fontSize: widget.fontSize,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    ClipRect(
                      clipper: _HorizontalFillClipper(fillFactor),
                      child: Text(
                        'CINIO',
                        textAlign: TextAlign.center,
                        style: AppText.display.copyWith(
                          fontSize: widget.fontSize,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ],
                );
              }

              final pulse = 0.35 + 0.55 * (0.5 + 0.5 * math.sin(_c.value * 2 * math.pi));
              return Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    'CINIO',
                    textAlign: TextAlign.center,
                    style: AppText.display.copyWith(
                      fontSize: widget.fontSize,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  Opacity(
                    opacity: pulse.clamp(0.0, 1.0),
                    child: Text(
                      'CINIO',
                      textAlign: TextAlign.center,
                      style: AppText.display.copyWith(
                        fontSize: widget.fontSize,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Text(
            statusText,
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _HorizontalFillClipper extends CustomClipper<Rect> {
  const _HorizontalFillClipper(this.factor);
  final double factor;

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * factor.clamp(0.0, 1.0), size.height);
  }

  @override
  bool shouldReclip(covariant _HorizontalFillClipper oldClipper) =>
      oldClipper.factor != factor;
}
