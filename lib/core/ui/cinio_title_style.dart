import 'package:flutter/material.dart';

import '../theme/app_text.dart';

/// Distinct cinematic title styling presets for titles without official logos.
///
/// Deterministically assigned per title (via seed hash), so each movie/series
/// gets a consistent, uniquely stylized typographic identity across Home,
/// Detail, Search, and Player loading.
enum CinioTitlePreset {
  breakingChemical,
  darkKnightNoir,
  espionageTypewriter,
  deathGameGeometric,
  retroSynthwave,
  cyberMatrix,
  atomicInferno,
  vintageGold,
  cosmicHolo,
  prestigeTitanium,
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
    return switch (preset) {
      // 1. Inspired by Breaking Bad (Chemical element toxic cyan-emerald)
      CinioTitlePreset.breakingChemical => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Montserrat',
          fontSize: fontSize * 0.98,
          fontWeight: FontWeight.w900,
          height: 0.95,
          letterSpacing: 2.8,
        ),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFE6FFFA),
            Color(0xFF38EF7D),
            Color(0xFF11998E),
            Color(0xFF0A5C54),
          ],
          stops: [0.0, 0.40, 0.75, 1.0],
        ),
        shadows: const [
          Shadow(color: Color(0xDD11998E), blurRadius: 20),
          Shadow(color: Color(0xFF000000), offset: Offset(0, 4), blurRadius: 10),
        ],
        uppercase: true,
      ),

      // 2. Inspired by Batman (Dark Knight gritty noir with bat-amber shadow)
      CinioTitlePreset.darkKnightNoir => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Montserrat',
          fontSize: fontSize * 1.06,
          fontWeight: FontWeight.w900,
          height: 0.88,
          letterSpacing: -0.8,
        ),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFFFFF),
            Color(0xFFE2E8F0),
            Color(0xFF64748B),
            Color(0xFF0F172A),
          ],
          stops: [0.0, 0.35, 0.70, 1.0],
        ),
        shadows: const [
          Shadow(color: Color(0xCCFECA57), offset: Offset(0, 0), blurRadius: 16),
          Shadow(color: Color(0xFF000000), offset: Offset(0, 6), blurRadius: 12),
        ],
        uppercase: true,
      ),

      // 3. Inspired by Slow Horses (Cold British MI5 stamped dossier)
      CinioTitlePreset.espionageTypewriter => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Rubik',
          fontSize: fontSize * 0.90,
          fontWeight: FontWeight.w800,
          height: 1.08,
          letterSpacing: 5.0,
        ),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFEF3C7),
            Color(0xFFF59E0B),
            Color(0xFFB45309),
          ],
          stops: [0.0, 0.55, 1.0],
        ),
        shadows: const [
          Shadow(color: Color(0x99DC2626), offset: Offset(0, 0), blurRadius: 14),
          Shadow(color: Color(0xEE000000), offset: Offset(0, 3), blurRadius: 8),
        ],
        uppercase: true,
      ),

      // 4. Inspired by Squid Game (Geometric high-contrast hot pink on void)
      CinioTitlePreset.deathGameGeometric => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Montserrat',
          fontSize: fontSize * 1.02,
          fontWeight: FontWeight.w900,
          height: 0.94,
          letterSpacing: 2.2,
        ),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFF0F7),
            Color(0xFFFF007F),
            Color(0xFFA30052),
          ],
          stops: [0.0, 0.50, 1.0],
        ),
        shadows: const [
          Shadow(color: Color(0xDDFF007F), blurRadius: 24),
          Shadow(color: Color(0xFF000000), offset: Offset(0, 4), blurRadius: 10),
        ],
        uppercase: true,
      ),

      // 5. Inspired by Stranger Things / 80s Synthwave (Electric violet neon)
      CinioTitlePreset.retroSynthwave => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Montserrat',
          fontSize: fontSize * 0.96,
          fontWeight: FontWeight.w900,
          height: 0.96,
          letterSpacing: 1.6,
        ),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFF77E9),
            Color(0xFFFF007F),
            Color(0xFF7B00FF),
          ],
          stops: [0.0, 0.45, 1.0],
        ),
        shadows: const [
          Shadow(color: Color(0xBBFF007F), blurRadius: 20),
          Shadow(color: Color(0xFF000000), offset: Offset(0, 3), blurRadius: 8),
        ],
        uppercase: true,
      ),

      // 6. Inspired by The Matrix / Cyberpunk (Digital terminal phosphor)
      CinioTitlePreset.cyberMatrix => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Rubik',
          fontSize: fontSize * 0.96,
          fontWeight: FontWeight.w800,
          height: 1.0,
          letterSpacing: 2.0,
        ),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFD1FAE5),
            Color(0xFF10B981),
            Color(0xFF047857),
          ],
          stops: [0.0, 0.48, 1.0],
        ),
        shadows: const [
          Shadow(color: Color(0xBB10B981), blurRadius: 18),
          Shadow(color: Color(0xFF000000), offset: Offset(0, 3), blurRadius: 8),
        ],
        uppercase: true,
      ),

      // 7. Inspired by Oppenheimer / Action Inferno (Atomic flame ember)
      CinioTitlePreset.atomicInferno => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Montserrat',
          fontSize: fontSize * 1.04,
          fontWeight: FontWeight.w900,
          height: 0.92,
          letterSpacing: -0.4,
        ),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFFBEB),
            Color(0xFFF59E0B),
            Color(0xFFEF4444),
            Color(0xFF7F1D1D),
          ],
          stops: [0.0, 0.35, 0.70, 1.0],
        ),
        shadows: const [
          Shadow(color: Color(0xCCF59E0B), blurRadius: 22),
          Shadow(color: Color(0xFF000000), offset: Offset(0, 4), blurRadius: 10),
        ],
        uppercase: true,
      ),

      // 8. Inspired by Peaky Blinders / Godfather (Brushed antique gold)
      CinioTitlePreset.vintageGold => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Montserrat',
          fontSize: fontSize * 0.96,
          fontWeight: FontWeight.w800,
          height: 1.0,
          letterSpacing: 3.2,
        ),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFFDF0),
            Color(0xFFFCD34D),
            Color(0xFFD97706),
            Color(0xFF78350F),
          ],
          stops: [0.0, 0.38, 0.75, 1.0],
        ),
        shadows: const [
          Shadow(color: Color(0x99D97706), blurRadius: 18),
          Shadow(color: Color(0xFF000000), offset: Offset(0, 3), blurRadius: 8),
        ],
        uppercase: true,
      ),

      // 9. Inspired by Interstellar / 2001 (Deep cosmic cyan holo)
      CinioTitlePreset.cosmicHolo => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Rubik',
          fontSize: fontSize * 0.94,
          fontWeight: FontWeight.w800,
          height: 1.02,
          letterSpacing: 3.0,
        ),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF0FDF4),
            Color(0xFF38BDF8),
            Color(0xFF0284C7),
            Color(0xFF0369A1),
          ],
          stops: [0.0, 0.40, 0.75, 1.0],
        ),
        shadows: const [
          Shadow(color: Color(0xAA38BDF8), blurRadius: 20),
          Shadow(color: Color(0xFF000000), offset: Offset(0, 3), blurRadius: 8),
        ],
        uppercase: true,
      ),

      // 10. Inspired by Succession / Prestige Drama (Clean frosted platinum)
      CinioTitlePreset.prestigeTitanium => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Poppins',
          fontSize: fontSize * 0.95,
          fontWeight: FontWeight.w800,
          height: 1.02,
          letterSpacing: 2.0,
        ),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFFFFF),
            Color(0xFFE2E8F0),
            Color(0xFF94A3B8),
            Color(0xFF475569),
          ],
          stops: [0.0, 0.45, 0.80, 1.0],
        ),
        shadows: const [
          Shadow(color: Color(0xFF000000), offset: Offset(0, 4), blurRadius: 10),
          Shadow(color: Color(0x6664748B), blurRadius: 14),
        ],
        uppercase: true,
      ),
    };
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

  return Stack(
    alignment: Alignment.center,
    children: [
      // Layer 1: Crisp subtle shadow behind the text (renders outside the ShaderMask)
      Text(
        displayTitle,
        textAlign: textAlign,
        maxLines: maxLines,
        softWrap: true,
        overflow: TextOverflow.ellipsis,
        style: cfg.baseStyle.copyWith(
          color: Colors.transparent,
          shadows: cfg.shadows,
        ),
      ),
      // Layer 2: Razor-sharp vector text filled with the gradient
      ShaderMask(
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
            shadows: const [],
          ),
        ),
      ),
    ],
  );
}
