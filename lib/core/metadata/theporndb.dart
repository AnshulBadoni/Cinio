import 'package:dio/dio.dart';

import '../models/home_section.dart';
import '../models/media_item.dart';
import '../models/media_detail.dart';
import '../models/episode.dart';
import '../models/media_extras.dart';
import '../models/provider_info.dart';

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
    final data = await _get('/movies', queryParameters: {
      'page': page,
      'per_page': 24,
      'orderBy': orderBy,
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
    });
    final rows = data['data'];
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map) _movie(row),
    ];
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
    final data = await _get('/performers', queryParameters: {
      'page': page,
      'per_page': 100,
      'orderBy': orderBy,
      'gender': 'FEMALE',
      'age': 40,
      'age_operation': '<',
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
    });
    final rows = data['data'];
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map && _qualifiesAsActor(row)) _performer(row),
    ].take(24).toList();
  }

  bool _qualifiesAsActor(Map row) {
    final rating = (row['rating'] as num?)?.toDouble();
    return rating != null && rating > 4.0;
  }

  Future<List<MediaItem>> studios({int page = 1}) async {
    final data = await _get('/sites', queryParameters: {
      'page': page,
      'per_page': 24,
      'orderBy': 'MOST_RELEVANT',
    });
    final rows = data['data'];
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map) _studio(row),
    ];
  }

  /// Builds the ThePornDB Home rows. Actors are restricted to female performers
  /// younger than 40 with a rating above 4.0. The API applies the gender/age
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
    return [
      HomeSection(title: 'Actors', items: results[0], more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_performers')),
      HomeSection(title: 'Trending', items: results[1], more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_trending')),
      HomeSection(title: 'Popular', items: results[2], more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_popular')),
      HomeSection(title: 'Top Rated', items: results[3], more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_top_rated')),
      HomeSection(title: 'Popular Studios', items: results[4], more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_studios')),
    ].where((section) => section.items.isNotEmpty).toList();
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
    final row = data['data'] is Map ? Map<String,dynamic>.from(data['data'] as Map) : data;
    final performers = row['performers'];
    final cast = <String>[];
    final members = <CastMember>[];
    if (performers is List) {
      for (final p in performers) {
        if (p is! Map) continue;
        final name = (p['name'] ?? p['full_name'])?.toString();
        if (name == null || name.isEmpty) continue;
        cast.add(name);
        members.add(CastMember(name: name, role: null, photo: (p['image'] ?? p['thumbnail'] ?? p['face'])?.toString()));
      }
    }
    final title = (row['title'] ?? row['name'] ?? item.title).toString();
    final ep = Episode(id: 'tpdb:movie:$rawId', title: title, number: 1, url: 'tpdb://movie/$rawId');
    return MediaDetail(id: item.id, title: title, cover: item.cover, url: item.url, description: row['description']?.toString() ?? row['synopsis']?.toString(), type: ProviderType.movie, sourceId: 'tpdb:catalog', cast: cast, castMembers: members, episodes: [ep]);
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

  double _rating(MediaItem item) => item.rating ?? 0;
}
