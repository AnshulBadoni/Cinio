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

  Future<PersonProfile?> load(PersonRef ref) {
    switch (ref.source) {
      case PersonSource.anilistCharacter:
        return _character(ref.id);
      case PersonSource.anilistStaff:
        return _staff(ref.id);
      case PersonSource.tmdb:
        return _tmdbPerson(ref.id);
      case PersonSource.thePornDbPerformer:
        return _tpdbPerformer(ref.externalId ?? ref.id.toString(), fallbackName: ref.name);
    }
  }

  /// Loads additional works/movies for a person (e.g. for infinite scroll).
  Future<List<PersonWork>> loadWorks(PersonRef ref, {required int page}) async {
    switch (ref.source) {
      case PersonSource.thePornDbPerformer:
        final id = ref.externalId ?? (ref.id != 0 ? ref.id.toString() : null);
        if (id == null || id.isEmpty) return const [];
        return _tpdbPerformerWorks(id, page: page);
      case PersonSource.tmdb:
        final all = _tmdbCreditsCache[ref.id];
        if (all == null) return const [];
        final startIndex = (page - 1) * 30;
        if (startIndex >= all.length) return const [];
        final endIndex = (startIndex + 30 < all.length) ? startIndex + 30 : all.length;
        return all.sublist(startIndex, endIndex);
      case PersonSource.anilistCharacter:
      case PersonSource.anilistStaff:
        return const [];
    }
  }

  Future<List<PersonWork>> _tpdbPerformerWorks(String performerId, {required int page}) async {
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

      final works = await _tpdbPerformerWorks(resolvedId, page: 1);

      return PersonProfile(
        name: name,
        photo: (row['image'] ?? row['thumbnail'] ?? row['face'])?.toString(),
        description: (row['description'] ?? row['bio'])?.toString(),
        subtitle: 'Acting',
        works: works,
      );
    } catch (_) {
      return null;
    }
  }

  String? _tpdbImage(Map row) {
    for (final key in ['poster', 'poster_image', 'image', 'thumbnail']) {
      final v = row[key]?.toString();
      if (v != null && v.isNotEmpty) return v;
    }
    final posters = row['posters'];
    if (posters is Map) {
      for (final key in ['large', 'medium', 'small', 'full']) {
        final v = posters[key]?.toString();
        if (v != null && v.isNotEmpty) return v;
      }
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

  Future<PersonProfile?> _tmdbPerson(int id) async {
    final person = await _get('$_tmdbBase/person/$id');
    if (person == null) return null;
    final name = person['name'] as String?;
    if (name == null || name.isEmpty) return null;

    final works = <PersonWork>[];
    final credits = await _get('$_tmdbBase/person/$id/combined_credits');
    final castList = credits?['cast'];
    if (castList is List) {
      final seenIds = <String>{};
      final sorted = castList.whereType<Map>().toList()
        ..sort((a, b) =>
            ((b['popularity'] as num?) ?? 0).compareTo((a['popularity'] as num?) ?? 0));
      for (final c in sorted) {
        final title = (c['title'] ?? c['name']) as String?;
        if (title == null || title.isEmpty) continue;
        final poster = c['poster_path'] as String?;
        final mediaId = c['id']?.toString();
        final key = mediaId ?? title;
        if (!seenIds.add(key)) continue;
        works.add(PersonWork(
          title: title,
          cover: (poster != null && poster.isNotEmpty) ? '$_img/w342$poster' : null,
          subtitle: c['character'] as String?,
          catalogId: mediaId,
        ));
      }
    }
    _tmdbCreditsCache[id] = works;
    final profile = person['profile_path'] as String?;
    return PersonProfile(
      name: name,
      photo: (profile != null && profile.isNotEmpty) ? '$_img/w300$profile' : null,
      description: (person['biography'] as String?)?.trim().isEmpty ?? true
          ? null
          : (person['biography'] as String).trim(),
      subtitle: person['known_for_department'] as String?,
      works: works.take(30).toList(),
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
