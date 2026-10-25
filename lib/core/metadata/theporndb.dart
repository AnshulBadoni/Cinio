import 'package:dio/dio.dart';
import '../di/injector.dart';
import '../models/episode.dart';
import '../models/home_section.dart';
import '../models/media_detail.dart';
import '../models/media_extras.dart';
import '../models/media_item.dart';
import '../models/person.dart';
import '../models/provider_info.dart';
import '../prefs/catalog_source_prefs.dart';

/// ThePornDB-backed catalog. It is catalog/metadata only; playback is still
/// resolved by the normal streaming-provider pipeline.
class ThePornDb {
  ThePornDb(this._dio);

  final Dio _dio;

  bool get _shouldFilter =>
      sl.isRegistered<CatalogSourcePrefs>()
          ? sl<CatalogSourcePrefs>().tpdbFilterOldAndGay
          : true;

  static const String base = 'https://api.theporndb.net';
  // Temporary development key. Replace this before the production release.
  static const String apiKey = '8ABvbgloweVLDeD3HBq6x9eHpL3lMJE8qEuBtdmb213d0c62';

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, dynamic>? queryParameters,
    int retryCount = 0,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        '$base$path',
        queryParameters: queryParameters,
        options: Options(
          headers: {'Authorization': 'Bearer $apiKey'},
          listFormat: ListFormat.multi,
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
          connectTimeout: const Duration(seconds: 8),
        ),
      );
      if (response.data is! Map) return const {};
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      if (e.response?.statusCode == 429 && retryCount < 3) {
        await Future.delayed(Duration(milliseconds: 1500 * (retryCount + 1)));
        return _get(path, queryParameters: queryParameters, retryCount: retryCount + 1);
      }
      rethrow;
    }
  }

  static final RegExp _excludedTitleRegex = RegExp(
    r'\b(gay|male[\s\-]on[\s\-]male|male/male|m/m|shemale|ladyboy|transgender|femboy|sissy|tranny|crossdresser|granny|gilf|grandma|elderly|geriatric|senior|old[\s\-]man|old[\s\-]guy|old[\s\-]dude|old[\s\-]woman|old[\s\-]lady|older[\s\-]man|older[\s\-]woman|old\s*/\s*young|young\s*/\s*old)\b',
    caseSensitive: false,
  );

  static const Set<String> _excludedTagNames = {
    'gay',
    'male-on-male',
    'male on male',
    'male/male',
    'mm',
    'm/m',
    'bisexual male',
    'shemale',
    'trans',
    'transgender',
    'ladyboy',
    'crossdresser',
    'femboy',
    'sissy',
    'tranny',
    'mature',
    'granny',
    'gilf',
    'grandma',
    'elderly',
    'senior',
    'geriatric',
    'vintage',
    'wrinkled',
    'old / young',
    'old/young',
    'young / old',
    'young/old',
    'old man',
    'old guy',
    'old woman',
    'older man',
    'older woman',
  };

  bool _qualifiesMedia(Map row) {
    if (!_shouldFilter) return true;
    // 1. Check title
    final title = (row['title'] ?? row['name'] ?? '').toString();
    if (_excludedTitleRegex.hasMatch(title)) {
      return false;
    }

    // 2. Check tags / genres
    final tags = _names(row['tags'] ?? row['genres']);
    for (final tag in tags) {
      final clean = tag.trim().toLowerCase();
      if (_excludedTagNames.contains(clean) || _excludedTitleRegex.hasMatch(clean)) {
        return false;
      }
    }

    // 3. Check performers if available
    final performers = row['performers'];
    if (performers is List && performers.isNotEmpty) {
      var hasFemale = false;
      var hasIdentifiedGender = false;
      for (final p in performers) {
        if (p is! Map) continue;
        final extras = p['extras'];
        final gender = '${p['gender'] ?? (extras is Map ? extras['gender'] : '')}'.trim().toUpperCase();
        if (gender == 'FEMALE' || gender == 'F') {
          hasFemale = true;
          hasIdentifiedGender = true;
        } else if (gender == 'MALE' || gender == 'M') {
          hasIdentifiedGender = true;
        } else if (gender.contains('TRANS') || gender == 'SHEMALE') {
          return false;
        }

        final birthday = p['birthday'] ?? (extras is Map ? extras['birthday'] : null);
        final age = double.tryParse('${p['age'] ?? (extras is Map ? extras['age'] : '')}');
        final born = birthday?.toString();
        final derivedAge = age ?? (born != null && born.length >= 4
            ? (DateTime.now().year - (int.tryParse(born.substring(0, 4)) ?? DateTime.now().year)).toDouble()
            : null);
        if (derivedAge != null && derivedAge >= 50) {
          return false;
        }
      }
      // If genders were identified and none were female, it's male-only/gay
      if (hasIdentifiedGender && !hasFemale) {
        return false;
      }
    }

    return true;
  }

  bool _qualifiesStudio(Map row) {
    if (!_shouldFilter) return true;
    final name = (row['name'] ?? row['short_name'] ?? '').toString();
    if (_excludedTitleRegex.hasMatch(name)) return false;
    final tags = _names(row['tags'] ?? row['genres']);
    for (final tag in tags) {
      final clean = tag.trim().toLowerCase();
      if (_excludedTagNames.contains(clean) || _excludedTitleRegex.hasMatch(clean)) {
        return false;
      }
    }
    return true;
  }

  Future<List<MediaItem>> movies({
    int page = 1,
    String orderBy = 'recently_released',
    String? query,
  }) async {
    final baseQuery = <String, dynamic>{
      'page': page,
      'per_page': 16,
      'orderBy': orderBy,
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
    };

    // TPDB documents performer_genders as a normal query array with
    // `Female`/`Male` values. `performer_gender_only=true` means the result
    // may contain only those performer genders. Do NOT combine this with
    // performer_gender_and: that flag asks for all selected genders to be
    // present in a result, which is not the same thing as straight-only and
    // can reduce the catalog to an empty result set.
    final filteredQuery = <String, dynamic>{
      ...baseQuery,
      if (_shouldFilter) ...await _straightFilterQuery(),
    };

    final data = await _get('/movies', queryParameters: filteredQuery);
    final rows = data['data'];
    if (rows is! List) return const <MediaItem>[];
    return [
      for (final row in rows)
        if (row is Map && _qualifiesMedia(row)) _movie(row),
    ];
  }


  Future<Map<String, dynamic>> _straightFilterQuery() async {
    if (!_shouldFilter) return const {};
    return {
      'performer_genders[Female]': 'Female',
    };
  }

  Future<List<MediaItem>> trendingPerformers({int page = 1}) async {
    final data = await _get('/scenes', queryParameters: {
      'page': page,
      'per_page': 50,
      'orderBy': 'recently_released',
      ...await _straightFilterQuery(),
    });
    final rows = data['data'];
    if (rows is! List) return const [];
    final seen = <String>{};
    final out = <MediaItem>[];
    for (final scene in rows) {
      if (scene is! Map || scene['performers'] is! List) continue;
      if (!_qualifiesMedia(scene)) continue;
      for (final performer in scene['performers'] as List) {
        if (performer is! Map) continue;
        if (!_qualifiesAsActor(performer, requireRating: false)) continue;
        final id = (performer['id'] ?? performer['_id'] ?? performer['slug']).toString();
        if (!seen.add(id)) continue;
        out.add(_performer(performer));
        if (out.length >= 24) return out;
      }
    }
    return out;
  }

  static final RegExp _seriesRegex = RegExp(
    r'(\bpart\s*\d+|\bpt\.?\s*\d+|\bvol(ume)?\.?\s*\d+|\bseason\s*\d+|\bep(isode)?\.?\s*\d+|#\s*\d+|\b\d+\s*$)',
    caseSensitive: false,
  );

  static bool isSeriesTitle(String title) {
    return _seriesRegex.hasMatch(title);
  }

  static const List<String> _curatedTrendingStudios = [
    'Brazzers',
    'Blacked',
    'Vixen',
  ];

  static List<MediaItem>? _curatedTrendingMoviesCache;

  Future<List<MediaItem>> trendingMovies({int page = 1}) async {
    if (_curatedTrendingMoviesCache == null || _curatedTrendingMoviesCache!.isEmpty) {
      final items = <MediaItem>[];
      final seenIds = <String>{};

      await Future.wait(
        _curatedTrendingStudios.map((studio) async {
          try {
            final data = await _get('/movies', queryParameters: {
              'q': studio,
              'per_page': 8,
            });
            final rows = data['data'];
            if (rows is List) {
              for (final row in rows) {
                if (row is Map && _qualifiesMedia(row)) {
                  final movie = _movie(row);
                  if (seenIds.add(movie.id)) {
                    items.add(movie);
                  }
                }
              }
            }
          } catch (_) {}
        }),
      );

      if (items.isNotEmpty) {
        _curatedTrendingMoviesCache = List.from(items);
      }
    }

    final cached = _curatedTrendingMoviesCache ?? const [];
    final pageSize = 16;
    final start = (page - 1) * pageSize;
    if (start < cached.length) {
      final end = (start + pageSize).clamp(0, cached.length);
      final slice = cached.sublist(start, end);
      if (slice.isNotEmpty) return slice;
    }

    return movies(page: page, orderBy: 'recently_updated');
  }

  static const List<String> _curatedPopularIcons = [
    'Angela White',
    'Riley Reid',
  ];

  static List<MediaItem>? _curatedPopularMoviesCache;

  Future<List<MediaItem>> popularMovies({int page = 1}) async {
    if (_curatedPopularMoviesCache == null || _curatedPopularMoviesCache!.isEmpty) {
      final items = <MediaItem>[];
      final seenIds = <String>{};

      await Future.wait(
        _curatedPopularIcons.map((performer) async {
          try {
            final data = await _get('/movies', queryParameters: {
              'q': performer,
              'per_page': 8,
            });
            final rows = data['data'];
            if (rows is List) {
              for (final row in rows) {
                if (row is Map && _qualifiesMedia(row)) {
                  final movie = _movie(row);
                  if (seenIds.add(movie.id)) {
                    items.add(movie);
                  }
                }
              }
            }
          } catch (_) {}
        }),
      );

      if (items.isNotEmpty) {
        _curatedPopularMoviesCache = List.from(items);
      }
    }

    final cached = _curatedPopularMoviesCache ?? const [];
    final pageSize = 16;
    final start = (page - 1) * pageSize;
    if (start < cached.length) {
      final end = (start + pageSize).clamp(0, cached.length);
      final slice = cached.sublist(start, end);
      if (slice.isNotEmpty) return slice;
    }

    return movies(page: page, orderBy: 'recently_created');
  }

  static const List<String> _curatedMainstreamPerformers = [
    'Gianna Michaels',
    'Lena Paul',
    'Sweetie Fox',
    'Leah Gotti',
    'Janice Griffith',
    'Vina Sky',
    'Emily Willis',
    'Gabbie Carter',
    'Mia Malkova',
    'Eva Elfie',
    'Alexis Texas',
    'Lisa Ann',
    'Riley Reid',
    'Violet Myers',
    'Adriana Chechik',
    'Tori Black',
    'Lana Rhoades',
    'Angela White',
    'Maitland Ward',
    'Blake Blossom',
    'Dillion Harper',
    'Dani Daniels',
    'Kenzie Reeves',
    'Alina Lopez',
    'La Sirena 69',
    'Lasirena69',
    'Aletta Ocean',
    'Kendra Lust',
    'Nicole Aniston',
    'Autumn Falls',
    'Abella Danger',
    'Katrina Jade',
    'Cory Chase',
    'Brandi Love',
  ];

  static List<MediaItem>? _curatedPerformersCache;

  Future<List<MediaItem>> _fetchCuratedPerformers() async {
    if (_curatedPerformersCache != null && _curatedPerformersCache!.isNotEmpty) {
      return List<MediaItem>.from(_curatedPerformersCache!);
    }

    final items = <MediaItem>[];
    final seenNames = <String>{};

    const batchSize = 6;
    for (var i = 0; i < _curatedMainstreamPerformers.length; i += batchSize) {
      final batch = _curatedMainstreamPerformers.sublist(
        i,
        (i + batchSize).clamp(0, _curatedMainstreamPerformers.length),
      );
      await Future.wait(
        batch.map((name) async {
          try {
            final data = await _get('/performers', queryParameters: {
              'q': name,
              'per_page': 1,
            });
            final rows = data['data'];
            if (rows is List && rows.isNotEmpty && rows.first is Map) {
              final row = rows.first as Map;
              if (_qualifiesAsActor(row, requireRating: true)) {
                final p = _performer(row);
                if (p.rating != null && p.rating! > 0 && seenNames.add(p.title.toLowerCase())) {
                  items.add(p);
                }
              }
            }
          } catch (_) {}
        }),
      );
      if (i + batchSize < _curatedMainstreamPerformers.length) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    items.sort((a, b) {
      final ra = a.rating ?? 0.0;
      final rb = b.rating ?? 0.0;
      return rb.compareTo(ra);
    });

    if (items.isNotEmpty) {
      _curatedPerformersCache = List.from(items);
    }
    return items;
  }

  Future<List<MediaItem>> performers({
    int page = 1,
    String orderBy = 'most_relevant',
    String? query,
  }) async {
    final isSearch = query != null && query.trim().isNotEmpty;

    // Normal browse: return mainstream rated performers sorted descending by rating
    if (!isSearch) {
      final curated = await _fetchCuratedPerformers();
      if (curated.isNotEmpty) {
        final pageSize = 24;
        final start = (page - 1) * pageSize;
        if (start < curated.length) {
          final end = (start + pageSize).clamp(0, curated.length);
          final pageSlice = curated.sublist(start, end);
          if (pageSlice.isNotEmpty) {
            return pageSlice;
          }
        }
      }
    }

    final data = await _get('/performers', queryParameters: {
      'page': page,
      'per_page': 50,
      'orderBy': orderBy,
      if (isSearch) 'q': query.trim(),
    });
    final rows = data['data'];
    if (rows is! List) return const [];
    final list = <MediaItem>[];
    for (final row in rows) {
      if (row is Map && _qualifiesAsActor(row, requireRating: !isSearch)) {
        list.add(_performer(row));
      }
    }
    // Replenish if filter reduced count on normal browse so row is full of mainstream rated actors
    if (list.length < 24 && !isSearch && rows.isNotEmpty) {
      for (var p = page + 1; p <= page + 3 && list.length < 24; p++) {
        try {
          final nextData = await _get('/performers', queryParameters: {
            'page': p,
            'per_page': 50,
            'orderBy': orderBy,
          });
          final nextRows = nextData['data'];
          if (nextRows is List) {
            for (final row in nextRows) {
              if (row is Map && _qualifiesAsActor(row, requireRating: !isSearch)) {
                list.add(_performer(row));
                if (list.length >= 28) break;
              }
            }
          }
        } catch (_) {}
      }
    }
    // Sort performers with highest rating first, decreasing from the start
    list.sort((a, b) {
      final ra = a.rating;
      final rb = b.rating;
      if (ra != null && rb != null) return rb.compareTo(ra);
      if (ra != null && rb == null) return -1;
      if (ra == null && rb != null) return 1;
      return 0;
    });

    return list;
  }

  int _extractPerformerVideoCount(Map row) {
    for (final key in [
      'scenes_count',
      'videos_count',
      'scene_count',
      'video_count',
      'movies_count',
      'total_scenes',
      'scenesCount',
      'videosCount',
      'count',
    ]) {
      final val = row[key];
      if (val is num && val > 0) return val.toInt();
      if (val != null) {
        final parsed = int.tryParse(val.toString());
        if (parsed != null && parsed > 0) return parsed;
      }
    }
    final extras = row['extras'];
    if (extras is Map) {
      for (final key in [
        'scenes_count',
        'videos_count',
        'scene_count',
        'video_count',
        'movies_count',
      ]) {
        final val = extras[key];
        if (val is num && val > 0) return val.toInt();
        if (val != null) {
          final parsed = int.tryParse(val.toString());
          if (parsed != null && parsed > 0) return parsed;
        }
      }
    }
    final scenes = row['scenes'];
    if (scenes is List && scenes.isNotEmpty) return scenes.length;
    final sps = row['site_performers'];
    if (sps is List && sps.isNotEmpty) return sps.length;

    // Check if explicitly 0
    if (row['scenes_count'] == 0 || row['videos_count'] == 0 || row['movies_count'] == 0) {
      return 0;
    }
    if (extras is Map && (extras['scenes_count'] == 0 || extras['videos_count'] == 0)) {
      return 0;
    }
    if (sps is List && sps.isEmpty) return 0;
    if (scenes is List && scenes.isEmpty) return 0;

    return 1;
  }

  double? _extractPerformerRating(Map row) {
    final direct = double.tryParse('${row['rating'] ?? row['score'] ?? ''}');
    if (direct != null && direct > 0) return direct;
    final extras = row['extras'];
    if (extras is Map) {
      final r = double.tryParse('${extras['rating'] ?? extras['score'] ?? ''}');
      if (r != null && r > 0) return r;
    }
    final sps = row['site_performers'];
    if (sps is List) {
      double? best;
      for (final s in sps) {
        if (s is Map) {
          final sr = double.tryParse('${s['rating'] ?? ''}');
          if (sr != null && sr > 0) {
            if (best == null || sr > best) best = sr;
          }
        }
      }
      if (best != null) return best;
    }
    return null;
  }

  bool _qualifiesAsActor(Map row, {bool requireRating = true}) {
    if (!_shouldFilter) return true;
    final rating = _extractPerformerRating(row);

    // User request: remove non-rated ones; keep mainstream high-rated performers
    if (requireRating && (rating == null || rating < 3.8)) {
      return false;
    }

    // User request: mainstream performers not with 0 videos
    if (_extractPerformerVideoCount(row) <= 0) {
      return false;
    }

    // Mainstream performers must have an official poster / photo
    final poster = _extractPerformerPoster(row) ?? _firstImage(row) ?? _extractUrl(row['image']) ?? _extractUrl(row['thumbnail']) ?? _extractUrl(row['face']);
    if (poster == null || poster.isEmpty) {
      return false;
    }

    final extras = row['extras'];
    final gender = '${row['gender'] ?? (extras is Map ? extras['gender'] : '')}'.trim().toUpperCase();
    final birthday = row['birthday'] ?? (extras is Map ? extras['birthday'] : null);
    final age = double.tryParse('${row['age'] ?? (extras is Map ? extras['age'] : '')}');
    final born = birthday?.toString();
    final derivedAge = age ?? (born != null && born.length >= 4
        ? (DateTime.now().year - (int.tryParse(born.substring(0, 4)) ?? DateTime.now().year)).toDouble()
        : null);

    final name = (row['name'] ?? row['full_name'] ?? '').toString();
    if (_excludedTitleRegex.hasMatch(name)) return false;

    final tags = _names(row['tags'] ?? row['genres']);
    for (final tag in tags) {
      final clean = tag.trim().toLowerCase();
      if (_excludedTagNames.contains(clean) || _excludedTitleRegex.hasMatch(clean)) {
        return false;
      }
    }

    if (gender == 'MALE' || gender == 'TRANSGENDER' || (gender.contains('MALE') && !gender.contains('FEMALE'))) {
      return false;
    }

    return (gender.isEmpty || gender == 'FEMALE' || gender == 'F') &&
        (derivedAge == null || derivedAge < 50);
  }

  Future<List<MediaItem>> studios({int page = 1, String? query}) async {
    final isSearch = query != null && query.trim().isNotEmpty;
    var data = await _get('/sites', queryParameters: {
      'page': page,
      'per_page': 24,
      'orderBy': 'most_relevant',
      if (isSearch) 'q': query.trim(),
    });
    var rows = data['data'];
    if (rows is! List || rows.isEmpty) {
      data = await _get('/sites', queryParameters: {
        'page': page,
        'per_page': 24,
        if (isSearch) 'q': query.trim(),
      });
      rows = data['data'];
    }
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map && _qualifiesStudio(row)) _studio(row),
    ];
  }

  /// Builds the ThePornDB Home rows in order: Recent, Trending, Actors, Popular, Top Rated.
  /// Uses genuinely distinct ordering across sections so lists are fresh and don't repeat.
  Future<List<HomeSection>> home() async {
    final results = await Future.wait([
      _safe(() => movies(orderBy: 'recently_released')), // 0: Recent
      _safe(() => trendingMovies()), // 1: Trending
      _safe(() => performers()), // 2: Actors
      _safe(() => popularMovies()), // 3: Popular
      _safe(() => _topRated(1)), // 4: Top Rated
    ]);

    final recentItems = results[0];
    final recentIds = recentItems.map((m) => m.id).toSet();
    final trendingItems = results[1].where((m) => !recentIds.contains(m.id)).toList();

    return [
      HomeSection(title: 'Recent', items: recentItems, more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_recent')),
      HomeSection(title: 'Trending', items: trendingItems.isNotEmpty ? trendingItems : results[1], more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_trending')),
      HomeSection(title: 'Actors', items: results[2], more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_performers')),
      HomeSection(title: 'Popular', items: results[3], more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_popular')),
      HomeSection(title: 'Top Rated', items: results[4], more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_top_rated')),
    ].where((section) => section.items.isNotEmpty).toList();
  }

  Future<HomeSection?> homeSection(String kind) async {
    final items = switch (kind) {
      'tpdb_recent' => await movies(orderBy: 'recently_released'),
      'tpdb_trending' => await trendingMovies(),
      'tpdb_performers' => await performers(),
      'tpdb_popular' => await popularMovies(),
      'tpdb_top_rated' => await _topRated(1),
      'tpdb_studios' => await studios(),
      _ => const <MediaItem>[],
    };
    if (items.isEmpty) return null;
    final title = switch (kind) {
      'tpdb_recent' => 'Recent',
      'tpdb_trending' => 'Trending',
      'tpdb_performers' => 'Actors',
      'tpdb_popular' => 'Popular',
      'tpdb_top_rated' => 'Top Rated',
      'tpdb_studios' => 'Studio',
      _ => '',
    };
    return HomeSection(title: title, items: items, more: BrowseMore(sourceId: 'tpdb:catalog', kind: kind));
  }

  Future<List<MediaItem>> _safe(Future<List<MediaItem>> Function() loader) async {
    try { return await loader(); } catch (_) { return const []; }
  }

  Future<List<MediaItem>> browseMore(String kind, int page) => switch (kind) {
        'tpdb_recent' => movies(page: page, orderBy: 'recently_released'),
        'tpdb_trending' => trendingMovies(page: page),
        'tpdb_popular' => popularMovies(page: page),
        'tpdb_top_rated' => _topRated(page),
        'tpdb_performers' => performers(page: page),
        'tpdb_studios' => studios(page: page),
        _ => Future.value(const []),
      };

  Future<List<MediaItem>> search(String query, {int page = 1}) async {
    final clean = query.trim();
    if (clean.isEmpty) return const [];
    if (page > 1) {
      return movies(page: page, query: clean, orderBy: 'most_relevant');
    }
    final results = await Future.wait([
      _safe(() => performers(page: 1, query: clean)),
      _safe(() => studios(page: 1, query: clean)),
      _safe(() => movies(page: 1, query: clean, orderBy: 'most_relevant')),
    ]);
    final perfList = results[0];
    final studList = results[1];
    final movList = results[2];

    return [
      ...perfList,
      ...studList,
      ...movList,
    ];
  }

  Future<MediaDetail> movieDetail(MediaItem item) async {
    final isScene = item.id.startsWith('tpdb:scene:');
    final rawId = item.id
        .replaceFirst('tpdb:movie:', '')
        .replaceFirst('tpdb:scene:', '')
        .replaceFirst('tpdb:performer:', '')
        .replaceFirst('tpdb:studio:', '')
        .replaceFirst('tpdb:', '');

    Map<String, dynamic> data = const {};
    if (isScene) {
      try {
        data = await _get('/scenes/$rawId');
        if (data['data'] == null) {
          data = await _get('/movies/$rawId');
        }
      } catch (_) {
        data = await _get('/movies/$rawId');
      }
    } else {
      try {
        data = await _get('/movies/$rawId');
        if (data['data'] == null) {
          data = await _get('/scenes/$rawId');
        }
      } catch (_) {
        data = await _get('/scenes/$rawId');
      }
    }

    final row = data['data'] is Map
        ? data['data'] as Map
        : (data['data'] is List && (data['data'] as List).isNotEmpty ? data['data'][0] as Map : const {});
    final performers = row['performers'];
    final cast = <String>[];
    final members = <CastMember>[];
    if (performers is List) {
      for (final p in performers) {
        if (p is! Map) continue;
        final parent = p['parent'] is Map ? p['parent'] as Map : null;
        final name = (parent?['name'] ?? parent?['full_name'] ?? p['name'] ?? p['full_name'])?.toString();
        if (name == null || name.isEmpty) continue;
        final rawPid = (parent?['id'] ?? parent?['uuid'] ?? parent?['_id'] ?? parent?['slug'] ?? p['id'] ?? p['uuid'] ?? p['_id'] ?? p['slug'])?.toString();
        final photo = _extractPerformerPoster(parent ?? p) ?? _extractUrl(parent?['image']) ?? _extractUrl(parent?['thumbnail']) ?? _extractUrl(parent?['face']) ?? _extractUrl(p['image']) ?? _extractUrl(p['thumbnail']) ?? _extractUrl(p['face']) ?? _firstImage(p);
        cast.add(name);
        if (rawPid != null && rawPid.isNotEmpty) {
          members.add(CastMember(
            name: name,
            photo: photo,
            person: PersonRef(
              id: int.tryParse((parent?['_id'] ?? p['_id'])?.toString() ?? '') ?? 0,
              externalId: rawPid,
              source: PersonSource.thePornDbPerformer,
              name: name,
              photo: photo,
            ),
          ));
        } else {
          members.add(CastMember(name: name, photo: photo));
        }
      }
    }
    final cover = _firstImage(row) ?? _firstHeroImage(row) ?? item.cover;
    final ep = Episode(
      id: item.id,
      number: 1,
      title: (row['title'] ?? item.title).toString(),
      url: item.url,
      thumbnail: cover,
      description: (row['description'] ?? row['synopsis'])?.toString(),
    );
    final title = (row['title'] ?? item.title).toString();
    final isSeries = isSeriesTitle(title);
    return MediaDetail(
      id: item.id,
      title: title,
      description: (row['description'] ?? row['synopsis'])?.toString(),
      cover: cover,
      url: item.url,
      year: _year(row['date'] ?? row['release_date']),
      type: ProviderType.movie,
      sourceId: 'tpdb:catalog',
      genres: _names(row['tags'] ?? row['genres']),
      studios: _studioNames(row),
      cast: cast,
      castMembers: members,
      episodes: [ep],
      isSeries: isSeries,
      tmdbIsTv: isSeries,
    );
  }

  Future<List<MediaItem>> _topRated(int page) async {
    final items = await movies(page: page, orderBy: 'recently_updated');
    return [...items]..sort((a, b) => _rating(b).compareTo(_rating(a)));
  }

  MediaItem _movie(Map row) {
    final id = (row['id'] ?? row['_id'] ?? row['uuid'] ?? row['slug']).toString();
    final title = (row['title'] ?? row['name'] ?? 'Untitled').toString();
    final isSeries = isSeriesTitle(title);
    final rawRating = (row['rating'] as num?)?.toDouble() ??
        (row['score'] as num?)?.toDouble() ??
        (row['site'] is Map ? (row['site']['rating'] as num?)?.toDouble() : null);
    final rating = (rawRating != null && rawRating > 0) ? rawRating : null;
    return MediaItem(
      id: 'tpdb:movie:$id',
      title: title,
      cover: _firstImage(row),
      heroImage: _firstHeroImage(row),
      url: 'tpdb://movie/$id',
      type: ProviderType.movie,
      sourceId: 'tpdb:catalog',
      genres: _names(row['tags']),
      rating: rating,
      year: _year(row['date'] ?? row['release_date']),
      tmdbIsTv: isSeries,
    );
  }

  MediaItem _performer(Map row) {
    final id = (row['id'] ?? row['_id'] ?? row['slug']).toString();
    final rating = _extractPerformerRating(row);
    return MediaItem(
      id: 'tpdb:performer:$id',
      title: (row['name'] ?? row['full_name'] ?? 'Performer').toString(),
      cover: _extractPerformerPoster(row) ?? _firstImage(row) ?? _extractUrl(row['image']) ?? _extractUrl(row['thumbnail']) ?? _extractUrl(row['face']),
      url: 'https://theporndb.net/performers/$id',
      type: ProviderType.movie,
      sourceId: 'tpdb:performer',
      rating: rating,
    );
  }

  String? _extractPerformerPoster(Map? row) {
    if (row == null) return null;
    final posters = row['posters'];
    if (posters is List && posters.isNotEmpty) {
      for (final p in posters) {
        if (p is Map) {
          final u = p['url'] ?? p['image'];
          if (u != null && u.toString().startsWith('http')) return u.toString();
        } else if (p is String && p.startsWith('http')) {
          return p;
        }
      }
    }
    final img = row['image']?.toString();
    if (img != null && img.startsWith('http')) return img;
    final sps = row['site_performers'];
    if (sps is List && sps.isNotEmpty) {
      for (final sp in sps) {
        if (sp is Map) {
          final u = sp['image'];
          if (u != null && u.toString().startsWith('http')) return u.toString();
        }
      }
    }
    return null;
  }

  MediaItem _studio(Map row) {
    final id = (row['id'] ?? row['uuid'] ?? row['short_name']).toString();
    return MediaItem(
      id: 'tpdb:studio:$id',
      title: (row['name'] ?? 'Studio').toString(),
      cover: _firstImage(row) ?? _extractUrl(row['logo']) ?? _extractUrl(row['poster']) ?? _extractUrl(row['favicon']),
      url: 'https://theporndb.net/sites/$id',
      type: ProviderType.movie,
      sourceId: 'tpdb:studio',
    );
  }

  String? _year(Object? value) {
    final s = value?.toString() ?? '';
    return s.length >= 4 ? s.substring(0, 4) : null;
  }

  String? _extractUrl(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final s = value.trim();
      if (s.isEmpty || s.startsWith('{') || s.startsWith('[')) return null;
      return s;
    }
    if (value is Map) {
      for (final k in [
        'full',
        'large',
        'original',
        'medium',
        'small',
        'url',
        'src',
        'poster',
        'image',
        'thumbnail',
      ]) {
        final res = _extractUrl(value[k]);
        if (res != null) return res;
      }
    }
    if (value is List) {
      for (final item in value) {
        final res = _extractUrl(item);
        if (res != null) return res;
      }
    }
    return null;
  }

  String? _firstHeroImage(Map row) {
    for (final key in [
      'background',
      'backgrounds',
      'backdrop',
      'backdrops',
      'backdrop_image',
      'background_image',
      'banner',
      'landscape',
      'fanart',
      'image',
      'poster',
      'posters',
    ]) {
      final val = _extractUrl(row[key]);
      if (val != null) return val;
    }
    return null;
  }

  String? _firstImage(Map row) {
    for (final key in [
      'poster',
      'poster_image',
      'posters',
      'image',
      'images',
      'thumbnail',
      'thumb',
      'face',
      'cover',
      'logo',
      'background',
    ]) {
      final val = _extractUrl(row[key]);
      if (val != null) return val;
    }
    return null;
  }

  List<String> _names(dynamic value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map && item['name'] != null) item['name'].toString(),
    ];
  }

  List<String> _studioNames(Map row) {
    final raw = row['site'] ?? row['studio'] ?? row['studios'];
    if (raw is Map) {
      final n = raw['name']?.toString();
      return n == null || n.isEmpty ? const [] : [n];
    }
    if (raw is List) {
      return [
        for (final v in raw)
          if (v is Map && v['name'] != null) v['name'].toString()
          else if (v != null && v.toString().isNotEmpty) v.toString(),
      ];
    }
    return raw == null || raw.toString().isEmpty ? const [] : [raw.toString()];
  }

  double _rating(MediaItem item) => item.rating ?? 0;

  /// Fetches a direct official trailer stream URL from ThePornDB for an item id,
  /// title, performer, or studio. Returns null if no trailer is indexed.
  Future<String?> fetchTrailer({
    String? id,
    String? title,
    String? performer,
    String? studio,
  }) async {
    try {
      if (id != null && id.isNotEmpty) {
        final rawId = id.replaceFirst(RegExp(r'^tpdb:(movie|scene|performer|studio):'), '');
        if (id.contains('scene')) {
          final data = await _get('/scenes/$rawId');
          final row = data['data'] is Map ? data['data'] as Map : null;
          final tr = _extractTrailer(row);
          if (tr != null) return tr;
        } else if (id.contains('movie')) {
          final data = await _get('/movies/$rawId');
          final row = data['data'] is Map ? data['data'] as Map : null;
          final tr = _extractTrailer(row);
          if (tr != null) return tr;
          final scenes = row?['scenes'];
          if (scenes is List && scenes.isNotEmpty) {
            for (final s in scenes) {
              if (s is Map) {
                final str = _extractTrailer(s);
                if (str != null) return str;
              }
            }
          }
        }
      }

      final q = title ?? performer ?? studio;
      if (q != null && q.trim().isNotEmpty) {
        final clean = q.trim();
        // 1. Check scenes first — primary location for official studio trailers in TPDB
        final sceneData = await _get('/scenes', queryParameters: {
          'q': clean,
          'per_page': 5,
          'orderBy': 'most_relevant',
        });
        final sceneRows = sceneData['data'];
        if (sceneRows is List) {
          for (final row in sceneRows) {
            if (row is Map) {
              final tr = _extractTrailer(row);
              if (tr != null) return tr;
            }
          }
        }

        // 2. Check movies if scene trailer not found
        final movieData = await _get('/movies', queryParameters: {
          'q': clean,
          'per_page': 5,
          'orderBy': 'most_relevant',
        });
        final movieRows = movieData['data'];
        if (movieRows is List) {
          for (final row in movieRows) {
            if (row is Map) {
              final tr = _extractTrailer(row);
              if (tr != null) return tr;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  String? _extractTrailer(Map? row) {
    if (row == null) return null;
    final direct = row['trailer']?.toString();
    if (direct != null && direct.startsWith('http')) return direct;
    final trailerObj = row['trailer_url'] ?? row['preview'] ?? row['trailer_src'];
    if (trailerObj != null && trailerObj.toString().startsWith('http')) {
      return trailerObj.toString();
    }
    final extras = row['extras'];
    if (extras is Map) {
      final et = extras['trailer']?.toString();
      if (et != null && et.startsWith('http')) return et;
    }
    return null;
  }
}
