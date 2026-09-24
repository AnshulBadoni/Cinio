import 'package:flutter/material.dart';

import '../theme/app_text.dart';

/// Distinct cinematic title styling presets for titles without official logos.
///
/// Deterministically assigned per title (via seed hash), so each movie/series
/// gets a consistent, uniquely stylized typographic identity across Home,
/// Detail, and Search.
enum CinioTitlePreset {
  cinematicGold,
  neonGlow,
  blockbusterTitan,
  editorialModern,
  crimsonImpact,
  cyberEmerald,
  sunsetAmber,
}

class CinioTitleStyle {
  const CinioTitleStyle._();

  static CinioTitlePreset presetFor(Object seed) {
    final hash = seed.hashCode.abs();
    return CinioTitlePreset.values[hash % CinioTitlePreset.values.length];
  }

  static ({
    TextStyle baseStyle,
    Gradient gradient,
    List<Shadow> shadows,
    bool uppercase,
  }) configFor({
    required CinioTitlePreset preset,
    required Color accent,
    double fontSize = 32,
  }) {
    final tunedAccent = _tuneAccent(accent);

    return switch (preset) {
      CinioTitlePreset.cinematicGold => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Montserrat',
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          height: 0.98,
          letterSpacing: -0.6,
        ),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFF7E6),
            Color(0xFFFFD56B),
            Color(0xFFD69324),
          ],
          stops: [0.0, 0.52, 1.0],
        ),
        shadows: const [
          Shadow(color: Color(0xDD000000), offset: Offset(0, 3), blurRadius: 8),
          Shadow(color: Color(0x66000000), offset: Offset(0, 6), blurRadius: 16),
        ],
        uppercase: true,
      ),
      CinioTitlePreset.neonGlow => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Rubik',
          fontSize: fontSize * 0.95,
          fontWeight: FontWeight.w800,
          height: 1.0,
          letterSpacing: 1.0,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            tunedAccent,
            tunedAccent.withValues(alpha: 0.85),
          ],
          stops: const [0.0, 0.65, 1.0],
        ),
        shadows: [
          Shadow(color: tunedAccent.withValues(alpha: 0.80), blurRadius: 14),
          const Shadow(color: Colors.black87, offset: Offset(0, 3), blurRadius: 8),
        ],
        uppercase: true,
      ),
      CinioTitlePreset.blockbusterTitan => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Montserrat',
          fontSize: fontSize * 1.04,
          fontWeight: FontWeight.w900,
          height: 0.94,
          letterSpacing: -1.2,
        ),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFFFFF),
            Color(0xFFDCE2EB),
            Color(0xFF8893A2),
          ],
          stops: [0.0, 0.48, 1.0],
        ),
        shadows: const [
          Shadow(color: Color(0xEE000000), offset: Offset(0, 4), blurRadius: 10),
          Shadow(color: Color(0x55000000), offset: Offset(0, 8), blurRadius: 20),
        ],
        uppercase: true,
      ),
      CinioTitlePreset.editorialModern => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Poppins',
          fontSize: fontSize * 0.92,
          fontWeight: FontWeight.w700,
          height: 1.04,
          letterSpacing: -0.4,
        ),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFFFFF),
            Color(0xFFE6ECF5),
            Color(0xFFB0BDCF),
          ],
          stops: [0.0, 0.55, 1.0],
        ),
        shadows: const [
          Shadow(color: Colors.black87, offset: Offset(0, 2), blurRadius: 6),
        ],
        uppercase: false,
      ),
      CinioTitlePreset.crimsonImpact => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Montserrat',
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          height: 0.96,
          letterSpacing: 0.2,
        ),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFF8E8E),
            Color(0xFFE50914),
            Color(0xFF8A0006),
          ],
          stops: [0.0, 0.48, 1.0],
        ),
        shadows: const [
          Shadow(color: Color(0xCC000000), offset: Offset(0, 3), blurRadius: 8),
          Shadow(color: Color(0x55E50914), blurRadius: 12),
        ],
        uppercase: true,
      ),
      CinioTitlePreset.cyberEmerald => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Rubik',
          fontSize: fontSize * 0.96,
          fontWeight: FontWeight.w800,
          height: 1.0,
          letterSpacing: 0.6,
        ),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFB3FFE8),
            Color(0xFF00E676),
            Color(0xFF007A3E),
          ],
          stops: [0.0, 0.50, 1.0],
        ),
        shadows: const [
          Shadow(color: Colors.black87, offset: Offset(0, 2), blurRadius: 6),
          Shadow(color: Color(0x6600E676), blurRadius: 12),
        ],
        uppercase: true,
      ),
      CinioTitlePreset.sunsetAmber => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Poppins',
          fontSize: fontSize * 0.96,
          fontWeight: FontWeight.w800,
          height: 1.0,
          letterSpacing: -0.6,
        ),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFDFB0),
            Color(0xFFFF8C42),
            Color(0xFFFF3C5F),
          ],
          stops: [0.0, 0.50, 1.0],
        ),
        shadows: const [
          Shadow(color: Color(0xDD000000), offset: Offset(0, 3), blurRadius: 8),
          Shadow(color: Color(0x44FF8C42), blurRadius: 10),
        ],
        uppercase: true,
      ),
    };
  }

  static Color _tuneAccent(Color accent) {
    final hsl = HSLColor.fromColor(accent);
    final saturation = hsl.saturation.clamp(0.50, 0.95).toDouble();
    final lightness = hsl.lightness.clamp(0.50, 0.72).toDouble();
    return hsl
        .withSaturation(saturation)
        .withLightness(lightness)
        .toColor();
  }
}

Widget cinioFallbackTitle({
  required String title,
  required Object seed,
  required Color accent,
  double fontSize = 32,
  int maxLines = 2,
  TextAlign textAlign = TextAlign.center,
}) {
  final preset = CinioTitleStyle.presetFor(seed);
  final cfg = CinioTitleStyle.configFor(
    preset: preset,
    accent: accent,
    fontSize: fontSize,
  );

  final displayTitle = cfg.uppercase ? title.toUpperCase() : title;

  return ShaderMask(
    blendMode: BlendMode.srcIn,
    shaderCallback: (bounds) => cfg.gradient.createShader(bounds),
    child: Text(
      displayTitle,
      textAlign: textAlign,
      maxLines: maxLines,
      softWrap: true,
      overflow: TextOverflow.ellipsis,
      style: cfg.baseStyle.copyWith(
        color: Colors.white,
        shadows: cfg.shadows,
      ),
    ),
  );
}
