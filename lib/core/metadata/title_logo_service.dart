import 'package:dio/dio.dart';
import 'package:watch_app/core/hive/safe_box.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/media_item.dart';
import '../models/provider_info.dart';
import 'tmdb.dart';

/// Best-effort TMDB "title logo" (the stylized title-art PNG) for a hero item,
/// so the banner can show the logo instead of plain text — CloudStream-style.
/// Resolves by tmdbId when the item has one, else a title search.
///
/// Two-level cache so the logo doesn't "pop in" every time:
///  - in-memory (per session),
///  - Hive ([_boxName], persisted) — keyed by tmdbId/title, value = logo URL
///    ('' means "this title genuinely has no logo", so we don't re-search it).
/// Only RESOLVED results are cached; a network error (e.g. a TMDB reset) is NOT
/// cached, so a later attempt can still succeed once TMDB is reachable. Any
/// failure yields null → the banner keeps its text title.
class TitleLogoService {
  TitleLogoService(this._dio);
  final Dio _dio;

  static const String _boxName = 'logo_cache';

  final Map<String, String> _mem = {}; // '' = known "no logo"
  Box<String>? _boxRef;
  Box<String> get _box => _boxRef ??= Hive.box<String>(_boxName);

  /// Open the persisted cache. Call once in initDependencies before use.
  ///
  /// Resilient: a half-written frame (e.g. the app was killed mid-cache) can make
  /// the box fail — or hang — to open, which would trap the whole app on the
  /// splash. The logo cache is disposable, so on any failure/timeout we wipe it
  /// from disk and reopen fresh instead of blocking boot.
  static Future<void> init() async {
    try {
      await openBoxSafely<String>(_boxName)
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      try {
        await Hive.deleteBoxFromDisk(_boxName);
      } catch (_) {}
      try {
        await openBoxSafely<String>(_boxName);
      } catch (_) {}
    }
  }

  /// Warm logos for the hero carousel up front — SEQUENTIALLY (one TMDB lookup
  /// chain at a time), so it never bursts requests at TMDB (which would trip its
  /// connection-reset rate limit) nor competes for the network all at once. By
  /// the time a banner rotates in, its logo is already cached → no pop-in.
  Future<void> prefetch(List<MediaItem> items) async {
    for (final it in items) {
      try {
        await logoFor(it);
      } catch (_) {/* best-effort */}
    }
  }

  /// Resolve a title logo when a detail object has fresher TMDB identity than
  /// the original browse item. This avoids forcing feature screens to duplicate
  /// the TMDB image lookup/caching rules.
  Future<String?> logoForDetail({
    required String title,
    int? tmdbId,
    bool isTv = false,
    String? year,
    String sourceId = 'tmdb:logo',
  }) async {
    final item = MediaItem(
      id: 'logo:$tmdbId:${isTv ? 'tv' : 'movie'}:$title',
      title: title,
      tmdbId: tmdbId,
      tmdbIsTv: isTv,
      year: year,
      url: '',
      type: ProviderType.movie,
      sourceId: sourceId,
    );
    return logoFor(item);
  }

  Future<String?> logoFor(MediaItem item) async {
    final key = item.tmdbId != null
        ? 'v4:id:${item.tmdbId}:${item.tmdbIsTv}'
        : 'v4:q:${item.sourceId}:${(item.englishTitle ?? item.title).toLowerCase()}:${item.year ?? ''}';

    final cached = _mem[key] ?? _box.get(key);
    if (cached != null) {
      _mem[key] = cached;
      return cached.isEmpty ? null : cached;
    }

    try {
      final url = await _resolve(item).timeout(const Duration(seconds: 5));
      // Cache the resolved result (a URL, or '' for a genuine "no logo").
      final value = url ?? '';
      _mem[key] = value;
      await _box.put(key, value);
      return url;
    } catch (_) {
      // Network error (e.g. a TMDB reset) — do NOT cache, so a later attempt
      // (this session or a future launch) can still resolve the logo.
      return null;
    }
  }


  String _normaliseTitle(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  double _titleSimilarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    if (a.contains(b) || b.contains(a)) {
      final shorter = a.length < b.length ? a.length : b.length;
      final longer = a.length > b.length ? a.length : b.length;
      return 0.82 + (shorter / longer) * 0.16;
    }
    final aa = a.split(' ').toSet();
    final bb = b.split(' ').toSet();
    final intersection = aa.intersection(bb).length;
    final union = aa.union(bb).length;
    final jaccard = union == 0 ? 0.0 : intersection / union;
    return jaccard;
  }

  Future<String?> _resolve(MediaItem item) async {
    int? id = item.tmdbId;
    var isTv = item.tmdbIsTv;
    if (id == null) {
      final q = (item.englishTitle ?? item.title).trim();
      if (q.isEmpty) return null;

      final wanted = _normaliseTitle(q);
      Map? best;
      var bestScore = 0.0;

      Future<void> collect(String kind) async {
        final params = <String, dynamic>{'query': q};
        final parsedYear = int.tryParse((item.year ?? '').trim());
        if (item.sourceId.startsWith('tpdb:') && parsedYear != null) {
          params[kind == 'tv' ? 'first_air_date_year' : 'year'] = parsedYear;
        }
        try {
          final response = await _dio.get<dynamic>(
            '${Tmdb.base}/search/$kind',
            queryParameters: params,
            options: Options(validateStatus: (c) => c != null && c < 500),
          );
          final results = response.data is Map ? response.data['results'] : null;
          if (results is! List) return;
          for (final r in results) {
            if (r is! Map) continue;
            final candidate = (r['title'] ?? r['name'])?.toString() ?? '';
            final score = _titleSimilarity(wanted, _normaliseTitle(candidate));
            if (score > bestScore) {
              bestScore = score;
              best = r;
              best = {...r, 'media_type': kind};
            }
          }
        } catch (_) {}
      }

      // TPDB titles are overwhelmingly movies/series with names that can be
      // matched more reliably when movie and TV search are scored separately.
      // Running the two small searches in parallel keeps this from becoming a
      // serial source of UI latency.
      await Future.wait([collect('movie'), collect('tv')]);
      final threshold = item.sourceId.startsWith('tpdb:') ? 0.88 : 0.62;
      final match = best;
      if (match == null || bestScore < threshold) return null;
      id = (match['id'] as num?)?.toInt();
      isTv = match['media_type'] == 'tv';
      if (id == null) return null;
    }
    final kind = isTv ? 'tv' : 'movie';
    // Ask TMDB for the complete logo set instead of filtering to en/null at
    // request time. A surprising number of titles only have a logo tagged in
    // their original language, and filtering those out made the hero silently
    // fall back to plain text. We still rank English first when it exists.
    final imgs = await _dio.get<dynamic>(
      '${Tmdb.base}/$kind/$id/images',
      options: Options(validateStatus: (c) => c != null && c < 500),
    );
    final logos = (imgs.data is Map) ? imgs.data['logos'] : null;
    if (logos is! List || logos.isEmpty) return null;
    final candidates = [for (final l in logos) if (l is Map) l];
    candidates.sort((a, b) {
      int languageScore(Map m) {
        final language = m['iso_639_1']?.toString();
        if (language == 'en') return 4;
        if (language == null || language.isEmpty) return 3;
        return 2;
      }
      final language = languageScore(b).compareTo(languageScore(a));
      if (language != 0) return language;
      final av = (a['vote_average'] as num?)?.toDouble() ?? 0;
      final bv = (b['vote_average'] as num?)?.toDouble() ?? 0;
      if (av != bv) return bv.compareTo(av);
      final aw = (a['width'] as num?)?.toInt() ?? 0;
      final bw = (b['width'] as num?)?.toInt() ?? 0;
      return bw.compareTo(aw);
    });
    for (final candidate in candidates) {
      final path = candidate['file_path']?.toString();
      if (path != null && path.isNotEmpty) {
        return '${Tmdb.img}/w1280$path';
      }
    }
    return null;
  }
}
