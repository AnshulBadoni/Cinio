import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';

import '../models/home_section.dart';
import '../models/media_detail.dart';
import '../models/episode.dart';
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

  static String get _deviceRegion {
    try {
      final loc = Platform.localeName;
      final parts = loc.split(RegExp(r'[_-]'));
      if (parts.length > 1) {
        final code = parts.last.toUpperCase();
        if (code.length == 2) return code;
      }
      return 'US';
    } catch (_) {
      return 'US';
    }
  }

  Future<HomeSection?> homeSection(String kind) async {
    final result = switch (kind) {
      'tmdb_recent' => await _recentMixed(1),
      'tmdb_new_releases' => await _newReleases(1),
      'tmdb_trending_movies' => await _trendingKind('movie', 1),
      'tmdb_trending_series' => await _trendingKind('tv', 1),
      'tmdb_popular_movies' => await _discoverKind(kind: 'movie', catalog: 'popular', page: 1),
      'tmdb_popular_series' => await _discoverKind(kind: 'tv', catalog: 'popular', page: 1),
      'tmdb_trending_anime' => await _discoverKind(kind: 'tv', catalog: 'anime', page: 1, anime: true),
      'tmdb_top_rated_movies' => await _discoverKind(kind: 'movie', catalog: 'top_rated', page: 1),
      'tmdb_top_rated_series' => await _discoverKind(kind: 'tv', catalog: 'top_rated', page: 1),
      _ => const <MediaItem>[],
    };
    if (result.isEmpty) return null;
    final title = switch (kind) {
      'tmdb_recent' => 'Recent Movies & Series',
      'tmdb_new_releases' => 'New Releases',
      'tmdb_trending_movies' => 'Trending Movies',
      'tmdb_trending_series' => 'Trending Series',
      'tmdb_popular_movies' => 'Popular Movies',
      'tmdb_popular_series' => 'Popular Series',
      'tmdb_trending_anime' => 'Trending Anime',
      'tmdb_top_rated_movies' => 'Top Rated Movies',
      'tmdb_top_rated_series' => 'Top Rated Series',
      _ => '',
    };
    return HomeSection(title: title, items: result, more: BrowseMore(sourceId: 'tmdb:catalog', kind: kind));
  }

  Future<List<HomeSection>> home() async {
    final results = await Future.wait([
      _safe(() => _recentMixed(1)),
      _safe(() => _newReleases(1)),
      _safe(() => _trendingKind('movie', 1)),
      _safe(() => _trendingKind('tv', 1)),
      _safe(() => _discoverKind(kind: 'movie', catalog: 'popular', page: 1)),
      _safe(() => _discoverKind(kind: 'tv', catalog: 'popular', page: 1)),
      _safe(() => _discoverKind(kind: 'tv', catalog: 'anime', page: 1, anime: true)),
      _safe(() => _discoverKind(kind: 'movie', catalog: 'top_rated', page: 1)),
      _safe(() => _discoverKind(kind: 'tv', catalog: 'top_rated', page: 1)),
    ]);
    final kinds = <String>[
      'tmdb_recent', 'tmdb_new_releases', 'tmdb_trending_movies', 'tmdb_trending_series',
      'tmdb_popular_movies', 'tmdb_popular_series', 'tmdb_trending_anime',
      'tmdb_top_rated_movies', 'tmdb_top_rated_series',
    ];
    final titles = <String>[
      'Recent Movies & Series', 'New Releases', 'Trending Movies', 'Trending Series',
      'Popular Movies', 'Popular Series', 'Trending Anime',
      'Top Rated Movies', 'Top Rated Series',
    ];
    return [
      for (var i = 0; i < results.length; i++)
        if (results[i].isNotEmpty) HomeSection(
          title: titles[i], items: results[i],
          more: BrowseMore(sourceId: 'tmdb:catalog', kind: kinds[i]),
        ),
    ];
  }

  Future<List<MediaItem>> _safe(Future<List<MediaItem>> Function() loader) async {
    try { return await loader(); } catch (_) { return const []; }
  }

  Future<List<MediaItem>> browseMore(String kind, int page) async {
    switch (kind) {
      case 'tmdb_recent': return _recentMixed(page);
      case 'tmdb_new_releases': return _newReleases(page);
      case 'tmdb_trending_movies': return _trendingKind('movie', page);
      case 'tmdb_trending_series': return _trendingKind('tv', page);
      case 'tmdb_popular_movies': return _discoverKind(kind: 'movie', catalog: 'popular', page: page);
      case 'tmdb_popular_series': return _discoverKind(kind: 'tv', catalog: 'popular', page: page);
      case 'tmdb_trending_anime': return _discoverKind(kind: 'tv', catalog: 'anime', page: page, anime: true);
      case 'tmdb_top_rated_movies': return _discoverKind(kind: 'movie', catalog: 'top_rated', page: page);
      case 'tmdb_top_rated_series': return _discoverKind(kind: 'tv', catalog: 'top_rated', page: page);
      default: return const [];
    }
  }

  Future<List<MediaItem>> _newReleases(int page) async {
    try {
      final response = await _dio.get<dynamic>(
        '${Tmdb.base}/movie/now_playing',
        queryParameters: {
          'page': page,
          'region': _deviceRegion,
        },
        options: Options(receiveTimeout: const Duration(seconds: 12), sendTimeout: const Duration(seconds: 12)),
      );
      final rows = response.data is Map ? response.data['results'] : null;
      if (rows is List && rows.isNotEmpty) {
        return [for (final row in rows) if (row is Map) ..._mapSearchRow(row, type: 'movies')];
      }
    } catch (_) {}
    return _discoverKind(kind: 'movie', catalog: 'recent', page: page);
  }

  Future<List<MediaItem>> _trendingKind(String kind, int page) async {
    final response = await _dio.get<dynamic>(
      '${Tmdb.base}/trending/$kind/week',
      queryParameters: {'page': page},
      options: Options(receiveTimeout: const Duration(seconds: 12), sendTimeout: const Duration(seconds: 12)),
    );
    final rows = response.data is Map ? response.data['results'] : null;
    if (rows is! List) return const [];
    return [for (final row in rows) if (row is Map) ..._mapSearchRow(row, type: kind == 'tv' ? 'series' : 'movies', trending: true)];
  }

  Future<List<MediaItem>> _recentMixed(int page) async {
    final movies = await _discoverKind(kind: 'movie', catalog: 'recent', page: page);
    final series = await _discoverKind(kind: 'tv', catalog: 'recent', page: page);
    final out = <MediaItem>[];
    for (var i = 0; i < movies.length || i < series.length; i++) {
      if (i < movies.length) out.add(movies[i]);
      if (i < series.length) out.add(series[i]);
    }
    return out;
  }

  Future<MediaDetail> movieDetail(MediaItem item) async {
    final id = item.tmdbId;
    if (id == null) throw StateError('Missing TMDB id');
    final kind = item.tmdbIsTv ? 'tv' : 'movie';
    final response = await _dio.get<dynamic>(
      '${Tmdb.base}/$kind/$id',
      queryParameters: {
        'append_to_response': item.tmdbIsTv ? 'credits' : 'credits,release_dates',
      },
      options: Options(receiveTimeout: const Duration(seconds: 12), sendTimeout: const Duration(seconds: 12)),
    );
    final row = response.data is Map ? Map<String,dynamic>.from(response.data as Map) : <String,dynamic>{};
    final title = (item.tmdbIsTv ? row['name'] : row['title'])?.toString() ?? item.title;
    final poster = row['poster_path']?.toString();
    final overview = row['overview']?.toString();
    var date = (item.tmdbIsTv ? row['first_air_date'] : row['release_date'])?.toString();
    final tmdbStatus = row['status']?.toString();
    var theatricalRelease = false;

    // TMDB release type: 2/3 = theatrical, 4 = digital/OTT, 5 = physical,
    // 6 = TV. A recent release date alone is NOT enough to call something
    // 'In Cinema': many OTT titles have a recent digital release. Prefer the
    // current device region when available and let a digital release supersede
    // theatrical availability.
    if (!item.tmdbIsTv && row['release_dates'] is Map) {
      final results = row['release_dates']['results'];
      if (results is List) {
        Map? matchCountry;
        for (final r in results) {
          if (r is Map && r['iso_3166_1'] == _deviceRegion) {
            matchCountry = r;
            break;
          }
        }
        matchCountry ??= results.cast<dynamic>().whereType<Map>().firstWhere(
          (r) => r['release_dates'] is List,
          orElse: () => <dynamic,dynamic>{},
        );
        final dates = matchCountry?['release_dates'];
        if (dates is List) {
          final today = DateTime.now();
          DateTime? latestTheatrical;
          DateTime? latestDigital;
          for (final d in dates) {
            if (d is! Map || d['release_date'] is! String) continue;
            final parsed = DateTime.tryParse((d['release_date'] as String).split('T').first);
            if (parsed == null || parsed.isAfter(today)) continue;
            final type = (d['type'] as num?)?.toInt();
            if (type == 2 || type == 3) {
              if (latestTheatrical == null || parsed.isAfter(latestTheatrical)) latestTheatrical = parsed;
            } else if (type == 4) {
              if (latestDigital == null || parsed.isAfter(latestDigital)) latestDigital = parsed;
            }
          }
          theatricalRelease = latestTheatrical != null &&
              (latestDigital == null || latestTheatrical.isAfter(latestDigital));
        }
      }
    }

    // Check regional release date for movie if available
    if (!item.tmdbIsTv && row['release_dates'] is Map) {
      final results = row['release_dates']['results'];
      if (results is List) {
        final region = _deviceRegion;
        Map? matchCountry;
        for (final r in results) {
          if (r is Map && r['iso_3166_1'] == region) {
            matchCountry = r;
            break;
          }
        }
        if (matchCountry != null && matchCountry['release_dates'] is List) {
          final datesList = matchCountry['release_dates'] as List;
          if (datesList.isNotEmpty) {
            for (final d in datesList) {
              if (d is Map && d['release_date'] is String) {
                final rd = (d['release_date'] as String).split('T').first;
                if (rd.isNotEmpty) {
                  date = rd;
                  break;
                }
              }
            }
          }
        }
      }
    }

    final castRows = row['credits'] is Map ? row['credits']['cast'] : null;
    final cast = <String>[];
    if (castRows is List) { for (final c in castRows) { if (c is Map && c['name'] != null) cast.add(c['name'].toString()); } }
    final episodes = <Episode>[];
    if (item.tmdbIsTv) {
      final seasons = row['seasons'];
      if (seasons is List) {
        final seasonNumbers = [
          for (final season in seasons)
            if (season is Map) (season['season_number'] as num?)?.toInt(),
        ].whereType<int>().where((n) => n > 0).toList();

        // Keep metadata loading bounded. A series with many seasons used to
        // fan out large groups of 12s requests and retry each failed season 3x,
        // which could make the detail screen look frozen for minutes.
        final seasonResults = <List<Episode>>[];
        for (var i = 0; i < seasonNumbers.length; i += 2) {
          final chunk = seasonNumbers.sublist(i, math.min(i + 2, seasonNumbers.length));
          final chunkRes = await Future.wait([
            for (final seasonNumber in chunk) _loadTmdbSeason(id, seasonNumber),
          ]);
          seasonResults.addAll(chunkRes);
        }

        for (final result in seasonResults) {
          episodes.addAll(result);
        }
        episodes.sort((a, b) {
          final sa = a.season ?? 1, sb = b.season ?? 1;
          final sn = sa.compareTo(sb);
          return sn != 0 ? sn : (a.number ?? 0).compareTo(b.number ?? 0);
        });

        return MediaDetail(
          id: item.id, title: title, englishTitle: item.englishTitle,
          cover: poster == null ? item.cover : '${Tmdb.img}/w500$poster',
          url: item.url, description: overview, year: date != null && date.length >= 4 ? date.substring(0,4) : null,
          type: ProviderType.movie, sourceId: 'tmdb:catalog', tmdbId: id, tmdbIsTv: item.tmdbIsTv,
          isSeries: item.tmdbIsTv, genres: item.genres, cast: cast, episodes: episodes,
          releaseDate: date,
          tmdbStatus: tmdbStatus,
          availableSeasons: seasonNumbers,
          tmdbTheatricalRelease: theatricalRelease,
        );
      }
    } else {
      episodes.add(Episode(
        id: 'tmdb:movie:$id',
        title: title,
        number: 1,
        url: 'tmdb://movie/$id',
      ));
    }
    return MediaDetail(
      id: item.id, title: title, englishTitle: item.englishTitle,
      cover: poster == null ? item.cover : '${Tmdb.img}/w500$poster',
      url: item.url, description: overview, year: date != null && date.length >= 4 ? date.substring(0,4) : null,
      type: ProviderType.movie, sourceId: 'tmdb:catalog', tmdbId: id, tmdbIsTv: item.tmdbIsTv,
      isSeries: item.tmdbIsTv, genres: item.genres, cast: cast, episodes: episodes,
      releaseDate: date,
      tmdbStatus: tmdbStatus,
      tmdbTheatricalRelease: theatricalRelease,
    );
  }

  Future<String?> alternatePosterFor(MediaItem item) async {
    final id = item.tmdbId;
    if (id == null || item.sourceId != 'tmdb:catalog') return null;
    final kind = item.tmdbIsTv ? 'tv' : 'movie';
    try {
      final response = await _dio.get<dynamic>('${Tmdb.base}/$kind/$id/images', queryParameters: {'include_image_language': 'en,null'}, options: Options(receiveTimeout: const Duration(seconds: 8), sendTimeout: const Duration(seconds: 8)));
      final rows = response.data is Map ? response.data['posters'] : null;
      if (rows is! List || rows.length < 2) return null;
      final posters = [for (final row in rows) if (row is Map) row];
      final primaryPath = item.cover == null ? null : Uri.tryParse(item.cover!)?.pathSegments.last;
      posters.removeWhere((p) => primaryPath != null && p['file_path'] == '/$primaryPath');
      if (posters.isEmpty) return null;
      posters.sort((a,b) {
        final an = a['iso_639_1'] == null ? 1 : 0;
        final bn = b['iso_639_1'] == null ? 1 : 0;
        if (an != bn) return bn.compareTo(an);
        final av = (a['vote_average'] as num?)?.toDouble() ?? 0;
        final bv = (b['vote_average'] as num?)?.toDouble() ?? 0;
        return bv.compareTo(av);
      });
      final path = posters.first['file_path']?.toString();
      return path == null || path.isEmpty ? null : '${Tmdb.img}/w780$path';
    } catch (_) { return null; }
  }

  Future<List<Episode>> _loadTmdbSeason(int id, int seasonNumber) async {
    try {
      final response = await _dio.get<dynamic>(
        '${Tmdb.base}/tv/$id/season/$seasonNumber',
        options: Options(
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      );
      final rawData = response.data;
      if (rawData is! Map) return const [];
      final rows = rawData['episodes'];
      if (rows is! List) return const [];
      return <Episode>[
        for (final e in rows)
          if (e is Map && e['episode_number'] is num)
            Episode(
              id: 'tmdb:tv:$id:s$seasonNumber:e${(e['episode_number'] as num).toInt()}:${e['id'] ?? ''}',
              title: (e['name'] ?? 'Episode ${(e['episode_number'] as num).toInt()}').toString(),
              number: (e['episode_number'] as num).toDouble(),
              url: 'tmdb://tv/$id/season/$seasonNumber/episode/${(e['episode_number'] as num).toInt()}',
              date: e['air_date']?.toString(),
              thumbnail: e['still_path'] is String && (e['still_path'] as String).isNotEmpty ? '${Tmdb.img}/w342${e['still_path']}' : null,
              season: seasonNumber,
              description: e['overview']?.toString(),
              metaTitle: e['name']?.toString(),
              rating: double.tryParse('${e['vote_average'] ?? ''}'),
              runtimeMinutes: (e['runtime'] as num?)?.toInt(),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

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

    final out = <MediaItem>[];
    final personIds = <int>[];
    for (final row in rows) {
      if (row is Map) {
        if (row['media_type'] == 'person' && row['id'] is num) {
          personIds.add((row['id'] as num).toInt());
        }
        out.addAll(_mapSearchRow(row, type: type, genre: genre));
      }
    }

    // If search matched an actor/person, fetch their popular filmography
    if (page == 1 && personIds.isNotEmpty) {
      for (final pid in personIds.take(2)) {
        try {
          final creditsRes = await _dio.get<dynamic>(
            '${Tmdb.base}/person/$pid/combined_credits',
            options: Options(receiveTimeout: const Duration(seconds: 8)),
          );
          final cast = creditsRes.data is Map ? creditsRes.data['cast'] : null;
          if (cast is List) {
            final sortedCast = List<Map>.from(cast.whereType<Map>());
            sortedCast.sort((a, b) => ((b['popularity'] as num?) ?? 0).compareTo((a['popularity'] as num?) ?? 0));
            final seen = out.map((i) => i.id).toSet();
            for (final r in sortedCast.take(15)) {
              for (final item in _mapSearchRow(r, type: type, genre: genre)) {
                if (seen.add(item.id)) out.add(item);
              }
            }
          }
        } catch (_) {}
      }
    }

    // If query could be a studio/company (e.g. "Marvel", "Pixar", "A24", "HBO")
    if (page == 1 && out.length < 15) {
      try {
        final companyRes = await _dio.get<dynamic>(
          '${Tmdb.base}/search/company',
          queryParameters: {'query': query, 'page': 1},
          options: Options(receiveTimeout: const Duration(seconds: 8)),
        );
        final cRows = companyRes.data is Map ? companyRes.data['results'] : null;
        if (cRows is List && cRows.isNotEmpty) {
          final firstComp = cRows.first;
          final cId = (firstComp is Map ? firstComp['id'] : null)?.toString();
          if (cId != null) {
            final compMoviesRes = await _dio.get<dynamic>(
              '${Tmdb.base}/discover/movie',
              queryParameters: {'with_companies': cId, 'page': 1, 'sort_by': 'popularity.desc'},
              options: Options(receiveTimeout: const Duration(seconds: 8)),
            );
            final compTvRes = await _dio.get<dynamic>(
              '${Tmdb.base}/discover/tv',
              queryParameters: {'with_companies': cId, 'page': 1, 'sort_by': 'popularity.desc'},
              options: Options(receiveTimeout: const Duration(seconds: 8)),
            );
            final mRows = compMoviesRes.data is Map ? compMoviesRes.data['results'] : null;
            final tvRows = compTvRes.data is Map ? compTvRes.data['results'] : null;
            final allCompanyRows = [
              if (mRows is List) ...mRows.whereType<Map>(),
              if (tvRows is List) ...tvRows.whereType<Map>(),
            ];
            allCompanyRows.sort((a, b) => ((b['popularity'] as num?) ?? 0).compareTo((a['popularity'] as num?) ?? 0));

            final seen = out.map((i) => i.id).toSet();
            for (final r in allCompanyRows.take(15)) {
              for (final item in _mapSearchRow(r, type: type, genre: genre)) {
                if (seen.add(item.id)) out.add(item);
              }
            }
          }
        }
      } catch (_) {}
    }

    return out;
  }

  Future<List<MediaItem>> _trending({
    required String type,
    String? genre,
    required int page,
  }) async {
    // "Trending" is intentionally a current-content feed rather than TMDB's
    // /trending endpoint. Now Playing movies and On The Air TV both expose
    // normal page-based pagination, so the Search screen can keep loading
    // beyond the first batch. TMDB documents both endpoints as paginated
    // list/discover calls.
    Future<List<MediaItem>> fetchKind(
      String endpoint,
      String resultType,
    ) async {
      final response = await _dio.get<dynamic>(
        '${Tmdb.base}/$endpoint',
        queryParameters: {'page': page},
      );
      final rows = response.data is Map ? response.data['results'] : null;
      if (rows is! List) return const [];
      return [
        for (final row in rows)
          if (row is Map)
            ..._mapSearchRow(
              row,
              type: resultType,
              genre: genre,
              trending: true,
            ),
      ];
    }

    final movies = type == 'series' || type == 'anime'
        ? const <MediaItem>[]
        : await fetchKind('movie/now_playing', 'movies');
    final shows = type == 'movies'
        ? const <MediaItem>[]
        : await fetchKind('tv/on_the_air', type == 'anime' ? 'anime' : 'series');

    final mixed = [...movies, ...shows];
    mixed.shuffle(math.Random(page * 104729));

    // Keep the Search/Discover pagination batch at roughly the same size as
    // the other catalogs even though this catalog combines two TMDB pages.
    return mixed.take(20).toList();
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
        'recent' => kind == 'tv' ? 'first_air_date.desc' : 'primary_release_date.desc',
        _ => 'popularity.desc',
      },
    };
    if (catalog == 'top_rated') params['vote_count.gte'] = 200;
    if (catalog == 'recent') params['vote_count.gte'] = 20;

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
    if (kind == 'movie') {
      params['region'] = _deviceRegion;
    }

    final response = await _dio.get<dynamic>(
      '${Tmdb.base}/discover/$kind',
      queryParameters: params,
      options: Options(receiveTimeout: const Duration(seconds: 12), sendTimeout: const Duration(seconds: 12)),
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
    if (mediaType == 'person') {
      final knownFor = row['known_for'];
      if (knownFor is List) {
        for (final item in knownFor) {
          if (item is Map) {
            yield* _mapSearchRow(item, type: type, genre: genre, trending: trending);
          }
        }
      }
      return;
    }
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
      tmdbIsAnime: type == 'anime',
      genres: genreNames,
      rating: (row['vote_average'] as num?)?.toDouble(),
      year: ((isTv ? row['first_air_date'] : row['release_date'])?.toString() ?? '')
          .trim()
          .split('-')
          .firstWhere((value) => value.isNotEmpty, orElse: () => ''),
    );
  }
}
