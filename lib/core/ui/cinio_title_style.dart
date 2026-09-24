import 'package:flutter/material.dart';

import '../theme/app_text.dart';

/// Three deliberately designed Cinio fallback title treatments used when a
/// provider does not have an official title logo.
///
/// The presets are deterministic per title, so a title keeps the same visual
/// identity across the home hero and detail page. They use fonts bundled with
/// Cinio rather than relying on device-installed fonts.
enum CinioTitlePreset { cinematic, editorial, geometric }

class CinioTitleStyle {
  const CinioTitleStyle._();

  static CinioTitlePreset presetFor(Object seed) {
    final hash = seed.hashCode.abs();
    return CinioTitlePreset.values[hash % CinioTitlePreset.values.length];
  }

  static TextStyle style({
    required CinioTitlePreset preset,
    required Color accent,
    double fontSize = 32,
  }) {
    final color = _colorForAccent(accent);
    return switch (preset) {
      CinioTitlePreset.cinematic => AppText.display.copyWith(
          fontFamily: 'Montserrat',
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          height: 1.0,
          letterSpacing: -1.15,
          color: color,
        ),
      CinioTitlePreset.editorial => AppText.display.copyWith(
          fontFamily: 'Lato',
          fontSize: fontSize + 1,
          fontWeight: FontWeight.w800,
          height: 0.98,
          letterSpacing: -0.7,
          color: color,
        ),
      CinioTitlePreset.geometric => AppText.display.copyWith(
          fontFamily: 'Rubik',
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          height: 1.02,
          letterSpacing: -0.9,
          color: color,
        ),
    };
  }

  static Color _colorForAccent(Color accent) {
    final hsl = HSLColor.fromColor(accent);
    final saturation = hsl.saturation.clamp(0.35, 0.92).toDouble();
    final lightness = hsl.lightness.clamp(0.54, 0.76).toDouble();
    final tuned = hsl
        .withSaturation(saturation)
        .withLightness(lightness)
        .toColor();
    return Color.lerp(Colors.white, tuned, 0.78) ?? tuned;
  }
}

Text cinioFallbackTitle({
  required String title,
  required Object seed,
  required Color accent,
  double fontSize = 32,
  int maxLines = 2,
}) {
  final preset = CinioTitleStyle.presetFor(seed);
  return Text(
    title,
    textAlign: TextAlign.center,
    maxLines: maxLines,
    softWrap: true,
    overflow: TextOverflow.ellipsis,
    style: CinioTitleStyle.style(
      preset: preset,
      accent: accent,
      fontSize: fontSize,
    ),
  );
}
