import 'dart:math';
import '../models/media_item.dart';

/// Intelligent title matching and normalization for resolving catalog titles
/// (TMDB, ThePornDB, AniList) to streaming provider items.
class TitleMatcher {
  TitleMatcher._();

  static final RegExp _romanWordRegex = RegExp(
    r'\b(?=[mdclxvi]+\b)(m{0,4}(?:cm|cd|d?c{0,3})(?:xc|xl|l?x{0,3})(?:ix|iv|v?i{0,3}))\b',
    caseSensitive: false,
  );

  static int? _parseRoman(String s) {
    final str = s.toLowerCase();
    if (str.isEmpty) return null;
    const romanValues = {
      'i': 1, 'v': 5, 'x': 10, 'l': 50, 'c': 100, 'd': 500, 'm': 1000
    };
    int total = 0;
    int prev = 0;
    for (int i = str.length - 1; i >= 0; i--) {
      final val = romanValues[str[i]] ?? 0;
      if (val < prev) {
        total -= val;
      } else {
        total += val;
        prev = val;
      }
    }
    return total > 0 ? total : null;
  }

  static final RegExp _noiseWords = RegExp(
    r'\b(volume|vol|v|part|pt|episode|ep|scene|season|no|num|number)\b',
    caseSensitive: false,
  );

  static final RegExp _junkSuffixes = RegExp(
    r'\b(compilation|short clip|teaser|trailer|promo|sample|preview|behind the scenes|bloopers)\b',
    caseSensitive: false,
  );

  static final RegExp _nonAlphaNum = RegExp(r'[^a-z0-9]+');

  /// Convert Roman numerals to decimal digits in title strings.
  static String convertRomanNumerals(String text) {
    return text.replaceAllMapped(_romanWordRegex, (m) {
      final match = m.group(0)!.toLowerCase();
      final val = _parseRoman(match);
      return val != null ? '$val' : match;
    });
  }

  /// Canonicalize a title:
  /// 1. Lowercase
  /// 2. Convert Roman numerals to digits
  /// 3. Strip volume/part/episode noise words
  /// 4. Replace non-alphanumeric chars with spaces and trim
  static String canonicalize(String text) {
    var s = text.toLowerCase();
    s = convertRomanNumerals(s);
    s = s.replaceAll(_noiseWords, ' ');
    s = s.replaceAll(_nonAlphaNum, ' ').trim();
    return s.replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Extract list of meaningful alphanumeric tokens from title.
  static List<String> tokenize(String text) {
    final canon = canonicalize(text);
    if (canon.isEmpty) return const [];
    return canon.split(' ').where((t) => t.isNotEmpty).toList();
  }

  /// Extract list of numeric sequences from title.
  static List<String> extractNumbers(String text) {
    final canon = convertRomanNumerals(text.toLowerCase());
    return RegExp(r'\d+').allMatches(canon).map((m) => m.group(0)!).toList();
  }

  /// Compute normalized Levenshtein similarity between two strings (0.0 to 1.0).
  static double similarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    final d = List.generate(
      s1.length + 1,
      (i) => List<int>.filled(s2.length + 1, 0),
    );

    for (var i = 0; i <= s1.length; i++) {
      d[i][0] = i;
    }
    for (var j = 0; j <= s2.length; j++) {
      d[0][j] = j;
    }

    for (var i = 1; i <= s1.length; i++) {
      for (var j = 1; j <= s2.length; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        d[i][j] = [
          d[i - 1][j] + 1,
          d[i][j - 1] + 1,
          d[i - 1][j - 1] + cost,
        ].reduce(min);
      }
    }

    final maxLen = max(s1.length, s2.length);
    return 1.0 - (d[s1.length][s2.length] / maxLen);
  }

  /// Score how well candidate matches wanted (1.0 = exact, 0.0 = mismatch).
  static double matchScore(String wanted, String candidate, {String? altWanted}) {
    if (wanted.trim().isEmpty || candidate.trim().isEmpty) return 0.0;

    // Check junk suffixes (e.g. "compilation", "teaser", "promo", "trailer")
    final wantedHasJunk = _junkSuffixes.hasMatch(wanted.toLowerCase());
    final candHasJunk = _junkSuffixes.hasMatch(candidate.toLowerCase());
    if (!wantedHasJunk && candHasJunk) return 0.0;

    // Fast path: standard normalized title equality
    final normWanted = normalizeTitle(wanted);
    final normCand = normalizeTitle(candidate);
    if (normWanted == normCand) return 1.0;

    if (altWanted != null && altWanted.trim().isNotEmpty) {
      final normAlt = normalizeTitle(altWanted);
      if (normAlt.isNotEmpty && (normAlt == normCand || normWanted == normalizeTitle(altWanted))) {
        return 1.0;
      }
    }

    // Canonical equality (handles "Vol 10" vs "10", "Part II" vs "2", Roman numerals)
    final canonWanted = canonicalize(wanted);
    final canonCand = canonicalize(candidate);
    if (canonWanted.isNotEmpty && canonWanted == canonCand) return 1.0;

    // Number consistency check: if wanted has numbers (e.g. volume 66),
    // candidate must contain the exact same numbers.
    final wantedNums = extractNumbers(wanted);
    final candNums = extractNumbers(candidate);
    if (wantedNums.isNotEmpty) {
      if (wantedNums.length != candNums.length) {
        if (!wantedNums.every(candNums.contains)) return 0.0;
      } else {
        for (var i = 0; i < wantedNums.length; i++) {
          if (wantedNums[i] != candNums[i]) return 0.0;
        }
      }
    }

    final wantedTokens = tokenize(wanted);
    final candTokens = tokenize(candidate);
    if (wantedTokens.isEmpty || candTokens.isEmpty) return 0.0;

    // Token subset: e.g. "Brazzers - Fantasy 10" contains all tokens of "Fantasy Vol 10"
    final wantedSet = wantedTokens.toSet();
    final candSet = candTokens.toSet();
    if (wantedSet.length >= 2) {
      if (wantedSet.every(candSet.contains) && (candTokens.length - wantedTokens.length).abs() <= 3) {
        return 0.92;
      }
      if (candSet.every(wantedSet.contains) && (wantedTokens.length - candTokens.length).abs() <= 2) {
        return 0.90;
      }
    }

    // Fuzzy string similarity on canonical text
    final sim = similarity(canonWanted, canonCand);
    if (sim >= 0.85) return sim * 0.9;

    return 0.0;
  }

  /// Check whether candidate title matches the wanted title.
  static bool isMatch(String wanted, String candidate, {String? altWanted}) {
    return matchScore(wanted, candidate, altWanted: altWanted) >= 0.70;
  }

  /// Find the best matching item among provider search results.
  static MediaItem? findBestMatch(
    List<MediaItem> results,
    String wanted, {
    String? altTitle,
    int? wantedMalId,
  }) {
    if (results.isEmpty) return null;

    if (wantedMalId != null) {
      for (final m in results) {
        if (m.malId != null && m.malId == wantedMalId) return m;
      }
    }

    MediaItem? best;
    double bestScore = 0.0;

    for (final m in results) {
      final s1 = matchScore(wanted, m.title, altWanted: altTitle);
      final s2 = m.englishTitle != null ? matchScore(wanted, m.englishTitle!, altWanted: altTitle) : 0.0;
      final score = max(s1, s2);
      if (score > bestScore) {
        bestScore = score;
        best = m;
      }
    }

    return bestScore >= 0.70 ? best : null;
  }

  /// Generate fallback search queries for a given title to maximize provider search hits.
  static List<String> searchQueries(String title) {
    final list = <String>[];
    final trimmed = title.trim();
    if (trimmed.isEmpty) return list;

    list.add(trimmed);

    // Canonical version without noise (e.g. "Fantasy Vol 10" -> "Fantasy 10")
    final canon = canonicalize(trimmed);
    if (canon.isNotEmpty && canon.toLowerCase() != trimmed.toLowerCase()) {
      list.add(canon);
    }

    // Base title without trailing numbers/volumes (e.g. "Fantasy Vol 10" -> "Fantasy")
    final withoutNumbers = trimmed.replaceAll(RegExp(r'\s*(vol|volume|pt|part|episode|ep|scene)?\.?\s*\d+\s*$', caseSensitive: false), '').trim();
    if (withoutNumbers.length >= 3 && !list.contains(withoutNumbers)) {
      list.add(withoutNumbers);
    }

    // Strip prefix before hyphen or colon (e.g. "Studio - Title" -> "Title")
    if (trimmed.contains(' - ')) {
      final afterHyphen = trimmed.split(' - ').last.trim();
      if (afterHyphen.length >= 3 && !list.contains(afterHyphen)) {
        list.add(afterHyphen);
      }
    }

    return list;
  }
}
