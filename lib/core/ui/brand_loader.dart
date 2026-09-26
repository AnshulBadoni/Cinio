import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../di/injector.dart';
import '../metadata/title_logo_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'cinio_title_style.dart';

/// Cinematic progressive title loader.
///
/// Features:
/// - Official logo support: Renders the movie/series stylized title PNG logo if
///   available (from TMDB / TitleLogoService), with dimmed base + progressive fill.
/// - Fallback typographic style: If no logo image exists, renders the title in its
///   distinct cinematic typographic identity (inspired by Breaking Bad, Batman,
///   Slow Horses, Squid Game, etc.).
/// - Fill layer: The exact title/logo in vibrant color, revealed via a horizontal
///   clip mask according to [progress] (or smooth gentle breathing opacity pulse).
/// - Contextual status: Displays [label] ("Finding best source…") or live stream
///   telemetry ([speed] • [buffered] • [quality]) with clean dot separators.
class BrandLoader extends StatefulWidget {
  const BrandLoader({
    super.key,
    this.title,
    this.logoUrl,
    this.tmdbId,
    this.tmdbIsTv = false,
    this.label,
    this.speed,
    this.buffered,
    this.quality,
    this.progress,
    this.fontSize = 24.7,
  });

  final String? title;
  final String? logoUrl;
  final int? tmdbId;
  final bool tmdbIsTv;
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

  String? _resolvedLogo;

  @override
  void initState() {
    super.initState();
    _resolvedLogo = widget.logoUrl;
    if (_resolvedLogo == null || _resolvedLogo!.isEmpty) {
      _fetchLogo();
    }
  }

  Future<void> _fetchLogo() async {
    if (!sl.isRegistered<TitleLogoService>()) return;
    final title = widget.title?.trim() ?? '';
    if (title.isEmpty && widget.tmdbId == null) return;
    try {
      final url = await sl<TitleLogoService>().logoForDetail(
        title: title,
        tmdbId: widget.tmdbId,
        isTv: widget.tmdbIsTv,
      );
      if (mounted && url != null && url.isNotEmpty) {
        setState(() => _resolvedLogo = url);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logo = _resolvedLogo?.trim();
    if (logo != null && logo.isNotEmpty) {
      return _buildLogoLoader(logo);
    }

    final title = widget.title?.trim();
    if (title != null && title.isNotEmpty) {
      return _buildTitleLoader(title);
    }
    return _buildFallbackLoader();
  }

  String _statusLine() {
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
    return parts.isNotEmpty
        ? parts.join('  •  ')
        : (widget.label?.trim().isNotEmpty ?? false)
            ? widget.label!.trim()
            : '';
  }

  Widget _buildLogoLoader(String logoUrl) {
    final statusText = _statusLine();

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
                    // Base Dimmed Logo Layer
                    Opacity(
                      opacity: 0.22,
                      child: CachedNetworkImage(
                        imageUrl: logoUrl,
                        height: 72,
                        fit: BoxFit.contain,
                        errorWidget: (_, __, ___) =>
                            _buildTitleLoader(widget.title ?? ''),
                      ),
                    ),
                    // Active Filled Logo Layer (Clipped Horizontally)
                    ClipRect(
                      clipper: _HorizontalFillClipper(fillFactor),
                      child: CachedNetworkImage(
                        imageUrl: logoUrl,
                        height: 72,
                        fit: BoxFit.contain,
                        errorWidget: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ],
                );
              }

              // Indeterminate breathing pulse
              final pulse =
                  0.35 + 0.65 * (0.5 + 0.5 * math.sin(_c.value * 2 * math.pi));
              return Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: 0.18,
                    child: CachedNetworkImage(
                      imageUrl: logoUrl,
                      height: 72,
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) =>
                          _buildTitleLoader(widget.title ?? ''),
                    ),
                  ),
                  Opacity(
                    opacity: pulse.clamp(0.0, 1.0),
                    child: CachedNetworkImage(
                      imageUrl: logoUrl,
                      height: 72,
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ],
              );
            },
          ),
          if (statusText.isNotEmpty) ...[
            const SizedBox(height: 16),
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
    final statusText = _statusLine();

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

              // Indeterminate: Gentle breathing opacity pulse
              final pulse =
                  0.35 + 0.55 * (0.5 + 0.5 * math.sin(_c.value * 2 * math.pi));
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
                    Text(
                      'CINIO',
                      style: AppText.display.copyWith(
                        fontFamily: 'Montserrat',
                        fontSize: widget.fontSize,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4.0,
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    ClipRect(
                      clipper: _HorizontalFillClipper(fillFactor),
                      child: Text(
                        'CINIO',
                        style: AppText.display.copyWith(
                          fontFamily: 'Montserrat',
                          fontSize: widget.fontSize,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4.0,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ],
                );
              }

              final pulse =
                  0.35 + 0.55 * (0.5 + 0.5 * math.sin(_c.value * 2 * math.pi));
              return Opacity(
                opacity: pulse.clamp(0.0, 1.0),
                child: Text(
                  'CINIO',
                  style: AppText.display.copyWith(
                    fontFamily: 'Montserrat',
                    fontSize: widget.fontSize,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4.0,
                    color: AppColors.accent,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            statusText,
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
    return Rect.fromLTWH(0, 0, size.width * factor, size.height);
  }

  @override
  bool shouldReclip(covariant _HorizontalFillClipper oldClipper) =>
      oldClipper.factor != factor;
}
