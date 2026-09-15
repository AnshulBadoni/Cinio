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
  Future<int?>? _straightTagIdFuture;
  // Temporary development key. Replace this before the production release.
  static const String apiKey = '8ABvbgloweVLDeD3HBq6x9eHpL3lMJE8qEuBtdmb213d0c62';

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final response = await _dio.get<dynamic>(
      '$base$path',
      queryParameters: queryParameters,
      options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
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

    // TPDB supports native server-side filtering. Prefer its canonical
    // Straight tag when it can be resolved, but NEVER let tag discovery or a
    // provider-side query-shape change take down the entire catalog. If the
    // tag request/filter is unavailable, retry immediately with TPDB's native
    // performer-gender filter.
    Map<String, dynamic> data;
    try {
      final straight = await (_straightTagIdFuture ??= _findStraightTagId());
      data = await _get('/movies', queryParameters: {
        ...baseQuery,
        ..._straightTagQueryFor(straight),
      });
    } catch (_) {
      data = await _get('/movies', queryParameters: {
        ...baseQuery,
        ..._straightGenderQuery(),
      });
    }

    final rows = data['data'];
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map) _movie(row),
    ];
  }

  Map<String, dynamic> _straightTagQueryFor(int? tagId) {
    if (tagId == null) return _straightGenderQuery();
    return {
      'tags[$tagId]': 'Straight',
      'tag_and': true,
    };
  }

  Map<String, dynamic> _straightGenderQuery() => {
    // These are TPDB's native movie-search filters (not client-side guesses).
    // performer_gender_only means every performer must be one of these genders,
    // excluding TPDB's transgender/non-binary gender values.
    'performer_genders': const ['Female', 'Male'],
    'performer_gender_only': true,
  };

  Future<int?> _findStraightTagId() async {
    try {
      final data = await _get('/tags', queryParameters: {
        'q': 'Straight',
        'per_page': 20,
      }).timeout(const Duration(seconds: 5));
      final rows = data['data'];
      if (rows is! List) return null;
      for (final row in rows) {
        if (row is! Map) continue;
        final name = row['name']?.toString().trim();
        if (name != null && name.toLowerCase() == 'straight') {
          return int.tryParse('${row['id']}');
        }
      }
    } catch (_) {
      // Fall back to TPDB's native performer-gender filter in movies().
    }
    return null;
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

  Future<List<MediaItem>> performers({
    int page = 1,
    String orderBy = 'MOST_RELEVANT',
    String? query,
  }) async {
    var data = await _get('/performers', queryParameters: {
      'page': page,
      'per_page': 48,
      'orderBy': orderBy,
      'gender': 'FEMALE',
      'age': 50,
      'age_operation': '<',
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
    });
    var rows = data['data'];
    if (rows is! List || rows.isEmpty) {
      data = await _get('/performers', queryParameters: {
        'page': page,
        'per_page': 48,
        'gender': 'female',
        'age': 50,
        'age_operation': '<',
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      });
      rows = data['data'];
    }
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map && _qualifiesAsActor(row)) _performer(row),
    ].take(24).toList();
  }

  bool _qualifiesAsActor(Map row) {
    final rating = double.tryParse('${row['rating'] ?? row['score'] ?? ''}');
    final extras = row['extras'];
    final gender = '${row['gender'] ?? (extras is Map ? extras['gender'] : '')}'.toUpperCase();
    final birthday = row['birthday'] ?? (extras is Map ? extras['birthday'] : null);
    final age = double.tryParse('${row['age'] ?? (extras is Map ? extras['age'] : '')}');
    final born = birthday?.toString();
    final derivedAge = age ?? (born != null && born.length >= 4
        ? (DateTime.now().year - (int.tryParse(born.substring(0, 4)) ?? DateTime.now().year)).toDouble()
        : null);
    return rating != null && rating > 4.0 &&
        (gender.isEmpty || gender == 'FEMALE') &&
        (derivedAge == null || derivedAge < 50);
  }

  Future<List<MediaItem>> studios({int page = 1}) async {
    var data = await _get('/sites', queryParameters: {
      'page': page,
      'per_page': 24,
      'orderBy': 'MOST_RELEVANT',
    });
    var rows = data['data'];
    if (rows is! List || rows.isEmpty) {
      data = await _get('/sites', queryParameters: {
        'page': page,
        'per_page': 24,
      });
      rows = data['data'];
    }
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map) _studio(row),
    ];
  }

  /// Builds the ThePornDB Home rows. Actors are restricted to female performers
  /// younger than 50 with a rating above 4.0. The API applies the gender/age
  /// filters server-side; rating is filtered locally because the performer list
  /// endpoint does not expose a rating filter.
  Future<List<HomeSection>> home() async {
    final results = await Future.wait([
      _safe(() => performers()),
      _safe(() => movies(orderBy: 'recently_released')),
      _safe(() => movies(orderBy: 'most_relevant')),
      _safe(() => _topRated(1)),
      _safe(() => studios()),
    ]);
    // Keep content rows first; people/studio rows belong after the movie rows.
    // This also prevents Actors from becoming the Home hero carousel source.
    return [
      HomeSection(title: 'Recent', items: results[1], more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_recent')),
      HomeSection(title: 'Popular', items: results[2], more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_popular')),
      HomeSection(title: 'Top Rated', items: results[3], more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_top_rated')),
      HomeSection(title: 'Actors', items: results[0], more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_performers')),
      HomeSection(title: 'Studio', items: results[4], more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_studios')),
    ].where((section) => section.items.isNotEmpty).toList();
  }

  Future<HomeSection?> homeSection(String kind) async {
    final items = switch (kind) {
      'tpdb_recent' => await movies(orderBy: 'recently_released'),
      'tpdb_popular' => await movies(orderBy: 'most_relevant'),
      'tpdb_top_rated' => await _topRated(1),
      'tpdb_performers' => await performers(),
      'tpdb_studios' => await studios(),
      _ => const <MediaItem>[],
    };
    if (items.isEmpty) return null;
    final title = switch (kind) {
      'tpdb_recent' => 'Recent',
      'tpdb_popular' => 'Popular',
      'tpdb_top_rated' => 'Top Rated',
      'tpdb_performers' => 'Actors',
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

  Future<List<MediaItem>> search(String query, {int page = 1}) =>
      movies(page: page, query: query, orderBy: 'most_relevant');

  Future<MediaDetail> movieDetail(MediaItem item) async {
    final rawId = item.id.replaceFirst('tpdb:movie:', '');
    final data = await _get('/movies/$rawId');
    final row = data['data'] is Map
        ? Map<String, dynamic>.from(data['data'] as Map)
        : data;
    final performers = row['performers'];
    final cast = <String>[];
    final members = <CastMember>[];
    if (performers is List) {
      for (final p in performers) {
        if (p is! Map) continue;
        final name = (p['name'] ?? p['full_name'])?.toString();
        if (name == null || name.isEmpty) continue;
        final rawPid = (p['id'] ?? p['uuid'] ?? p['_id'] ?? p['slug'])?.toString();
        final photo = (p['image'] ?? p['thumbnail'] ?? p['face'])?.toString();
        cast.add(name);
        if (rawPid != null && rawPid.isNotEmpty) {
          members.add(CastMember(
            name: name,
            photo: photo,
            person: PersonRef(
              id: int.tryParse(p['_id']?.toString() ?? '') ?? 0,
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
    final title = (row['title'] ?? row['name'] ?? item.title).toString();
    final ep = Episode(
      id: 'tpdb:movie:$rawId',
      title: title,
      number: 1,
      url: 'tpdb://movie/$rawId',
      description: row['description']?.toString() ?? row['synopsis']?.toString(),
      rating: double.tryParse('${row['rating'] ?? ''}'),
      date: row['date']?.toString() ?? row['release_date']?.toString(),
    );
    return MediaDetail(
      id: item.id,
      title: title,
      cover: _firstImage(row) ?? item.cover,
      url: item.url,
      description: row['description']?.toString() ?? row['synopsis']?.toString(),
      year: _year(row['release_date'] ?? row['date']),
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
      url: 'tpdb://movie/$id',
      type: ProviderType.movie,
      sourceId: 'tpdb:catalog',
      genres: _names(row['tags']),
      rating: (row['rating'] as num?)?.toDouble(),
    );
  }

  MediaItem _performer(Map row) {
    final id = (row['id'] ?? row['_id'] ?? row['slug']).toString();
    return MediaItem(
      id: 'tpdb:performer:$id',
      title: (row['name'] ?? row['full_name'] ?? 'Performer').toString(),
      cover: (row['image'] ?? row['thumbnail'] ?? row['face'])?.toString(),
      url: 'https://theporndb.net/performers/$id',
      type: ProviderType.movie,
      sourceId: 'tpdb:performer',
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
}
