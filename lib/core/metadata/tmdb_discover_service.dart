import 'dart:math' as math;

import 'package:dio/dio.dart';

import '../models/media_item.dart';
import '../models/provider_info.dart';
import 'tmdb.dart';

/// TMDB-backed catalog/search used by the Search screen's Discover mode.
///
/// TMDB is deliberately a catalog only: the returned MediaItems carry a
/// synthetic source id and TMDB id. The Search screen resolves a tapped item
/// against the user's active streaming provider before opening DetailScreen.
class TmdbDiscoverService {
  TmdbDiscoverService(this._dio);

  final Dio _dio;

  static const _movieGenres = <String, int>{
    'Action': 28,
    'Adventure': 12,
    'Animation': 16,
    'Comedy': 35,
    'Crime': 80,
    'Documentary': 99,
    'Drama': 18,
    'Family': 10751,
    'Fantasy': 14,
    'History': 36,
    'Horror': 27,
    'Music': 10402,
    'Mystery': 9648,
    'Romance': 10749,
    'Science Fiction': 878,
    'Thriller': 53,
    'War': 10752,
    'Western': 37,
  };

  static const _tvGenres = <String, int>{
    'Action & Adventure': 10759,
    'Animation': 16,
    'Comedy': 35,
    'Crime': 80,
    'Documentary': 99,
    'Drama': 18,
    'Family': 10751,
    'Kids': 10762,
    'Mystery': 9648,
    'News': 10763,
    'Reality': 10764,
    'Sci-Fi & Fantasy': 10765,
    'Soap': 10766,
    'Talk': 10767,
    'War & Politics': 10768,
    'Western': 37,
  };

  static const List<String> genres = [
    'Any',
    'Action',
    'Adventure',
    'Animation',
    'Comedy',
    'Crime',
    'Documentary',
    'Drama',
    'Family',
    'Fantasy',
    'Horror',
    'Mystery',
    'Romance',
    'Science Fiction',
    'Thriller',
    'History',
    'Music',
  ];

  Future<List<MediaItem>> discover({
    required String catalog,
    required String type,
    String? genre,
    required int page,
  }) async {
    if (catalog == 'trending') {
      return _trending(type: type, genre: genre, page: page);
    }

    final results = <MediaItem>[];
    if (type == 'movies' || type == 'all') {
      results.addAll(
        await _discoverKind(
          kind: 'movie',
          catalog: catalog,
          genre: genre,
          page: page,
        ),
      );
    }
    if (type == 'series' || type == 'all' || type == 'anime') {
      results.addAll(
        await _discoverKind(
          kind: 'tv',
          catalog: catalog,
          genre: genre,
          page: page,
          anime: type == 'anime',
        ),
      );
    }

    // Mixed feeds should feel mixed rather than movie-page then TV-page.
    if (type == 'all') {
      results.shuffle(math.Random(page * 7919));
    }
    return results;
  }

  Future<List<MediaItem>> search({
    required String query,
    required String type,
    String? genre,
    int page = 1,
  }) async {
    final response = await _dio.get<dynamic>(
      '${Tmdb.base}/search/multi',
      queryParameters: {
        'query': query,
        'page': page,
        'include_adult': false,
      },
    );
    final rows = response.data is Map ? response.data['results'] : null;
    if (rows is! List) return const [];

    return [
      for (final row in rows)
        if (row is Map) ..._mapSearchRow(row, type: type, genre: genre),
    ];
  }

  Future<List<MediaItem>> _trending({
    required String type,
    String? genre,
    required int page,
  }) async {
    final path = type == 'movies'
        ? 'movie'
        : type == 'series' || type == 'anime'
        ? 'tv'
        : 'all';
    // TMDB's trending endpoint is a single ranked batch; unlike Discover it
    // does not expose page-based pagination. Do not send a synthetic `page`
    // parameter here — it is not part of the endpoint contract.
    final response = await _dio.get<dynamic>(
      '${Tmdb.base}/trending/$path/week',
    );
    final rows = response.data is Map ? response.data['results'] : null;
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map)
          ..._mapSearchRow(
            row,
            type: type,
            genre: genre,
            trending: true,
          ),
    ];
  }

  Future<List<MediaItem>> _discoverKind({
    required String kind,
    required String catalog,
    String? genre,
    required int page,
    bool anime = false,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'include_adult': false,
      'sort_by': switch (catalog) {
        'top_rated' => 'vote_average.desc',
        _ => 'popularity.desc',
      },
    };
    if (catalog == 'top_rated') params['vote_count.gte'] = 200;

    final actualPage = catalog == 'discover_new'
        ? math.Random().nextInt(20) + 1
        : page;
    params['page'] = actualPage;

    final genreId = _genreId(kind, genre);
    if (genreId != null) params['with_genres'] = genreId;
    if (anime) {
      params['with_genres'] = 16;
      params['with_origin_country'] = 'JP';
    }

    final response = await _dio.get<dynamic>(
      '${Tmdb.base}/discover/$kind',
      queryParameters: params,
    );
    final rows = response.data is Map ? response.data['results'] : null;
    if (rows is! List) return const [];
    final mapped = [
      for (final row in rows)
        if (row is Map) ..._mapSearchRow(row, type: kind == 'tv' ? 'series' : 'movies'),
    ];
    if (catalog == 'discover_new') mapped.shuffle(math.Random());
    return mapped;
  }

  int? _genreId(String kind, String? genre) {
    if (genre == null || genre.trim().isEmpty || genre == 'Any') return null;
    if (kind == 'movie') return _movieGenres[genre];
    const tvAliases = <String, int>{
      'Action': 10759,
      'Adventure': 10759,
      'Animation': 16,
      'Comedy': 35,
      'Crime': 80,
      'Documentary': 99,
      'Drama': 18,
      'Family': 10751,
      'Fantasy': 10765,
      'Mystery': 9648,
      'Romance': 18,
      'Science Fiction': 10765,
      'Thriller': 9648,
      'History': 36,
      'Music': 35,
    };
    return _tvGenres[genre] ?? tvAliases[genre];
  }

  Iterable<MediaItem> _mapSearchRow(
    Map row, {
    required String type,
    String? genre,
    bool trending = false,
  }) sync* {
    final mediaType = row['media_type']?.toString();
    final isTv = mediaType == 'tv' || (mediaType == null && type == 'series');
    final isMovie = mediaType == 'movie' || (mediaType == null && type == 'movies');
    if (!isTv && !isMovie) return;
    if (type == 'movies' && !isMovie) return;
    if ((type == 'series' || type == 'anime') && !isTv) return;
    if (type == 'anime') {
      if (!isTv) return;
      final genres = (row['genre_ids'] as List?)?.whereType<num>().map((e) => e.toInt()).toSet() ?? {};
      final countries = (row['origin_country'] as List?)?.map((e) => e.toString()).toSet() ?? {};
      if (!genres.contains(16) || !countries.contains('JP')) return;
    }

    if (genre != null && genre != 'Any') {
      final wanted = _genreId(isTv ? 'tv' : 'movie', genre);
      if (wanted != null) {
        final ids = (row['genre_ids'] as List?)?.whereType<num>().map((e) => e.toInt()).toSet() ?? {};
        if (!ids.contains(wanted)) return;
      }
    }

    final id = (row['id'] as num?)?.toInt();
    if (id == null) return;
    final title = (isTv ? row['name'] : row['title'])?.toString().trim();
    if (title == null || title.isEmpty) return;
    final coverPath = row['poster_path']?.toString();
    final backdrop = row['backdrop_path']?.toString();
    final genreNames = <String>[];
    final ids = (row['genre_ids'] as List?)?.whereType<num>().map((e) => e.toInt()) ?? const <int>[];
    final map = isTv ? _tvGenres : _movieGenres;
    for (final entry in map.entries) {
      if (ids.contains(entry.value)) genreNames.add(entry.key);
    }

    yield MediaItem(
      id: 'tmdb:${isTv ? 'tv' : 'movie'}:$id',
      title: title,
      cover: coverPath == null ? null : '${Tmdb.img}/w500$coverPath',
      url: 'tmdb://${isTv ? 'tv' : 'movie'}/$id',
      type: ProviderType.movie,
      sourceId: 'tmdb:catalog',
      tmdbId: id,
      tmdbIsTv: isTv,
      genres: genreNames,
    );
  }
}
