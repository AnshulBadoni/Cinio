import 'package:dio/dio.dart';

import '../models/home_section.dart';
import '../models/media_item.dart';
import '../models/media_detail.dart';
import '../models/episode.dart';
import '../models/media_extras.dart';
import '../models/provider_info.dart';
import '../models/person.dart';

/// ThePornDB-backed catalog. It is catalog/metadata only; playback is still
/// resolved by the normal streaming-provider pipeline.
class ThePornDb {
  ThePornDb(this._dio);

  final Dio _dio;

  static const String base = 'https://api.theporndb.net';
  // Temporary development key. Replace this before the production release.
  static const String apiKey = '8ABvbgloweVLDeD3HBq6x9eHpL3lMJE8qEuBtdmb213d0c62';

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
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
      ...await _straightFilterQuery(),
    };

    final data = await _get('/movies', queryParameters: filteredQuery);
    final rows = data['data'];
    if (rows is! List) return const <MediaItem>[];
    return [
      for (final row in rows)
        if (row is Map) _movie(row),
    ];
  }


  Future<Map<String, dynamic>> _straightFilterQuery() async {
    // Prefer TPDB's explicit tag filter when the canonical Straight tag can
    // be resolved. This is the strongest server-side signal for orientation.
    try {
      final tagData = await _get('/tags', queryParameters: {
        'q': 'Straight',
        'orderBy': 'most_relevant',
      });
      final rows = tagData['data'];
      if (rows is List) {
        for (final row in rows) {
          if (row is! Map) continue;
          final name = row['name']?.toString().trim();
          final id = int.tryParse('${row['id']}');
          if (id != null && name != null && name.toLowerCase() == 'straight') {
            return {
              'tags[$id]': name,
              'tag_and': true,
            };
          }
        }
      }
    } catch (_) {
      // Fall through to the documented performer-gender-only filter. A
      // failure resolving the optional tag must never make TPDB unavailable.
    }

    // TPDB documents performer_genders as an associative array:
    // performer_genders[Female]=Female.
    return {
      'performer_genders[Female]': 'Female',
    };
  }

  Future<List<MediaItem>> trendingPerformers({int page = 1}) async {
    final data = await _get('/scenes', queryParameters: {
      'page': page,
      'per_page': 50,
      'orderBy': 'recently_released',
    });
    final rows = data['data'];
    if (rows is! List) return const [];
    final seen = <String>{};
    final out = <MediaItem>[];
    for (final scene in rows) {
      if (scene is! Map || scene['performers'] is! List) continue;
      for (final performer in scene['performers'] as List) {
        if (performer is! Map) continue;
        final id = (performer['id'] ?? performer['_id'] ?? performer['slug']).toString();
        if (!seen.add(id)) continue;
        out.add(_performer(performer));
        if (out.length >= 24) return out;
      }
    }
    return out;
  }

  static const List<String> _kTopPerformers = [
    'Riley Reid', 'Gabbie Carter', 'Lana Rhoades', 'Mia Malkova', 'Angela White',
    'Emily Willis', 'Autumn Falls', 'Abella Danger', 'Eva Lovia', 'Kendra Lust',
    'Janice Griffith', 'Alina Lopez', 'Kenzie Reeves', 'Blake Blossom', 'Liya Silver',
    'Cory Chase', 'Brandi Love', 'Alexis Texas', 'Tori Black', 'Nicole Aniston',
    'Dillion Harper', 'Lena Paul', 'Vicki Chase', 'Maitland Ward', 'Kenna James',
    'Gianna Michaels', 'Violet Myers', 'Skylar Vox', 'Gia Paige', 'Scarlit Scandal',
    'Sweetie Fox', 'Little Caprice', 'Leah Gotti', 'Kelsi Monroe', 'Elsa Jean',
    'Alex Coal', 'Adria Rae', 'Lacy Lennon', 'Vanna Bardot', 'Maya Bijou',
    'Kira Noir', 'Jill Kassidy', 'Kylie Rocket', 'Vina Sky', 'Cherie DeVille',
    'Natasha Nice', 'Kagney Linn Karter', 'Phoenix Marie', 'Sarah Vandella', 'Lisa Ann',
    'Penny Pax', 'Chanel Preston', 'Alexis Fawx', 'Reagan Foxx', 'Eva Elfie',
  ];

  Future<List<MediaItem>> performers({
    int page = 1,
    String orderBy = 'most_relevant',
    String? query,
  }) async {
    final isSearch = query != null && query.trim().isNotEmpty;
    if (!isSearch) {
      const pageSize = 20;
      final offset = (page - 1) * pageSize;
      if (offset < _kTopPerformers.length) {
        final List<String> names;
        if (page == 1) {
          names = (List<String>.from(_kTopPerformers)..shuffle()).take(pageSize).toList();
        } else {
          names = _kTopPerformers.skip(offset).take(pageSize).toList();
        }
        final futures = names.map((name) async {
          try {
            final res = await _get('/performers', queryParameters: {
              'q': name,
              'per_page': 1,
            });
            final list = res['data'] as List?;
            if (list != null && list.isNotEmpty) {
              final row = list.first;
              if (row is Map && _qualifiesAsActor(row, requireRating: true)) {
                return _performer(row);
              }
            }
          } catch (_) {}
          return null;
        });
        final results = (await Future.wait(futures)).whereType<MediaItem>().toList();
        results.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
        if (results.isNotEmpty) return results;
      }
    }

    final data = await _get('/performers', queryParameters: {
      'page': page,
      'per_page': 50,
      'orderBy': orderBy,
      'gender': 'Female',
      'age': 50,
      'age_operation': '<',
      if (isSearch) 'q': query.trim(),
    });
    final rows = data['data'];
    if (rows is! List) return const [];
    final list = [
      for (final row in rows)
        if (row is Map && _qualifiesAsActor(row, requireRating: !isSearch)) _performer(row),
    ];
    list.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
    return list.take(24).toList();
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
        if (s is Map && s['rating'] != null) {
          final sr = double.tryParse('${s['rating']}');
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
    final rating = _extractPerformerRating(row);
    final extras = row['extras'];
    final gender = '${row['gender'] ?? (extras is Map ? extras['gender'] : '')}'.toUpperCase();
    final birthday = row['birthday'] ?? (extras is Map ? extras['birthday'] : null);
    final age = double.tryParse('${row['age'] ?? (extras is Map ? extras['age'] : '')}');
    final born = birthday?.toString();
    final derivedAge = age ?? (born != null && born.length >= 4
        ? (DateTime.now().year - (int.tryParse(born.substring(0, 4)) ?? DateTime.now().year)).toDouble()
        : null);
    final ratingOk = requireRating
        ? (rating != null && rating >= 4.0)
        : (rating == null || rating >= 4.0);
    return ratingOk &&
        (gender.isEmpty || gender == 'FEMALE') &&
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
        if (row is Map) _studio(row),
    ];
  }

  /// Builds the ThePornDB Home rows in order: Recent, Trending, Actors, Popular, Top Rated.
  /// Actors are restricted to female performers younger than 50 with a rating above 4.0,
  /// sorted with top-rated models first. Studio row is removed from home.
  Future<List<HomeSection>> home() async {
    final results = await Future.wait([
      _safe(() => movies(orderBy: 'recently_released')), // 0: Recent
      _safe(() => movies(orderBy: 'most_relevant')), // 1: Trending
      _safe(() => performers()), // 2: Actors
      _safe(() => movies(orderBy: 'most_relevant', page: 2)), // 3: Popular
      _safe(() => _topRated(1)), // 4: Top Rated
    ]);
    return [
      HomeSection(title: 'Recent', items: results[0], more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_recent')),
      HomeSection(title: 'Trending', items: results[1], more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_trending')),
      HomeSection(title: 'Actors', items: results[2], more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_performers')),
      HomeSection(title: 'Popular', items: results[3], more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_popular')),
      HomeSection(title: 'Top Rated', items: results[4], more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_top_rated')),
    ].where((section) => section.items.isNotEmpty).toList();
  }

  Future<HomeSection?> homeSection(String kind) async {
    final items = switch (kind) {
      'tpdb_recent' => await movies(orderBy: 'recently_released'),
      'tpdb_trending' => await movies(orderBy: 'most_relevant'),
      'tpdb_performers' => await performers(),
      'tpdb_popular' => await movies(orderBy: 'most_relevant', page: 2),
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
        'tpdb_trending' => movies(page: page, orderBy: 'recently_released'),
        'tpdb_popular' => movies(page: page, orderBy: 'most_relevant'),
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
    final rawId = item.id.replaceFirst('tpdb:movie:', '');
    final data = await _get('/movies/$rawId');
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
        final photo = (parent?['image'] ?? parent?['thumbnail'] ?? parent?['face'] ?? p['image'] ?? p['thumbnail'] ?? p['face'])?.toString() ?? _firstImage(p);
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
    final ep = Episode(
      id: item.id,
      number: 1,
      title: (row['title'] ?? item.title).toString(),
      url: item.url,
      thumbnail: _firstImage(row) ?? item.cover,
      description: (row['description'] ?? row['synopsis'])?.toString(),
    );
    return MediaDetail(
      id: item.id,
      title: (row['title'] ?? item.title).toString(),
      description: (row['description'] ?? row['synopsis'])?.toString(),
      cover: _firstImage(row) ?? item.cover,
      url: item.url,
      year: _year(row['date'] ?? row['release_date']),
      type: ProviderType.movie,
      sourceId: 'tpdb:catalog',
      genres: _names(row['tags'] ?? row['genres']),
      studios: _studioNames(row),
      cast: cast,
      castMembers: members,
      episodes: [ep],
    );
  }

  Future<List<MediaItem>> _topRated(int page) async {
    final items = await movies(page: page, orderBy: 'recently_released');
    return [...items]..sort((a, b) => _rating(b).compareTo(_rating(a)));
  }

  MediaItem _movie(Map row) {
    final id = (row['id'] ?? row['_id'] ?? row['uuid'] ?? row['slug']).toString();
    final title = (row['title'] ?? row['name'] ?? 'Untitled').toString();
    return MediaItem(
      id: 'tpdb:movie:$id',
      title: title,
      cover: _firstImage(row),
      heroImage: _firstHeroImage(row),
      url: 'tpdb://movie/$id',
      type: ProviderType.movie,
      sourceId: 'tpdb:catalog',
      genres: _names(row['tags']),
      rating: (row['rating'] as num?)?.toDouble(),
      year: _year(row['date'] ?? row['release_date']),
    );
  }

  MediaItem _performer(Map row) {
    final id = (row['id'] ?? row['_id'] ?? row['slug']).toString();
    final rating = _extractPerformerRating(row);
    return MediaItem(
      id: 'tpdb:performer:$id',
      title: (row['name'] ?? row['full_name'] ?? 'Performer').toString(),
      cover: (row['image'] ?? row['thumbnail'] ?? row['face'])?.toString(),
      url: 'https://theporndb.net/performers/$id',
      type: ProviderType.movie,
      sourceId: 'tpdb:performer',
      rating: rating,
    );
  }

  MediaItem _studio(Map row) {
    final id = (row['id'] ?? row['uuid'] ?? row['short_name']).toString();
    return MediaItem(
      id: 'tpdb:studio:$id',
      title: (row['name'] ?? 'Studio').toString(),
      cover: (row['logo'] ?? row['poster'] ?? row['favicon'])?.toString(),
      url: 'https://theporndb.net/sites/$id',
      type: ProviderType.movie,
      sourceId: 'tpdb:studio',
    );
  }

  String? _year(Object? value) {
    final s = value?.toString() ?? '';
    return s.length >= 4 ? s.substring(0, 4) : null;
  }

  String? _firstHeroImage(Map row) {
    for (final key in [
      'background',
      'backdrop',
      'backdrop_image',
      'background_image',
      'banner',
      'landscape',
      'fanart',
    ]) {
      final value = row[key]?.toString();
      if (value != null && value.isNotEmpty) return value;
    }
    final backgrounds = row['backgrounds'] ?? row['backdrops'] ?? row['fanart'];
    if (backgrounds is Map) {
      for (final key in ['large', 'medium', 'full', 'original']) {
        final value = backgrounds[key]?.toString();
        if (value != null && value.isNotEmpty) return value;
      }
    }
    if (backgrounds is List) {
      for (final value in backgrounds) {
        if (value is String && value.isNotEmpty) return value;
        if (value is Map) {
          for (final key in ['url', 'image', 'src', 'large', 'full']) {
            final v = value[key]?.toString();
            if (v != null && v.isNotEmpty) return v;
          }
        }
      }
    }
    return null;
  }

  String? _firstImage(Map row) {
    for (final key in ['poster', 'poster_image', 'image']) {
      final value = row[key]?.toString();
      if (value != null && value.isNotEmpty) return value;
    }
    final posters = row['posters'];
    if (posters is Map) {
      for (final key in ['large', 'medium', 'small', 'full']) {
        final value = posters[key]?.toString();
        if (value != null && value.isNotEmpty) return value;
      }
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
