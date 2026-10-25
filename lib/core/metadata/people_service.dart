import 'package:dio/dio.dart';

import '../models/person.dart';

/// Loads person pages — anime characters + voice actors/staff from AniList,
/// movie/TV people from TMDB. Read-only, best-effort: any miss/failure returns
/// null and the page shows its error state. The TMDB api_key is attached by the
/// shared Dio interceptor (initDependencies), so TMDB calls need no key here.
class PeopleService {
  PeopleService(this._dio);
  final Dio _dio;

  static const String _anilist = 'https://graphql.anilist.co';
  static const String _tmdbBase = 'https://api.themoviedb.org/3';
  static const String _img = 'https://image.tmdb.org/t/p';
  static const String _tpdbBase = 'https://api.theporndb.net';
  static const String _tpdbKey = '8ABvbgloweVLDeD3HBq6x9eHpL3lMJE8qEuBtdmb213d0c62';

  final Map<int, List<PersonWork>> _tmdbCreditsCache = {};
  final Map<int, List<PersonWork>> _tmdbCompanyCreditsCache = {};
  final Map<String, int> _tmdbResolvedCompanyIds = {};
  final Map<String, String> _tpdbResolvedIds = {};
  final Map<String, PersonProfile> _profileCache = {};

  Future<PersonProfile?> load(PersonRef ref) async {
    final cacheKey = '${ref.source.name}:${ref.externalId ?? ref.id}:${ref.name.trim().toLowerCase()}';
    if (_profileCache.containsKey(cacheKey)) {
      return _profileCache[cacheKey];
    }
    final profile = await _loadDirect(ref);
    if (profile != null) {
      _profileCache[cacheKey] = profile;
    }
    return profile;
  }

  Future<PersonProfile?> _loadDirect(PersonRef ref) {
    switch (ref.source) {
      case PersonSource.anilistCharacter:
        return _character(ref.id);
      case PersonSource.anilistStaff:
        return _staff(ref.id);
      case PersonSource.tmdb:
        return _tmdbPerson(ref.id, fallbackName: ref.name);
      case PersonSource.thePornDbPerformer:
        return _tpdbPerformer(ref.externalId ?? ref.id.toString(), fallbackName: ref.name);
      case PersonSource.thePornDbStudio:
        return _tpdbStudio(ref.externalId ?? ref.id.toString(), fallbackName: ref.name);
      case PersonSource.tmdbCompany:
        return _tmdbCompany(ref.id, fallbackName: ref.name);
    }
  }

  /// Loads additional works/movies for a person (e.g. for infinite scroll).
  Future<List<PersonWork>> loadWorks(PersonRef ref, {required int page}) async {
    switch (ref.source) {
      case PersonSource.thePornDbPerformer:
        final rawId = ref.externalId ?? (ref.id != 0 ? ref.id.toString() : null);
        final id = _tpdbResolvedIds[rawId ?? ''] ?? _tpdbResolvedIds[ref.name] ?? rawId;
        if (id == null || id.isEmpty) return const [];
        return _tpdbPerformerWorks(id, page: page);
      case PersonSource.thePornDbStudio:
        final rawId = ref.externalId ?? (ref.id != 0 ? ref.id.toString() : null);
        final id = _tpdbResolvedIds[rawId ?? ''] ?? _tpdbResolvedIds[ref.name] ?? rawId;
        if (id == null || id.isEmpty) return const [];
        return _tpdbStudioWorks(id, studioName: ref.name, page: page);
      case PersonSource.tmdb:
        final all = _tmdbCreditsCache[ref.id];
        if (all == null) return const [];
        final startIndex = (page - 1) * 30;
        if (startIndex >= all.length) return const [];
        final endIndex = (startIndex + 30 < all.length) ? startIndex + 30 : all.length;
        return all.sublist(startIndex, endIndex);
      case PersonSource.tmdbCompany:
        return _tmdbCompanyWorks(ref.id, fallbackName: ref.name, page: page);
      case PersonSource.anilistCharacter:
      case PersonSource.anilistStaff:
        return const [];
    }
  }

  Future<List<PersonWork>> _tpdbPerformerWorks(
    String performerId, {
    required int page,
    Map<String, PersonRef>? relatedMap,
    String? currentPerformerName,
  }) async {
    try {
      final movies = await _dio.get<dynamic>(
        '$_tpdbBase/performers/$performerId/movies',
        queryParameters: {'page': page, 'per_page': 30},
        options: Options(headers: {'Authorization': 'Bearer $_tpdbKey'}),
      );
      final rows = movies.data is Map ? movies.data['data'] : null;
      if (rows is! List) return const [];
      final works = <PersonWork>[];
      for (final m in rows) {
        if (m is! Map) continue;
        final title = (m['title'] ?? m['name'])?.toString();
        if (title == null || title.isEmpty) continue;
        final bdrop = (m['background'] is Map ? m['background']['large'] : null) ??
            m['image'] ??
            m['poster'];
        final date = (m['date'] ?? m['release_date'])?.toString();
        works.add(PersonWork(
          title: title,
          cover: _tpdbImage(m),
          backdrop: bdrop?.toString(),
          catalogId: (m['id'] ?? m['_id'] ?? m['uuid'] ?? m['slug'])?.toString(),
          releaseDate: date,
        ));

        if (relatedMap != null) {
          final perfs = m['performers'];
          if (perfs is List) {
            for (final p in perfs) {
              if (p is! Map) continue;
              final pName = (p['name'] ?? p['full_name'])?.toString();
              final pId = (p['id'] ?? p['_id'] ?? p['slug'])?.toString();
              if (pName != null &&
                  pName.isNotEmpty &&
                  (currentPerformerName == null ||
                      pName.toLowerCase() != currentPerformerName.toLowerCase()) &&
                  pId != null) {
                relatedMap.putIfAbsent(
                  pId,
                  () => PersonRef(
                    id: int.tryParse(pId) ?? 0,
                    source: PersonSource.thePornDbPerformer,
                    name: pName,
                    photo: (p['image'] ?? p['thumbnail'] ?? p['face'])?.toString(),
                    externalId: pId,
                  ),
                );
              }
            }
          }
        }
      }
      return works;
    } catch (_) {
      return const [];
    }
  }

  Future<PersonProfile?> _tpdbPerformer(String id, {String? fallbackName}) async {
    try {
      Map<String, dynamic>? row;
      try {
        final res = await _dio.get<dynamic>(
          '$_tpdbBase/performers/$id',
          options: Options(headers: {'Authorization': 'Bearer $_tpdbKey'}),
        );
        if (res.data is Map && res.data['data'] is Map) {
          row = Map<String, dynamic>.from(res.data['data'] as Map);
        }
      } catch (_) {}

      // Fallback: If direct lookup failed and we have a performer name, search for them
      if (row == null && fallbackName != null && fallbackName.trim().isNotEmpty) {
        try {
          final searchRes = await _dio.get<dynamic>(
            '$_tpdbBase/performers',
            queryParameters: {
              'q': fallbackName.trim(),
              'per_page': 10,
              'orderBy': 'most_relevant',
            },
            options: Options(headers: {'Authorization': 'Bearer $_tpdbKey'}),
          );
          final rows = searchRes.data is Map ? searchRes.data['data'] : null;
          if (rows is List && rows.isNotEmpty) {
            final first = rows.first;
            if (first is Map) {
              row = Map<String, dynamic>.from(first);
            }
          }
        } catch (_) {}
      }

      if (row == null) return null;
      final name = (row['name'] ?? row['full_name'] ?? fallbackName)?.toString();
      if (name == null || name.isEmpty) return null;
      final resolvedId = (row['id'] ?? row['uuid'] ?? row['_id'] ?? row['slug'] ?? id).toString();
      _tpdbResolvedIds[id] = resolvedId;
      _tpdbResolvedIds[name] = resolvedId;
      if (fallbackName != null) _tpdbResolvedIds[fallbackName] = resolvedId;

      final relatedMap = <String, PersonRef>{};
      final providerVideos = <PersonWork>[];

      // Run movies works & scenes in parallel for fast loading
      final futureWorks = _tpdbPerformerWorks(
        resolvedId,
        page: 1,
        relatedMap: relatedMap,
        currentPerformerName: name,
      );

      final futureScenes = _dio.get<dynamic>(
        '$_tpdbBase/scenes',
        queryParameters: {
          'q': name,
          'per_page': 24,
          'orderBy': 'most_relevant',
        },
        options: Options(
          headers: {'Authorization': 'Bearer $_tpdbKey'},
          receiveTimeout: const Duration(seconds: 6),
          sendTimeout: const Duration(seconds: 6),
        ),
      ).then<void>((scenesRes) {
        final sceneRows = scenesRes.data is Map ? scenesRes.data['data'] : null;
        if (sceneRows is List) {
          for (final s in sceneRows) {
            if (s is! Map) continue;
            final sTitle = (s['title'] ?? s['name'])?.toString();
            if (sTitle == null || sTitle.isEmpty) continue;
            final sImg = (s['background'] is Map ? s['background']['large'] : null) ??
                s['image'] ??
                s['poster'] ??
                _tpdbImage(s);
            final sId = (s['id'] ?? s['_id'] ?? s['uuid'])?.toString();
            final sDate = s['date']?.toString();

            providerVideos.add(PersonWork(
              title: sTitle,
              cover: sImg?.toString(),
              backdrop: sImg?.toString(),
              catalogId: sId,
              releaseDate: sDate,
              isScene: true,
            ));

            final perfs = s['performers'];
            if (perfs is List) {
              for (final p in perfs) {
                if (p is! Map) continue;
                final pName = (p['name'] ?? p['full_name'])?.toString();
                final pId = (p['id'] ?? p['_id'] ?? p['slug'])?.toString();
                if (pName != null &&
                    pName.isNotEmpty &&
                    pName.toLowerCase() != name.toLowerCase() &&
                    pId != null) {
                  relatedMap.putIfAbsent(
                    pId,
                    () => PersonRef(
                      id: int.tryParse(pId) ?? 0,
                      source: PersonSource.thePornDbPerformer,
                      name: pName,
                      photo: (p['image'] ?? p['thumbnail'] ?? p['face'])?.toString(),
                      externalId: pId,
                    ),
                  );
                }
              }
            }
          }
        }
      }, onError: (_, __) {});

      final works = await futureWorks;
      await futureScenes;

      final photoList = <String>[];
      final seenUrls = <String>{};

      void addPhoto(dynamic url) {
        if (url == null) return;
        final s = url.toString().trim();
        if (s.isNotEmpty && s.startsWith('http') && seenUrls.add(s)) {
          photoList.add(s);
        }
      }

      // 1. Primary official image
      addPhoto(row['image']);

      // 2. High-res posters array
      final posters = row['posters'];
      if (posters is List) {
        for (final p in posters) {
          if (p is Map) {
            addPhoto(p['url'] ?? p['image']);
          } else if (p is String) {
            addPhoto(p);
          }
        }
      }

      // 3. Site/studio posters
      final sitePerfs = row['site_performers'];
      if (sitePerfs is List) {
        for (final sp in sitePerfs) {
          if (sp is Map) {
            addPhoto(sp['image']);
          }
        }
      }

      // 4. Fallback thumbnail/face
      if (photoList.isEmpty) {
        addPhoto(row['thumbnail'] ?? row['face']);
      }

      final bestPhoto = photoList.isNotEmpty ? photoList.first : null;
      final rating = (row['rating'] as num?)?.toDouble() ??
          double.tryParse('${row['rating']}') ??
          (row['extras'] is Map ? (row['extras']['rating'] as num?)?.toDouble() : null);

      return PersonProfile(
        name: name,
        photo: bestPhoto,
        photos: photoList,
        description: (row['description'] ?? row['bio'])?.toString(),
        subtitle: 'Performer',
        rating: rating,
        works: works,
        providerVideos: providerVideos,
        related: relatedMap.values.take(16).toList(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<PersonProfile?> _tpdbStudio(String id, {String? fallbackName}) async {
    try {
      Map<String, dynamic>? row;
      try {
        final res = await _dio.get<dynamic>(
          '$_tpdbBase/sites/$id',
          options: Options(headers: {'Authorization': 'Bearer $_tpdbKey'}),
        );
        if (res.data is Map && res.data['data'] is Map) {
          row = Map<String, dynamic>.from(res.data['data'] as Map);
        }
      } catch (_) {}

      if (row == null && fallbackName != null && fallbackName.trim().isNotEmpty) {
        try {
          final searchRes = await _dio.get<dynamic>(
            '$_tpdbBase/sites',
            queryParameters: {
              'q': fallbackName.trim(),
              'per_page': 10,
              'orderBy': 'most_relevant',
            },
            options: Options(headers: {'Authorization': 'Bearer $_tpdbKey'}),
          );
          final rows = searchRes.data is Map ? searchRes.data['data'] : null;
          if (rows is List && rows.isNotEmpty && rows.first is Map) {
            row = Map<String, dynamic>.from(rows.first as Map);
          }
        } catch (_) {}
      }

      final name = (row?['name'] ?? row?['short_name'] ?? fallbackName)?.toString();
      if (name == null || name.isEmpty) return null;
      final resolvedId = (row?['id'] ?? row?['uuid'] ?? row?['short_name'] ?? id).toString();
      _tpdbResolvedIds[id] = resolvedId;
      _tpdbResolvedIds[name] = resolvedId;
      if (fallbackName != null) _tpdbResolvedIds[fallbackName] = resolvedId;

      final photoList = <String>[];
      for (final key in ['logo', 'poster', 'favicon', 'image', 'thumbnail']) {
        final v = row?[key]?.toString();
        if (v != null && v.isNotEmpty) { photoList.add(v); break; }
      }

      final network = row?['network'];
      final subtitle = (network is Map ? network['name']?.toString() : null) ?? 'Studio';

      // Load studio movies and scenes in parallel
      final providerVideos = <PersonWork>[];
      final relatedMap = <String, PersonRef>{};
      final appearances = <String, int>{};

      final futureWorks = _tpdbStudioWorks(resolvedId, studioName: name, page: 1);

      final futureScenes = _dio.get<dynamic>(
        '$_tpdbBase/scenes',
        queryParameters: {
          'q': name,
          'per_page': 50,
          'orderBy': 'most_relevant',
        },
        options: Options(
          headers: {'Authorization': 'Bearer $_tpdbKey'},
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      ).then<void>((scenesRes) {
        final sceneRows = scenesRes.data is Map ? scenesRes.data['data'] : null;
        if (sceneRows is List) {
          for (final s in sceneRows) {
            if (s is! Map) continue;
            final sTitle = (s['title'] ?? s['name'])?.toString();
            if (sTitle == null || sTitle.isEmpty) continue;
            final sImg = (s['background'] is Map ? s['background']['large'] : null) ??
                s['image'] ??
                s['poster'] ??
                _tpdbImage(s);
            final sId = (s['id'] ?? s['_id'] ?? s['uuid'])?.toString();
            final sDate = s['date']?.toString();

            providerVideos.add(PersonWork(
              title: sTitle,
              cover: sImg?.toString(),
              backdrop: sImg?.toString(),
              catalogId: sId,
              releaseDate: sDate,
              isScene: true,
            ));

            final perfs = s['performers'];
            if (perfs is List) {
              for (final p in perfs) {
                if (p is! Map) continue;
                final pName = (p['name'] ?? p['full_name'])?.toString();
                final pId = (p['id'] ?? p['_id'] ?? p['slug'])?.toString();
                if (pName != null && pName.isNotEmpty && pId != null) {
                  appearances[pId] = (appearances[pId] ?? 0) + 1;
                  final pRating = (p['rating'] as num?)?.toDouble() ??
                      double.tryParse('${p['rating']}');
                  relatedMap.putIfAbsent(
                    pId,
                    () => PersonRef(
                      id: int.tryParse(pId) ?? 0,
                      source: PersonSource.thePornDbPerformer,
                      name: pName,
                      photo: (p['image'] ?? p['thumbnail'] ?? p['face'])?.toString(),
                      externalId: pId,
                      rating: pRating,
                    ),
                  );
                }
              }
            }
          }
        }
      }, onError: (_, __) {});

      final works = await futureWorks;
      await futureScenes;

      for (final w in works) {
        if (w.backdrop != null && w.backdrop!.isNotEmpty && !photoList.contains(w.backdrop)) {
          photoList.add(w.backdrop!);
          if (photoList.length >= 8) break;
        }
      }
      for (final pv in providerVideos) {
        if (pv.backdrop != null && pv.backdrop!.isNotEmpty && !photoList.contains(pv.backdrop)) {
          photoList.add(pv.backdrop!);
          if (photoList.length >= 8) break;
        }
      }

      final studioLogo = photoList.isNotEmpty ? photoList.first : null;
      final sortedRelated = relatedMap.values.toList()
        ..sort((a, b) {
          final ca = appearances[a.externalId ?? a.id.toString()] ?? 0;
          final cb = appearances[b.externalId ?? b.id.toString()] ?? 0;
          return cb.compareTo(ca);
        });

      String? description = (row?['description'] ?? row?['about'])?.toString();
      if (description == null || description.trim().isEmpty) {
        final net = row?['network'];
        if (net is Map && net['description'] != null) {
          description = net['description'].toString();
        }
      }

      return PersonProfile(
        name: name,
        photo: studioLogo,
        photos: photoList,
        description: (description != null && description.trim().isNotEmpty) ? description.trim() : null,
        subtitle: subtitle,
        works: works,
        providerVideos: providerVideos,
        related: sortedRelated.take(30).toList(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<PersonProfile?> _tmdbCompany(int id, {String? fallbackName}) async {
    try {
      int companyId = id;
      Map<String, dynamic>? details;
      if (companyId > 0) {
        details = await _get('$_tmdbBase/company/$companyId');
      }

      if (details == null && fallbackName != null && fallbackName.trim().isNotEmpty) {
        final searchRes = await _get(
          '$_tmdbBase/search/company?query=${Uri.encodeComponent(fallbackName.trim())}',
        );
        final results = searchRes?['results'] as List?;
        if (results != null && results.isNotEmpty && results.first is Map) {
          final first = results.first as Map;
          companyId = (first['id'] as num?)?.toInt() ?? 0;
          if (companyId > 0) {
            details = await _get('$_tmdbBase/company/$companyId');
          }
        }
      }

      if (companyId <= 0) return null;
      _tmdbResolvedCompanyIds[fallbackName ?? ''] = companyId;

      final name = (details?['name'] ?? fallbackName)?.toString() ?? 'Studio';
      final logoPath = details?['logo_path'] as String?;
      final logo = (logoPath != null && logoPath.isNotEmpty) ? '$_img/w780$logoPath' : null;
      final headquarters = details?['headquarters'] as String?;
      final description = (details?['description'] as String?)?.trim();
      final parentComp = details?['parent_company'] as Map?;

      final subtitle = (headquarters != null && headquarters.isNotEmpty)
          ? '$headquarters · Studio'
          : 'Production Studio';

      // Load movies & TV shows
      final movieRes = await _get(
        '$_tmdbBase/discover/movie?with_companies=$companyId&sort_by=popularity.desc&page=1',
      );
      final tvRes = await _get(
        '$_tmdbBase/discover/tv?with_companies=$companyId&sort_by=popularity.desc&page=1',
      );

      final works = <PersonWork>[];
      final movieRows = movieRes?['results'] is List ? movieRes!['results'] as List : const [];
      final tvRows = tvRes?['results'] is List ? tvRes!['results'] as List : const [];

      for (final m in movieRows.whereType<Map>()) {
        final title = (m['title'] ?? m['name']) as String?;
        if (title == null || title.isEmpty) continue;
        final poster = m['poster_path'] as String?;
        final backdrop = m['backdrop_path'] as String?;
        works.add(PersonWork(
          title: title,
          cover: (poster != null && poster.isNotEmpty) ? '$_img/w342$poster' : null,
          backdrop: (backdrop != null && backdrop.isNotEmpty) ? '$_img/w780$backdrop' : null,
          catalogId: m['id']?.toString(),
          isTv: false,
          releaseDate: m['release_date']?.toString(),
          rating: (m['vote_average'] as num?)?.toDouble(),
          popularity: (m['popularity'] as num?)?.toDouble(),
        ));
      }

      for (final t in tvRows.whereType<Map>()) {
        final title = (t['name'] ?? t['title']) as String?;
        if (title == null || title.isEmpty) continue;
        final poster = t['poster_path'] as String?;
        final backdrop = t['backdrop_path'] as String?;
        works.add(PersonWork(
          title: title,
          cover: (poster != null && poster.isNotEmpty) ? '$_img/w342$poster' : null,
          backdrop: (backdrop != null && backdrop.isNotEmpty) ? '$_img/w780$backdrop' : null,
          catalogId: t['id']?.toString(),
          isTv: true,
          releaseDate: t['first_air_date']?.toString(),
          rating: (t['vote_average'] as num?)?.toDouble(),
          popularity: (t['popularity'] as num?)?.toDouble(),
        ));
      }

      works.sort((a, b) => ((b.popularity ?? 0)).compareTo(a.popularity ?? 0));
      _tmdbCompanyCreditsCache[companyId] = works;

      final photoList = <String>[];
      if (logo != null) photoList.add(logo);
      for (final w in works) {
        if (w.backdrop != null && w.backdrop!.isNotEmpty && !photoList.contains(w.backdrop)) {
          photoList.add(w.backdrop!);
          if (photoList.length >= 8) break;
        }
      }

      final providerVideos = works.where((w) => w.backdrop != null).take(15).toList();

      final related = <PersonRef>[];
      if (parentComp != null && parentComp['name'] != null) {
        final pId = (parentComp['id'] as num?)?.toInt() ?? 0;
        final pLogo = parentComp['logo_path'] != null ? '$_img/w185${parentComp['logo_path']}' : null;
        related.add(PersonRef(
          id: pId,
          source: PersonSource.tmdbCompany,
          name: parentComp['name'].toString(),
          photo: pLogo,
        ));
      }

      if (works.isNotEmpty) {
        final topWorks = works.take(6).toList();
        final castCount = <int, int>{};
        final castMap = <int, PersonRef>{};

        await Future.wait(topWorks.map((w) async {
          if (w.catalogId == null) return;
          try {
            final topType = w.isTv ? 'tv' : 'movie';
            final topCredits = await _get('$_tmdbBase/$topType/${w.catalogId}/credits');
            final topCast = topCredits?['cast'];
            if (topCast is List) {
              for (final personRow in topCast.whereType<Map>()) {
                final pId = (personRow['id'] as num?)?.toInt();
                final pName = personRow['name'] as String?;
                final pPic = personRow['profile_path'] as String?;
                if (pId != null && pName != null && pName.isNotEmpty) {
                  castCount[pId] = (castCount[pId] ?? 0) + 1;
                  castMap.putIfAbsent(
                    pId,
                    () => PersonRef(
                      id: pId,
                      source: PersonSource.tmdb,
                      name: pName,
                      photo: (pPic != null && pPic.isNotEmpty) ? '$_img/w185$pPic' : null,
                    ),
                  );
                }
              }
            }
          } catch (_) {}
        }));

        final sortedCast = castMap.values.toList()
          ..sort((a, b) => (castCount[b.id] ?? 0).compareTo(castCount[a.id] ?? 0));
        related.addAll(sortedCast.take(24));
      }

      return PersonProfile(
        name: name,
        photo: logo ?? (photoList.isNotEmpty ? photoList.first : null),
        photos: photoList,
        description: (description != null && description.isNotEmpty) ? description : null,
        subtitle: subtitle,
        works: works,
        providerVideos: providerVideos,
        related: related,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<PersonWork>> _tmdbCompanyWorks(int id, {String? fallbackName, required int page}) async {
    try {
      final resolvedId = id > 0 ? id : _tmdbResolvedCompanyIds[fallbackName ?? ''];
      if (resolvedId == null || resolvedId <= 0) return const [];
      final moviesRes = await _get(
        '$_tmdbBase/discover/movie?with_companies=$resolvedId&sort_by=popularity.desc&page=$page',
      );
      final tvRes = await _get(
        '$_tmdbBase/discover/tv?with_companies=$resolvedId&sort_by=popularity.desc&page=$page',
      );
      final movieRows = moviesRes?['results'] is List ? moviesRes!['results'] as List : const [];
      final tvRows = tvRes?['results'] is List ? tvRes!['results'] as List : const [];
      final works = <PersonWork>[];
      for (final m in movieRows.whereType<Map>()) {
        final title = (m['title'] ?? m['name']) as String?;
        if (title == null || title.isEmpty) continue;
        final poster = m['poster_path'] as String?;
        final backdrop = m['backdrop_path'] as String?;
        works.add(PersonWork(
          title: title,
          cover: (poster != null && poster.isNotEmpty) ? '$_img/w342$poster' : null,
          backdrop: (backdrop != null && backdrop.isNotEmpty) ? '$_img/w780$backdrop' : null,
          catalogId: m['id']?.toString(),
          isTv: false,
          releaseDate: m['release_date']?.toString(),
          rating: (m['vote_average'] as num?)?.toDouble(),
          popularity: (m['popularity'] as num?)?.toDouble(),
        ));
      }
      for (final t in tvRows.whereType<Map>()) {
        final title = (t['name'] ?? t['title']) as String?;
        if (title == null || title.isEmpty) continue;
        final poster = t['poster_path'] as String?;
        final backdrop = t['backdrop_path'] as String?;
        works.add(PersonWork(
          title: title,
          cover: (poster != null && poster.isNotEmpty) ? '$_img/w342$poster' : null,
          backdrop: (backdrop != null && backdrop.isNotEmpty) ? '$_img/w780$backdrop' : null,
          catalogId: t['id']?.toString(),
          isTv: true,
          releaseDate: t['first_air_date']?.toString(),
          rating: (t['vote_average'] as num?)?.toDouble(),
          popularity: (t['popularity'] as num?)?.toDouble(),
        ));
      }
      works.sort((a, b) => ((b.popularity ?? 0)).compareTo(a.popularity ?? 0));
      return works;
    } catch (_) {
      return const [];
    }
  }


  Future<List<PersonWork>> _tpdbStudioWorks(String siteId, {String? studioName, required int page}) async {
    try {
      Response<dynamic>? res;
      try {
        res = await _dio.get<dynamic>(
          '$_tpdbBase/sites/$siteId/movies',
          queryParameters: {'page': page, 'per_page': 30},
          options: Options(headers: {'Authorization': 'Bearer $_tpdbKey'}),
        );
      } catch (_) {}

      var rows = res?.data is Map ? res?.data['data'] : null;
      if (rows is! List || rows.isEmpty) {
        final queryName = (studioName != null && studioName.isNotEmpty) ? studioName : siteId;
        res = await _dio.get<dynamic>(
          '$_tpdbBase/movies',
          queryParameters: {
            'q': queryName,
            'page': page,
            'per_page': 30,
            'orderBy': 'recently_released',
          },
          options: Options(headers: {'Authorization': 'Bearer $_tpdbKey'}),
        );
        rows = res.data is Map ? res.data['data'] : null;
      }

      if (rows is! List) return const [];
      final works = <PersonWork>[];
      for (final m in rows) {
        if (m is! Map) continue;
        final title = (m['title'] ?? m['name'])?.toString();
        if (title == null || title.isEmpty) continue;
        works.add(PersonWork(
          title: title,
          cover: _tpdbImage(m),
          catalogId: (m['id'] ?? m['_id'] ?? m['uuid'] ?? m['slug'])?.toString(),
        ));
      }
      return works;
    } catch (_) {
      return const [];
    }
  }

  String? _tpdbImage(Map row) {
    final posters = row['posters'] ?? row['images'];
    if (posters is Map) {
      for (final key in ['original', 'full', 'large', 'medium', 'small']) {
        final v = posters[key]?.toString();
        if (v != null && v.isNotEmpty) return v;
      }
    }
    for (final key in ['poster', 'poster_image', 'image', 'thumbnail']) {
      final v = row[key]?.toString();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  // ── AniList ─────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _gql(String query, Map<String, dynamic> vars) async {
    try {
      final res = await _dio.post<dynamic>(
        _anilist,
        data: {'query': query, 'variables': vars},
        options: Options(
          headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      final data = res.data;
      if (data is Map && data['data'] is Map) {
        return Map<String, dynamic>.from(data['data'] as Map);
      }
    } catch (_) {}
    return null;
  }

  Future<PersonProfile?> _character(int id) async {
    const q =
        'query(\$id:Int){ Character(id:\$id){ '
        'name{ full native } image{ large } description(asHtml:false) '
        'media(type:ANIME,sort:[POPULARITY_DESC],perPage:25){ edges{ characterRole '
        'node{ idMal title{ romaji english } coverImage{ large } } '
        'voiceActors(language:JAPANESE){ id name{ full } image{ large } } } } } }';
    final d = await _gql(q, {'id': id});
    final c = d?['Character'];
    if (c is! Map) return null;

    final works = <PersonWork>[];
    final vaById = <int, PersonRef>{};
    final edges = (c['media'] is Map) ? c['media']['edges'] : null;
    if (edges is List) {
      for (final e in edges) {
        if (e is! Map) continue;
        final node = e['node'];
        final title = _aniTitle(node);
        if (title != null) {
          works.add(PersonWork(
            title: title,
            romaji: _aniRomaji(node),
            cover: _aniImage(node, 'coverImage'),
            subtitle: _titleCase(e['characterRole'] as String?),
            malId: _aniMalId(node),
          ));
        }
        final vas = e['voiceActors'];
        if (vas is List) {
          for (final v in vas) {
            final ref = _staffRef(v);
            if (ref != null) vaById.putIfAbsent(ref.id, () => ref);
          }
        }
      }
    }
    return PersonProfile(
      name: _aniName(c) ?? 'Character',
      nativeName: _aniNative(c),
      photo: _aniImage(c, 'image'),
      description: _plain(c['description'] as String?),
      subtitle: 'Character',
      works: works,
      related: vaById.values.toList(),
    );
  }

  Future<PersonProfile?> _staff(int id) async {
    const q =
        'query(\$id:Int){ Staff(id:\$id){ '
        'name{ full native } image{ large } description(asHtml:false) '
        'primaryOccupations '
        'characterMedia(sort:[POPULARITY_DESC],perPage:25){ edges{ '
        'characters{ name{ full } } '
        'node{ idMal title{ romaji english } coverImage{ large } } } } '
        // What this person MADE, as opposed to characterMedia's "who they
        // voiced". A manga author voices nobody, so characterMedia comes back
        // empty for them and their page had nothing on it — staffMedia is the
        // field that answers "show me everything they wrote".
        'staffMedia(sort:[POPULARITY_DESC],perPage:25){ edges{ staffRole '
        'node{ idMal title{ romaji english } coverImage{ large } } } } } }';
    final d = await _gql(q, {'id': id});
    final s = d?['Staff'];
    if (s is! Map) return null;

    final works = <PersonWork>[];
    final seenTitles = <String>{};
    final edges = (s['characterMedia'] is Map) ? s['characterMedia']['edges'] : null;
    if (edges is List) {
      for (final e in edges) {
        if (e is! Map) continue;
        final title = _aniTitle(e['node']);
        if (title == null) continue;
        String? character;
        final chars = e['characters'];
        if (chars is List && chars.isNotEmpty && chars.first is Map) {
          final n = (chars.first as Map)['name'];
          if (n is Map) character = n['full'] as String?;
        }
        if (!seenTitles.add(title)) continue;
        works.add(PersonWork(
          title: title,
          romaji: _aniRomaji(e['node']),
          cover: _aniImage(e['node'], 'coverImage'),
          subtitle: character,
          malId: _aniMalId(e['node']),
        ));
      }
    }

    // Then the things they worked ON, deduped against the above so someone who
    // both voiced and directed a title isn't listed twice.
    final staffEdges = (s['staffMedia'] is Map) ? s['staffMedia']['edges'] : null;
    if (staffEdges is List) {
      for (final e in staffEdges) {
        if (e is! Map) continue;
        final title = _aniTitle(e['node']);
        if (title == null || !seenTitles.add(title)) continue;
        works.add(PersonWork(
          title: title,
          romaji: _aniRomaji(e['node']),
          cover: _aniImage(e['node'], 'coverImage'),
          subtitle: e['staffRole'] as String?,
          malId: _aniMalId(e['node']),
        ));
      }
    }

    final occ = s['primaryOccupations'];
    final subtitle = (occ is List && occ.isNotEmpty) ? '${occ.first}' : null;
    return PersonProfile(
      name: _aniName(s) ?? 'Staff',
      nativeName: _aniNative(s),
      photo: _aniImage(s, 'image'),
      description: _plain(s['description'] as String?),
      subtitle: subtitle,
      works: works,
    );
  }

  PersonRef? _staffRef(dynamic v) {
    if (v is! Map || v['id'] == null) return null;
    final n = v['name'];
    final name = (n is Map) ? n['full'] as String? : null;
    if (name == null || name.isEmpty) return null;
    return PersonRef(
      id: (v['id'] as num).toInt(),
      source: PersonSource.anilistStaff,
      name: name,
      photo: _aniImage(v, 'image'),
    );
  }

  String? _aniName(Map m) => (m['name'] is Map) ? m['name']['full'] as String? : null;
  String? _aniNative(Map m) {
    final n = (m['name'] is Map) ? m['name']['native'] as String? : null;
    return (n != null && n.isNotEmpty) ? n : null;
  }

  String? _aniTitle(dynamic node) {
    if (node is! Map || node['title'] is! Map) return null;
    final t = node['title'] as Map;
    final title = (t['english'] ?? t['romaji']) as String?;
    return (title != null && title.isNotEmpty) ? title : null;
  }

  String? _aniRomaji(dynamic node) {
    if (node is! Map || node['title'] is! Map) return null;
    final r = (node['title'] as Map)['romaji'] as String?;
    return (r != null && r.isNotEmpty) ? r : null;
  }

  String? _aniImage(dynamic m, String key) {
    if (m is! Map || m[key] is! Map) return null;
    final img = (m[key] as Map)['large'] ?? (m[key] as Map)['medium'];
    return (img is String && img.isNotEmpty) ? img : null;
  }

  int? _aniMalId(dynamic node) =>
      (node is Map) ? (node['idMal'] as num?)?.toInt() : null;

  // ── TMDB ────────────────────────────────────────────────────────────────────

  Future<PersonProfile?> _tmdbPerson(int id, {String? fallbackName}) async {
    Map<String, dynamic>? person;
    int personId = id;
    if (personId > 0) {
      person = await _get('$_tmdbBase/person/$personId');
    }
    if (person == null && fallbackName != null && fallbackName.trim().isNotEmpty) {
      final searchRes = await _get(
        '$_tmdbBase/search/person?query=${Uri.encodeComponent(fallbackName.trim())}',
      );
      final results = searchRes?['results'] as List?;
      if (results != null && results.isNotEmpty && results.first is Map) {
        final first = results.first as Map;
        personId = (first['id'] as num?)?.toInt() ?? 0;
        if (personId > 0) {
          person = await _get('$_tmdbBase/person/$personId');
        }
      }
    }
    if (person == null) return null;
    final name = (person['name'] ?? fallbackName) as String?;
    if (name == null || name.isEmpty) return null;

    final works = <PersonWork>[];
    final providerVideos = <PersonWork>[];
    final credits = await _get('$_tmdbBase/person/$personId/combined_credits');
    final castList = credits?['cast'];
    final crewList = credits?['crew'];
    final related = <PersonRef>[];
    final seenIds = <String>{};

    void processCreditList(List? list, {required bool isCrew}) {
      if (list is! List) return;
      final sorted = list.whereType<Map>().toList()
        ..sort((a, b) =>
            ((b['popularity'] as num?) ?? 0).compareTo((a['popularity'] as num?) ?? 0));
      for (final c in sorted) {
        final title = (c['title'] ?? c['name']) as String?;
        if (title == null || title.isEmpty) continue;
        final poster = c['poster_path'] as String?;
        final backdrop = c['backdrop_path'] as String?;
        final mediaId = c['id']?.toString();
        final key = mediaId ?? title;
        if (!seenIds.add(key)) continue;

        final isTv = c['media_type'] == 'tv';
        final releaseDate = (c['release_date'] ?? c['first_air_date'])?.toString();
        final rating = (c['vote_average'] as num?)?.toDouble();
        final pop = (c['popularity'] as num?)?.toDouble();
        final role = isCrew ? (c['job'] as String?) : (c['character'] as String?);

        final work = PersonWork(
          title: title,
          cover: (poster != null && poster.isNotEmpty) ? '$_img/w342$poster' : null,
          backdrop: (backdrop != null && backdrop.isNotEmpty) ? '$_img/w780$backdrop' : null,
          subtitle: role,
          catalogId: mediaId,
          isTv: isTv,
          releaseDate: releaseDate,
          rating: rating,
          popularity: pop,
        );
        works.add(work);

        if (backdrop != null && backdrop.isNotEmpty && providerVideos.length < 15) {
          providerVideos.add(work);
        }
      }
    }

    final knownDept = (person['known_for_department'] as String?)?.toLowerCase();
    if (knownDept == 'directing' || knownDept == 'writing' || knownDept == 'production' || knownDept == 'crew') {
      processCreditList(crewList, isCrew: true);
      processCreditList(castList, isCrew: false);
    } else {
      processCreditList(castList, isCrew: false);
      processCreditList(crewList, isCrew: true);
    }

    if (works.isNotEmpty) {
      // Fetch co-stars from top movie/series for the Related row
      try {
        final top = works.first;
        final topType = top.isTv ? 'tv' : 'movie';
        final topId = top.catalogId;
        if (topId != null) {
          final topCredits = await _get('$_tmdbBase/$topType/$topId/credits');
          final topCast = topCredits?['cast'];
          if (topCast is List) {
            for (final personRow in topCast.whereType<Map>()) {
              final pId = (personRow['id'] as num?)?.toInt();
              final pName = personRow['name'] as String?;
              final pPic = personRow['profile_path'] as String?;
              if (pId != null && pId != personId && pName != null && pName.isNotEmpty) {
                related.add(PersonRef(
                  id: pId,
                  source: PersonSource.tmdb,
                  name: pName,
                  photo: (pPic != null && pPic.isNotEmpty) ? '$_img/w185$pPic' : null,
                ));
                if (related.length >= 12) break;
              }
            }
          }
        }
      } catch (_) {}
    }
    _tmdbCreditsCache[personId] = works;
    if (id > 0) _tmdbCreditsCache[id] = works;
    final profile = person['profile_path'] as String?;
    return PersonProfile(
      name: name,
      photo: (profile != null && profile.isNotEmpty) ? '$_img/w780$profile' : null,
      description: (person['biography'] as String?)?.trim().isEmpty ?? true
          ? null
          : (person['biography'] as String).trim(),
      subtitle: person['known_for_department'] as String?,
      works: works,
      providerVideos: providerVideos,
      related: related,
    );
  }

  Future<Map<String, dynamic>?> _get(String url) async {
    try {
      final res = await _dio.get<dynamic>(
        url,
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
    } catch (_) {}
    return null;
  }

  // ── Text helpers ────────────────────────────────────────────────────────────

  static String? _titleCase(String? s) {
    if (s == null || s.isEmpty) return null;
    final t = s.replaceAll('_', ' ').toLowerCase();
    return t[0].toUpperCase() + t.substring(1);
  }

  /// Strip AniList's light HTML/markdown so the bio renders as plain text.
  static String? _plain(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    var out = s
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'~!|!~'), '') // AniList spoiler markers
        .replaceAll('__', '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return out.isEmpty ? null : out;
  }
}
