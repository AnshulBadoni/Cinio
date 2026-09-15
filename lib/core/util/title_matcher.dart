import 'dart:math';
import '../models/media_item.dart';

/// Intelligent title matching and normalization for resolving catalog titles
/// (TMDB, ThePornDB, AniList) to streaming provider items.
class TitleMatcher {
  TitleMatcher._();

  static final RegExp _romanRegex = RegExp(
    r'\b(xx|xix|xviii|xvii|xvi|xv|xiv|xiii|xii|xi|x|ix|viii|vii|vi|v|iv|iii|ii|i)\b',
    caseSensitive: false,
  );

  static final Map<String, String> _romanMap = {
    'i': '1',
    'ii': '2',
    'iii': '3',
    'iv': '4',
    'v': '5',
    'vi': '6',
    'vii': '7',
    'viii': '8',
    'ix': '9',
    'x': '10',
    'xi': '11',
    'xii': '12',
    'xiii': '13',
    'xiv': '14',
    'xv': '15',
    'xvi': '16',
    'xvii': '17',
    'xviii': '18',
    'xix': '19',
    'xx': '20',
  };

  static final RegExp _noiseWords = RegExp(
    r'\b(volume|vol|v|part|pt|episode|ep|scene|season|no|num|number)\b',
    caseSensitive: false,
  );

  static final RegExp _nonAlphaNum = RegExp(r'[^a-z0-9]+');

  /// Convert Roman numerals to decimal digits in title strings.
  static String convertRomanNumerals(String text) {
    return text.replaceAllMapped(_romanRegex, (m) {
      final match = m.group(0)!.toLowerCase();
      return _romanMap[match] ?? match;
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

  /// Check whether candidate title matches the wanted title.
  static bool isMatch(String wanted, String candidate, {String? altWanted}) {
    if (wanted.trim().isEmpty || candidate.trim().isEmpty) return false;

    // Fast path: standard normalized title equality
    final normWanted = normalizeTitle(wanted);
    final normCand = normalizeTitle(candidate);
    if (normWanted == normCand) return true;

    if (altWanted != null && altWanted.trim().isNotEmpty) {
      final normAlt = normalizeTitle(altWanted);
      if (normAlt.isNotEmpty && (normAlt == normCand || normWanted == normalizeTitle(altWanted))) {
        return true;
      }
    }

    // Canonical equality (handles "Vol 10" vs "10", "Part II" vs "2")
    final canonWanted = canonicalize(wanted);
    final canonCand = canonicalize(candidate);
    if (canonWanted.isNotEmpty && canonWanted == canonCand) return true;

    // Number consistency check: if wanted has numbers (e.g. volume 10),
    // candidate must contain the exact same numbers.
    final wantedNums = extractNumbers(wanted);
    final candNums = extractNumbers(candidate);
    if (wantedNums.isNotEmpty) {
      if (wantedNums.length != candNums.length) {
        // If candidate doesn't have the same count of numbers, check set inclusion
        if (!wantedNums.every(candNums.contains)) return false;
      } else {
        for (var i = 0; i < wantedNums.length; i++) {
          if (wantedNums[i] != candNums[i]) return false;
        }
      }
    }

    final wantedTokens = tokenize(wanted);
    final candTokens = tokenize(candidate);
    if (wantedTokens.isEmpty || candTokens.isEmpty) return false;

    // Token subset / inclusion: e.g. "Brazzers - Fantasy 10" contains all tokens of "Fantasy Vol 10"
    final wantedSet = wantedTokens.toSet();
    final candSet = candTokens.toSet();
    if (wantedSet.length >= 2 && (wantedSet.every(candSet.contains) || candSet.every(wantedSet.contains))) {
      return true;
    }

    // Fuzzy string similarity on canonical text (handles minor typos like "Fantay 10" vs "Fantasy 10")
    final sim = similarity(canonWanted, canonCand);
    if (sim >= 0.82) return true;

    return false;
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

    // 1. Exact / canonical match
    for (final m in results) {
      if (isMatch(wanted, m.title, altWanted: altTitle)) return m;
      if (m.englishTitle != null && isMatch(wanted, m.englishTitle!, altWanted: altTitle)) {
        return m;
      }
    }

    return null;
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
