import 'package:flutter/material.dart';

import '../theme/app_text.dart';

/// 5 Signature Cinio title typography archetypes.
///
/// Presets strictly govern **typography, composition, and weight**,
/// while the poster's dominant palette dynamically governs **color & tint**.
enum CinioTitlePreset {
  /// 01 — Cinematic Condensed (Inspired by Batman / Daredevil / The Punisher)
  /// Heavy condensed sans, tight line height, compressed tracking, crisp drop shadow.
  cinematicCondensed,

  /// 02 — Industrial / Stamped (Inspired by Breaking Bad / Slow Horses)
  /// Sturdy bold weight, wider tracking, structured stamped feel, subtle poster tint.
  industrialStamped,

  /// 03 — Geometric Modern (Inspired by Squid Game / modern Netflix titles)
  /// Ultra-clean geometric sans, balanced tracking, minimalist flat tone.
  geometricModern,

  /// 04 — Editorial Prestige (Inspired by Apple TV+ / HBO prestige dramas)
  /// Refined medium-heavy weight, Title Case, elegant letter spacing, soft shadow.
  editorialPrestige,

  /// 05 — Raw / Noir Thriller (Inspired by Sicario / Crime Thrillers)
  /// Heavy, blocky typography, high contrast, strong dark grounding.
  rawNoir,
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
    double fontSize = 30.0,
  }) {
    // 5% global reduction for balanced cinematic proportions
    final effSize = fontSize * 0.95;

    // Derived restrained palette based on poster accent
    final tintLight = Color.lerp(Colors.white, accent, 0.18) ?? Colors.white;
    final tintMid = Color.lerp(const Color(0xFFE2E8F0), accent, 0.28) ?? const Color(0xFFE2E8F0);
    final tintDark = Color.lerp(const Color(0xFF94A3B8), accent, 0.38) ?? const Color(0xFF94A3B8);

    return switch (preset) {
      // 01 — CINEMATIC CONDENSED
      CinioTitlePreset.cinematicCondensed => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Montserrat',
          fontSize: effSize * 1.02,
          fontWeight: FontWeight.w900,
          height: 0.88,
          letterSpacing: -0.5,
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            tintLight,
            tintMid,
            tintDark,
          ],
          stops: const [0.0, 0.35, 0.70, 1.0],
        ),
        shadows: const [
          Shadow(color: Colors.black, offset: Offset(0, 3), blurRadius: 8),
          Shadow(color: Colors.black87, offset: Offset(0, 1), blurRadius: 3),
        ],
        uppercase: true,
      ),

      // 02 — INDUSTRIAL / STAMPED
      CinioTitlePreset.industrialStamped => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Rubik',
          fontSize: effSize * 0.92,
          fontWeight: FontWeight.w800,
          height: 0.94,
          letterSpacing: 1.8,
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tintLight,
            tintMid,
          ],
          stops: const [0.0, 1.0],
        ),
        shadows: const [
          Shadow(color: Colors.black, offset: Offset(0, 2), blurRadius: 5),
          Shadow(color: Colors.black54, offset: Offset(0, 1), blurRadius: 2),
        ],
        uppercase: true,
      ),

      // 03 — GEOMETRIC MODERN
      CinioTitlePreset.geometricModern => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Montserrat',
          fontSize: effSize * 0.95,
          fontWeight: FontWeight.w700,
          height: 0.96,
          letterSpacing: 1.2,
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            tintLight,
          ],
          stops: const [0.0, 1.0],
        ),
        shadows: const [
          Shadow(color: Colors.black87, offset: Offset(0, 2), blurRadius: 6),
        ],
        uppercase: true,
      ),

      // 04 — EDITORIAL PRESTIGE
      CinioTitlePreset.editorialPrestige => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Rubik',
          fontSize: effSize * 0.96,
          fontWeight: FontWeight.w600,
          height: 1.0,
          letterSpacing: 0.4,
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            tintLight,
          ],
          stops: const [0.0, 1.0],
        ),
        shadows: const [
          Shadow(color: Colors.black54, offset: Offset(0, 2), blurRadius: 4),
        ],
        uppercase: false,
      ),

      // 05 — RAW / NOIR THRILLER
      CinioTitlePreset.rawNoir => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Montserrat',
          fontSize: effSize * 1.00,
          fontWeight: FontWeight.w900,
          height: 0.90,
          letterSpacing: -0.2,
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            tintMid,
            tintDark,
          ],
          stops: const [0.0, 0.50, 1.0],
        ),
        shadows: const [
          Shadow(color: Colors.black, offset: Offset(0, 4), blurRadius: 10),
          Shadow(color: Colors.black87, offset: Offset(0, 2), blurRadius: 4),
        ],
        uppercase: true,
      ),
    };
  }
}

/// Helper to decompose a title into Main Title + Subtitle if it contains a separator.
({String main, String? sub}) _splitCompoundTitle(String title) {
  final trimmed = title.trim();
  if (trimmed.isEmpty) return (main: '', sub: null);

  // Check colon first
  if (trimmed.contains(':')) {
    final idx = trimmed.indexOf(':');
    final p1 = trimmed.substring(0, idx).trim();
    final p2 = trimmed.substring(idx + 1).trim();
    if (p1.isNotEmpty && p2.isNotEmpty && p1.length <= 40) {
      return (main: p1, sub: p2);
    }
  }

  // Check " - " or " — "
  for (final sep in const [' — ', ' – ', ' - ']) {
    if (trimmed.contains(sep)) {
      final idx = trimmed.indexOf(sep);
      final p1 = trimmed.substring(0, idx).trim();
      final p2 = trimmed.substring(idx + sep.length).trim();
      if (p1.isNotEmpty && p2.isNotEmpty && p1.length <= 40) {
        return (main: p1, sub: p2);
      }
    }
  }

  return (main: trimmed, sub: null);
}

Widget cinioFallbackTitle({
  required String title,
  required Object seed,
  required Color accent,
  double fontSize = 26.6,
  int maxLines = 2,
  TextAlign textAlign = TextAlign.center,
}) {
  final split = _splitCompoundTitle(title);
  final hasSub = split.sub != null && split.sub!.isNotEmpty;

  // Use the passed-in fontSize directly (already 5% reduced upstream).
  // FittedBox handles shrinking for long titles automatically — no more
  // manual length-bucket heuristics.
  final effectiveFontSize = fontSize;

  final preset = CinioTitleStyle.presetFor(seed);
  final cfg = CinioTitleStyle.configFor(
    preset: preset,
    accent: accent,
    fontSize: effectiveFontSize,
  );

  final displayMain = cfg.uppercase ? split.main.toUpperCase() : split.main;
  final mainFontSize = cfg.baseStyle.fontSize ?? effectiveFontSize;

  // Builds the shadow + gradient double-layer text, wrapped in a FittedBox
  // so it scales down only when it would otherwise overflow — short titles
  // stay at full size, long titles shrink smoothly to fit.
  Widget buildMainText(double fs, int lines) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Text(
          displayMain,
          textAlign: textAlign,
          maxLines: lines,
          softWrap: true,
          overflow: TextOverflow.ellipsis,
          style: cfg.baseStyle.copyWith(
            fontSize: fs,
            color: Colors.transparent,
            shadows: cfg.shadows,
          ),
        ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => cfg.gradient.createShader(bounds),
          child: Text(
            displayMain,
            textAlign: textAlign,
            maxLines: lines,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
            style: cfg.baseStyle.copyWith(
              fontSize: fs,
              color: Colors.white,
              shadows: const [],
            ),
          ),
        ),
      ],
    ),
  );

  if (hasSub) {
    final subText = cfg.uppercase ? split.sub!.toUpperCase() : split.sub!;
    final subFontSize = (mainFontSize * 0.44).clamp(9.5, 12.5);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        buildMainText(mainFontSize, 2),
        const SizedBox(height: 3),
        // Subtitle (Secondary Refined Tier)
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            subText,
            textAlign: textAlign,
            maxLines: 2,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(
              fontFamily: cfg.baseStyle.fontFamily ?? 'Rubik',
              fontSize: subFontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.6,
              color: Color.lerp(Colors.white70, accent, 0.20) ?? Colors.white70,
              shadows: const [
                Shadow(
                  color: Color(0xFF000000),
                  offset: Offset(0, 1.5),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  return buildMainText(mainFontSize, maxLines);
}
