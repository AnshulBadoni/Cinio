import 'package:flutter/material.dart';

import '../theme/app_text.dart';

/// 10 Distinct Cinio title typography archetypes.
///
/// Presets strictly govern **typography, composition, and weight**,
/// while the poster's dominant palette dynamically governs **color & tint**.
enum CinioTitlePreset {
  /// 01 — Cinematic — Prestige (Inspired by The Last of Us, Apple TV+, HBO)
  /// Elegant high-contrast serif, large but restrained, slight letter spacing, subtle shadow.
  /// Good for: Drama, historical, prestige, mystery.
  cinematicPrestige,

  /// 02 — Blockbuster — Heavy Sans (Inspired by Oppenheimer)
  /// Very heavy sans-serif, wide proportions, tight letter spacing, strong hierarchy.
  /// Good for: Action, sci-fi, thriller, blockbuster.
  blockbusterHeavySans,

  /// 03 — Comic Book (Inspired by Invincible!)
  /// Heavy comic/display font, slight slant/angle, subtle 3D extrusion/shadow.
  /// Good for: Superhero, comedy, animation, action.
  comicBook,

  /// 04 — Horror — Distressed (Inspired by The Ritual)
  /// Cold distressed tone, wide eerie tracking, deep menacing shadow.
  /// Good for: Horror, psychological thriller, supernatural.
  horrorDistressed,

  /// 05 — Retro / 80s (Inspired by Stranger Things)
  /// Retro geometric display, wide tracking, subtle luminous neon glow.
  /// Good for: Retro, sci-fi, 80s-inspired content.
  retro80s,

  /// 06 — Futuristic / Sci-Fi (Inspired by Dune Part II)
  /// Geometric sans, ultra-wide spacing, sleek metallic gradient.
  /// Good for: Sci-fi, space, cyberpunk, technology.
  futuristicSciFi,

  /// 07 — Handwritten / Indie (Inspired by Lady Bird)
  /// Natural human feeling, Title Case, warm soft shadow, minimal decoration.
  /// Good for: Indie, romance, coming-of-age, comedy.
  handwrittenIndie,

  /// 08 — Western / Americana (Inspired by Digger, Yellowstone)
  /// Western slab serif feel, strong vertical structure, dual hard weathered shadow.
  /// Good for: Western, cowboy, frontier, historical.
  westernAmericana,

  /// 09 — Elegant / Luxury (Inspired by Succession)
  /// Thin high-fashion serif, very generous tracking, razor clean.
  /// Good for: Luxury, fashion, romance, sophisticated drama.
  elegantLuxury,

  /// 10 — Anime / Stylized Graphic (Inspired by Jujutsu Kaisen)
  /// Strong stylized display, bold punch, chromatic artwork-tinted outline/shadow.
  /// Good for: Anime, manga, animation, fantasy.
  animeGraphic,

  /// 11 — Sweaty / Movie Display (Inspired by Sweaty Font & high-impact movie display typography)
  /// Ultra-heavy chunky display lettering, intense poster palette gradient,
  /// 3D layered drop shadows and vibrant edge glow.
  /// Good for: Blockbusters, action, animated movies, comedy, punchy titles.
  sweatyMovie,
}

class CinioTitleStyle {
  const CinioTitleStyle._();

  /// Resolves the optimal title preset with balanced distribution:
  /// 1. Prioritizes natural genre affinity without letting broad genres (Action/Drama)
  ///    monopolize the selection.
  /// 2. Uses deterministic seed hashing within genre clusters to distribute across
  ///    multiple matching styles.
  /// 3. Falls back to equal distribution across archetypes when genres are omitted.
  static CinioTitlePreset presetFor(Object seed, {List<String> genres = const []}) {
    final hash = seed.hashCode.abs();

    if (genres.isNotEmpty) {
      final joined = genres.map((g) => g.toLowerCase()).join(' ');

      // 1. Anime / Manga / Animation
      if (joined.contains('anime') || joined.contains('manga') || joined.contains('animation')) {
        if (joined.contains('superhero') || joined.contains('comic') || joined.contains('comedy') || joined.contains('family')) {
          final mod = hash % 3;
          if (mod == 0) return CinioTitlePreset.sweatyMovie;
          if (mod == 1) return CinioTitlePreset.comicBook;
          return CinioTitlePreset.animeGraphic;
        }
        return (hash % 3 == 0) ? CinioTitlePreset.comicBook : CinioTitlePreset.animeGraphic;
      }

      // 2. Horror / Supernatural / Psychological
      if (joined.contains('horror') || joined.contains('supernatural') || joined.contains('psychological')) {
        return CinioTitlePreset.horrorDistressed;
      }

      // 3. Western / Frontier
      if (joined.contains('western') || joined.contains('cowboy') || joined.contains('frontier')) {
        return CinioTitlePreset.westernAmericana;
      }

      // 4. Sci-Fi / Science Fiction / Space / Fantasy
      if (joined.contains('sci-fi') || joined.contains('science fiction') || joined.contains('space') || joined.contains('cyberpunk') || joined.contains('fantasy')) {
        return (hash % 2 == 0) ? CinioTitlePreset.futuristicSciFi : CinioTitlePreset.retro80s;
      }

      // 5. Romance / Comedy / Family
      if (joined.contains('romance') || joined.contains('comedy') || joined.contains('coming-of-age') || joined.contains('family')) {
        if (joined.contains('comedy') || joined.contains('family')) {
          return (hash % 2 == 0) ? CinioTitlePreset.sweatyMovie : CinioTitlePreset.handwrittenIndie;
        }
        return (hash % 2 == 0) ? CinioTitlePreset.handwrittenIndie : CinioTitlePreset.elegantLuxury;
      }

      // 6. Mystery / Crime / Thriller
      if (joined.contains('mystery') || joined.contains('crime') || joined.contains('thriller')) {
        final mod = hash % 3;
        if (mod == 0) return CinioTitlePreset.blockbusterHeavySans;
        if (mod == 1) return CinioTitlePreset.cinematicPrestige;
        return CinioTitlePreset.horrorDistressed;
      }

      // 7. Drama / History / Biography / War
      if (joined.contains('drama') || joined.contains('history') || joined.contains('historical') || joined.contains('biography') || joined.contains('war')) {
        final mod = hash % 3;
        if (mod == 0) return CinioTitlePreset.cinematicPrestige;
        if (mod == 1) return CinioTitlePreset.elegantLuxury;
        return CinioTitlePreset.handwrittenIndie;
      }

      // 8. Action / Adventure / Superhero / Blockbuster
      if (joined.contains('action') || joined.contains('adventure') || joined.contains('superhero')) {
        final mod = hash % 4;
        if (mod == 0) return CinioTitlePreset.sweatyMovie;
        if (mod == 1) return CinioTitlePreset.blockbusterHeavySans;
        if (mod == 2) return CinioTitlePreset.retro80s;
        return CinioTitlePreset.westernAmericana;
      }
    }

    // Default: Uniform hash distribution across all archetypes
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
    int titleLength = 0,
  }) {
    // 5% global reduction for balanced cinematic proportions
    final effSize = fontSize * 0.95;

    // Vibrant poster color tones directly derived from the extracted palette
    final bool hasVibrantAccent = accent != Colors.white && accent != Colors.transparent;
    final Color posterAccent = hasVibrantAccent ? accent : const Color(0xFFE50914);

    // Multi-stop rich color highlights and shades tuned to the poster's dominant hue
    final tintLight = Color.lerp(Colors.white, posterAccent, 0.40) ?? Colors.white;
    final tintMid = posterAccent;
    final tintDeep = Color.lerp(posterAccent, Colors.black, 0.65) ?? Colors.black;
    final tintDark = Color.lerp(posterAccent, const Color(0xFF1E293B), 0.50) ?? const Color(0xFF1E293B);

    // Tracking compression factor for long titles so wide-spaced styles
    // (Sci-Fi, Luxury, Horror) don't overflow the container width.
    final double trackingScale;
    if (titleLength <= 12) {
      trackingScale = 1.0;
    } else if (titleLength <= 24) {
      trackingScale = 0.55;
    } else if (titleLength <= 36) {
      trackingScale = 0.28;
    } else {
      trackingScale = 0.12;
    }

    return switch (preset) {
      // 01 — CINEMATIC — PRESTIGE (e.g. The Last of Us, Apple TV+, HBO)
      CinioTitlePreset.cinematicPrestige => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Poppins',
          fontSize: effSize * 1.04,
          fontWeight: FontWeight.w700,
          height: 0.95,
          letterSpacing: (2.0 * trackingScale).clamp(-0.4, 2.4),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            tintLight,
            tintMid,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        shadows: const [
          Shadow(color: Colors.black, offset: Offset(0, 3), blurRadius: 8),
          Shadow(color: Colors.black87, offset: Offset(0, 1), blurRadius: 2),
        ],
        uppercase: true,
      ),

      // 02 — BLOCKBUSTER — HEAVY SANS (e.g. Oppenheimer)
      CinioTitlePreset.blockbusterHeavySans => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Montserrat',
          fontSize: effSize * 1.08,
          fontWeight: FontWeight.w900,
          height: 0.88,
          letterSpacing: (-0.8 * trackingScale).clamp(-1.2, 0.0),
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
          Shadow(color: Colors.black, offset: Offset(0, 4), blurRadius: 10),
          Shadow(color: Colors.black87, offset: Offset(0, 1), blurRadius: 3),
        ],
        uppercase: true,
      ),

      // 03 — COMIC BOOK (e.g. Invincible!)
      CinioTitlePreset.comicBook => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Rubik',
          fontSize: effSize * 1.04,
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
          height: 0.92,
          letterSpacing: (0.4 * trackingScale).clamp(-0.2, 0.8),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            tintLight,
            tintMid,
          ],
          stops: const [0.0, 0.60, 1.0],
        ),
        shadows: const [
          Shadow(color: Colors.black, offset: Offset(2.0, 2.5), blurRadius: 0),
          Shadow(color: Colors.black, offset: Offset(3.5, 4.0), blurRadius: 3),
        ],
        uppercase: true,
      ),

      // 04 — HORROR — DISTRESSED (e.g. The Ritual)
      CinioTitlePreset.horrorDistressed => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Montserrat',
          fontSize: effSize * 0.94,
          fontWeight: FontWeight.w700,
          fontStyle: FontStyle.italic,
          height: 1.04,
          letterSpacing: (4.8 * trackingScale).clamp(0.2, 4.8),
        ),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFF1F5F9),
            Color(0xFF94A3B8),
            Color(0xFF475569),
          ],
          stops: [0.0, 0.50, 1.0],
        ),
        shadows: const [
          Shadow(color: Colors.black, offset: Offset(0, 6), blurRadius: 16),
          Shadow(color: Colors.black, offset: Offset(0, 2), blurRadius: 4),
        ],
        uppercase: true,
      ),

      // 05 — RETRO / 80S (e.g. Stranger Things)
      CinioTitlePreset.retro80s => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Montserrat',
          fontSize: effSize * 0.96,
          fontWeight: FontWeight.w800,
          height: 0.95,
          letterSpacing: (3.2 * trackingScale).clamp(0.2, 3.2),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            tintLight,
            accent,
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
        shadows: [
          Shadow(color: accent.withValues(alpha: 0.85), offset: Offset.zero, blurRadius: 14),
          Shadow(color: accent.withValues(alpha: 0.45), offset: Offset.zero, blurRadius: 28),
          const Shadow(color: Colors.black, offset: Offset(0, 3), blurRadius: 6),
        ],
        uppercase: true,
      ),

      // 06 — FUTURISTIC / SCI-FI (e.g. Dune Part II)
      CinioTitlePreset.futuristicSciFi => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Montserrat',
          fontSize: effSize * 0.88,
          fontWeight: FontWeight.w400,
          height: 1.06,
          letterSpacing: (6.5 * trackingScale).clamp(0.4, 6.5),
        ),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            Color(0xFFE2E8F0),
            Color(0xFF94A3B8),
          ],
          stops: [0.0, 0.50, 1.0],
        ),
        shadows: const [
          Shadow(color: Colors.black87, offset: Offset(0, 2), blurRadius: 8),
        ],
        uppercase: true,
      ),

      // 07 — HANDWRITTEN / INDIE (e.g. Lady Bird)
      CinioTitlePreset.handwrittenIndie => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Lato',
          fontSize: effSize * 0.98,
          fontWeight: FontWeight.w600,
          fontStyle: FontStyle.italic,
          height: 1.02,
          letterSpacing: (0.6 * trackingScale).clamp(0.0, 1.0),
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
          Shadow(color: Colors.black54, offset: Offset(0, 2), blurRadius: 5),
        ],
        uppercase: false,
      ),

      // 08 — WESTERN / AMERICANA (e.g. Digger, Yellowstone)
      CinioTitlePreset.westernAmericana => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Rubik',
          fontSize: effSize * 0.94,
          fontWeight: FontWeight.w900,
          height: 0.96,
          letterSpacing: (2.8 * trackingScale).clamp(0.2, 2.8),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFFFFBEB),
            tintLight,
            tintMid,
          ],
          stops: const [0.0, 0.40, 1.0],
        ),
        shadows: const [
          Shadow(color: Color(0xFF1C130D), offset: Offset(2.0, 2.0), blurRadius: 1),
          Shadow(color: Colors.black, offset: Offset(0, 4), blurRadius: 7),
        ],
        uppercase: true,
      ),

      // 09 — ELEGANT / LUXURY (e.g. Succession)
      CinioTitlePreset.elegantLuxury => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Inter',
          fontSize: effSize * 0.88,
          fontWeight: FontWeight.w300,
          height: 1.10,
          letterSpacing: (7.5 * trackingScale).clamp(0.4, 7.5),
        ),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            Color(0xFFF8FAFC),
          ],
          stops: [0.0, 1.0],
        ),
        shadows: const [
          Shadow(color: Colors.black54, offset: Offset(0, 2), blurRadius: 6),
        ],
        uppercase: true,
      ),

      // 10 — ANIME / STYLIZED GRAPHIC (e.g. Jujutsu Kaisen)
      CinioTitlePreset.animeGraphic => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Montserrat',
          fontSize: effSize * 1.04,
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
          height: 0.88,
          letterSpacing: (-0.3 * trackingScale).clamp(-0.6, 0.0),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            tintLight,
            accent,
          ],
          stops: const [0.0, 0.40, 1.0],
        ),
        shadows: [
          Shadow(color: accent, offset: const Offset(-1.5, -1.0), blurRadius: 0),
          const Shadow(color: Colors.black, offset: Offset(2.5, 3.0), blurRadius: 4),
        ],
        uppercase: true,
      ),

      // 11 — SWEATY / MOVIE DISPLAY (Inspired by Sweaty Font, chunky movie display titles)
      CinioTitlePreset.sweatyMovie => (
        baseStyle: AppText.display.copyWith(
          fontFamily: 'Rubik',
          fontSize: effSize * 1.14,
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
          height: 0.88,
          letterSpacing: (-0.6 * trackingScale).clamp(-1.2, 0.2),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            tintLight,
            tintMid,
            tintDeep,
          ],
          stops: const [0.0, 0.25, 0.65, 1.0],
        ),
        shadows: [
          Shadow(
            color: Color.lerp(tintMid, Colors.black, 0.80)!,
            offset: const Offset(2.2, 3.2),
            blurRadius: 0,
          ),
          Shadow(
            color: Colors.black.withValues(alpha: 0.95),
            offset: const Offset(4.0, 5.5),
            blurRadius: 4,
          ),
          Shadow(
            color: tintMid.withValues(alpha: 0.5),
            offset: Offset.zero,
            blurRadius: 18,
          ),
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
    if (p1.isNotEmpty && p2.isNotEmpty && p1.length <= 48) {
      return (main: p1, sub: p2);
    }
  }

  // Check " - " or " — " or " – "
  for (final sep in const [' — ', ' – ', ' - ']) {
    if (trimmed.contains(sep)) {
      final idx = trimmed.indexOf(sep);
      final p1 = trimmed.substring(0, idx).trim();
      final p2 = trimmed.substring(idx + sep.length).trim();
      if (p1.isNotEmpty && p2.isNotEmpty && p1.length <= 48) {
        return (main: p1, sub: p2);
      }
    }
  }

  return (main: trimmed, sub: null);
}

List<String> _chunkWordsForPlayfulTitle(String text) {
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.length <= 2) return [text];
  if (words.length == 3) return [words[0], words[1], words[2]];
  if (words.length == 4) return ['${words[0]} ${words[1]}', '${words[2]} ${words[3]}'];
  if (words.length == 5) return ['${words[0]} ${words[1]}', words[2], '${words[3]} ${words[4]}'];
  final chunkCount = words.length > 7 ? 4 : 3;
  final perChunk = (words.length / chunkCount).ceil();
  final chunks = <String>[];
  for (var i = 0; i < words.length; i += perChunk) {
    chunks.add(words.skip(i).take(perChunk).join(' '));
  }
  return chunks;
}

Widget cinioFallbackTitle({
  required String title,
  required Object seed,
  required Color accent,
  List<String> genres = const [],
  double fontSize = 38.0,
  int maxLines = 3,
  TextAlign textAlign = TextAlign.center,
  double? maxWidth,
}) {
  final split = _splitCompoundTitle(title);
  final hasSub = split.sub != null && split.sub!.isNotEmpty;

  final mainLen = split.main.length;
  final words = split.main.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final isPlayfulLong = mainLen > 15 || words.length >= 3;

  final double lengthScale;
  final int maxDisplayLines;

  if (mainLen <= 14) {
    lengthScale = 1.0;
    maxDisplayLines = maxLines;
  } else if (mainLen <= 26) {
    lengthScale = 0.92;
    maxDisplayLines = maxLines.clamp(2, 4);
  } else if (mainLen <= 40) {
    lengthScale = 0.84;
    maxDisplayLines = 4;
  } else {
    lengthScale = 0.74;
    maxDisplayLines = 4;
  }

  final effectiveFontSize = fontSize * lengthScale;

  final preset = CinioTitleStyle.presetFor(seed, genres: genres);
  final cfg = CinioTitleStyle.configFor(
    preset: preset,
    accent: accent,
    fontSize: effectiveFontSize,
    titleLength: mainLen,
  );

  final displayMain = cfg.uppercase ? split.main.toUpperCase() : split.main;
  final mainFontSize = (cfg.baseStyle.fontSize ?? effectiveFontSize).clamp(24.0, 56.0);
  final fittedAlign = (textAlign == TextAlign.left)
      ? Alignment.centerLeft
      : (textAlign == TextAlign.right ? Alignment.centerRight : Alignment.center);
  final crossAlign = (textAlign == TextAlign.left)
      ? CrossAxisAlignment.start
      : (textAlign == TextAlign.right ? CrossAxisAlignment.end : CrossAxisAlignment.center);

  // Playful stacked layout inspired by "The End Of Oak Street"
  Widget buildPlayfulStacked(double fs, double maxW) {
    final lines = _chunkWordsForPlayfulTitle(displayMain);
    final playfulTransforms = const [
      (angle: -0.035, dx: -6.0),
      (angle: 0.040, dx: 7.0),
      (angle: -0.024, dx: -4.0),
      (angle: 0.030, dx: 5.0),
      (angle: -0.018, dx: -3.0),
    ];

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: fittedAlign,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: crossAlign,
          children: [
            for (var i = 0; i < lines.length; i++)
              Transform.translate(
                offset: Offset(
                  playfulTransforms[i % playfulTransforms.length].dx,
                  i == 0 ? 0.0 : -fs * 0.20,
                ),
                child: Transform.rotate(
                  angle: playfulTransforms[i % playfulTransforms.length].angle,
                  child: Text(
                    lines[i],
                    textAlign: textAlign,
                    maxLines: 1,
                    softWrap: false,
                    style: cfg.baseStyle.copyWith(
                      fontSize: fs,
                      height: 0.84,
                      color: Colors.white,
                      shadows: [
                        const Shadow(
                          color: Colors.black,
                          offset: Offset(0, 3.5),
                          blurRadius: 7,
                        ),
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.90),
                          offset: const Offset(2.0, 4.0),
                          blurRadius: 9,
                        ),
                        ...cfg.shadows,
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Standard non-gradient solid title
  Widget buildStandardText(double fs, int lines, double maxW) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: fittedAlign,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW),
      child: Text(
        displayMain,
        textAlign: textAlign,
        maxLines: lines,
        softWrap: true,
        style: cfg.baseStyle.copyWith(
          fontSize: fs,
          color: Colors.white,
          shadows: [
            const Shadow(
              color: Colors.black,
              offset: Offset(0, 3.0),
              blurRadius: 6,
            ),
            ...cfg.shadows,
          ],
        ),
      ),
    ),
  );

  Widget buildMainContent(double fs, double maxW) {
    if (isPlayfulLong && !hasSub) {
      return buildPlayfulStacked(fs, maxW);
    }
    return buildStandardText(fs, maxDisplayLines, maxW);
  }

  return LayoutBuilder(
    builder: (context, constraints) {
      final effectiveMaxW = (maxWidth != null && maxWidth > 0 && maxWidth.isFinite)
          ? maxWidth
          : (constraints.maxWidth.isFinite && constraints.maxWidth > 0
              ? constraints.maxWidth
              : 320.0);

      if (hasSub) {
        final subText = cfg.uppercase ? split.sub!.toUpperCase() : split.sub!;
        final subLen = subText.length;
        final double subScale = (subLen <= 20) ? 1.0 : (subLen <= 35 ? 0.85 : 0.75);
        final subFontSize = (mainFontSize * 0.46 * subScale).clamp(11.0, 16.0);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: crossAlign,
          children: [
            buildStandardText(mainFontSize, 2, effectiveMaxW),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: fittedAlign,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: effectiveMaxW),
                child: Text(
                  subText,
                  textAlign: textAlign,
                  maxLines: 2,
                  softWrap: true,
                  style: AppText.caption.copyWith(
                    fontFamily: cfg.baseStyle.fontFamily ?? 'Rubik',
                    fontSize: subFontSize,
                    fontWeight: FontWeight.w600,
                    letterSpacing: (1.6 * (subLen <= 20 ? 1.0 : 0.5)).clamp(0.4, 1.6),
                    color: Color.lerp(Colors.white70, accent, 0.20) ?? Colors.white70,
                    shadows: const [
                      Shadow(
                        color: Color(0xFF000000),
                        offset: Offset(0, 2),
                        blurRadius: 5,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      }

      return buildMainContent(mainFontSize, effectiveMaxW);
    },
  );
}
