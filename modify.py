from pathlib import Path
p=Path('/mnt/data/work/current')

# prefs default
f=p/'lib/core/prefs/catalog_source_prefs.dart'; s=f.read_text(); s=s.replace("defaultValue: CatalogSource.provider.name", "defaultValue: CatalogSource.tmdb.name"); s=s.replace("orElse: () => CatalogSource.provider,", "orElse: () => CatalogSource.tmdb,"); f.write_text(s)

# HomeCubit fallback default
f=p/'lib/features/home/cubit/home_cubit.dart'; s=f.read_text().replace("_catalogPrefs?.source ?? CatalogSource.provider", "_catalogPrefs?.source ?? CatalogSource.tmdb"); f.write_text(s)

# HomeSection docs broaden
f=p/'lib/core/models/home_section.dart'; s=f.read_text().replace("final String? categoryId;", "final String? categoryId;"); f.write_text(s)

# TMDB service replace home + trending and add detail/browse
f=p/'lib/core/metadata/tmdb_discover_service.dart'; s=f.read_text()
start=s.index('  Future<List<HomeSection>> home() async {')
end=s.index('\n  Future<List<MediaItem>> discover({', start)
new='''  Future<List<HomeSection>> home() async {\n    final results = await Future.wait([\n      _recentMixed(1),\n      _trendingKind('movie', 1),\n      _trendingKind('tv', 1),\n      _discoverKind(kind: 'movie', catalog: 'popular', page: 1),\n      _discoverKind(kind: 'tv', catalog: 'popular', page: 1),\n      _discoverKind(kind: 'tv', catalog: 'anime', page: 1, anime: true),\n      _discoverKind(kind: 'movie', catalog: 'top_rated', page: 1),\n    ]);\n    final kinds = <String>[\n      'tmdb_recent', 'tmdb_trending_movies', 'tmdb_trending_series',\n      'tmdb_popular_movies', 'tmdb_popular_series', 'tmdb_trending_anime',\n      'tmdb_top_rated_movies',\n    ];\n    final titles = <String>[\n      'Recent Movies & Series', 'Trending Movies', 'Trending Series',\n      'Popular Movies', 'Popular Series', 'Trending Anime', 'Top Rated Movies',\n    ];\n    return [\n      for (var i = 0; i < results.length; i++)\n        if (results[i].isNotEmpty) HomeSection(\n          title: titles[i], items: results[i],\n          more: BrowseMore(sourceId: 'tmdb:catalog', kind: kinds[i]),\n        ),\n    ];\n  }\n\n  Future<List<MediaItem>> browseMore(String kind, int page) async {\n    switch (kind) {\n      case 'tmdb_recent': return _recentMixed(page);\n      case 'tmdb_trending_movies': return _trendingKind('movie', page);\n      case 'tmdb_trending_series': return _trendingKind('tv', page);\n      case 'tmdb_popular_movies': return _discoverKind(kind: 'movie', catalog: 'popular', page: page);\n      case 'tmdb_popular_series': return _discoverKind(kind: 'tv', catalog: 'popular', page: page);\n      case 'tmdb_trending_anime': return _discoverKind(kind: 'tv', catalog: 'anime', page: page, anime: true);\n      case 'tmdb_top_rated_movies': return _discoverKind(kind: 'movie', catalog: 'top_rated', page: page);\n      default: return const [];\n    }\n  }\n\n  Future<List<MediaItem>> _trendingKind(String kind, int page) async {\n    final response = await _dio.get<dynamic>('${Tmdb.base}/trending/$kind/week', queryParameters: {'page': page});\n    final rows = response.data is Map ? response.data['results'] : null;\n    if (rows is! List) return const [];\n    return [for (final row in rows) if (row is Map) ..._mapSearchRow(row, type: kind == 'tv' ? 'series' : 'movies', trending: true)];\n  }\n\n  Future<List<MediaItem>> _recentMixed(int page) async {\n    final movies = await _discoverKind(kind: 'movie', catalog: 'recent', page: page);\n    final series = await _discoverKind(kind: 'tv', catalog: 'recent', page: page);\n    final out = [...movies, ...series];\n    out.sort((a,b) => (b.year ?? '').compareTo(a.year ?? ''));\n    return out;\n  }\n\n  Future<MediaDetail> movieDetail(MediaItem item) async {\n    final id = item.tmdbId;\n    if (id == null) throw StateError('Missing TMDB id');\n    final kind = item.tmdbIsTv ? 'tv' : 'movie';\n    final response = await _dio.get<dynamic>('${Tmdb.base}/$kind/$id', queryParameters: {'append_to_response': 'credits'});\n    final row = response.data is Map ? Map<String,dynamic>.from(response.data as Map) : <String,dynamic>{};\n    final title = (item.tmdbIsTv ? row['name'] : row['title'])?.toString() ?? item.title;\n    final poster = row['poster_path']?.toString();\n    final overview = row['overview']?.toString();\n    final date = (item.tmdbIsTv ? row['first_air_date'] : row['release_date'])?.toString();\n    final castRows = row['credits'] is Map ? row['credits']['cast'] : null;\n    final cast = <String>[];\n    if (castRows is List) { for (final c in castRows) { if (c is Map && c['name'] != null) cast.add(c['name'].toString()); } }\n    final ep = Episode(id: 'tmdb:$kind:$id', title: title, number: 1, url: 'tmdb://$kind/$id');\n    return MediaDetail(\n      id: item.id, title: title, englishTitle: item.englishTitle,\n      cover: poster == null ? item.cover : '${Tmdb.img}/w500$poster',\n      url: item.url, description: overview, year: date != null && date.length >= 4 ? date.substring(0,4) : null,\n      type: ProviderType.movie, sourceId: 'tmdb:catalog', tmdbId: id, tmdbIsTv: item.tmdbIsTv,\n      isSeries: item.tmdbIsTv, genres: item.genres, cast: cast, episodes: [ep],\n    );\n  }\n'''
s=s[:start]+new+s[end:]
# imports
s=s.replace("import '../models/home_section.dart';", "import '../models/home_section.dart';\nimport '../models/media_detail.dart';\nimport '../models/episode.dart';")
# sort_by recent
s=s.replace("'top_rated' => 'vote_average.desc',\n        _ => 'popularity.desc',", "'top_rated' => 'vote_average.desc',\n        'recent' => kind == 'tv' ? 'first_air_date.desc' : 'primary_release_date.desc',\n        _ => 'popularity.desc',")
s=s.replace("if (catalog == 'top_rated') params['vote_count.gte'] = 200;", "if (catalog == 'top_rated') params['vote_count.gte'] = 200;\n    if (catalog == 'recent') params['vote_count.gte'] = 20;")
# add rating/year to mapper
needle="      genres: genreNames,\n    );"
rep="      genres: genreNames,\n      rating: (row['vote_average'] as num?)?.toDouble(),\n    );"
s=s.replace(needle,rep)
# Ensure discover supports MediaDetail imports done
f.write_text(s)

# TPDB service update home + detail + browse aliases
f=p/'lib/core/metadata/theporndb.dart'; s=f.read_text()
old="""    final results = await Future.wait([\n      movies(orderBy: 'recently_released'),\n      movies(orderBy: 'most_relevant'),\n      movies(orderBy: 'recently_released'),\n      performers(),\n      studios(),\n    ]);\n\n    final topRated = [...results[2]]\n      ..sort((a, b) => _rating(b).compareTo(_rating(a)));\n\n    return [\n      HomeSection(\n        title: 'Recent Movies',\n        items: results[0],\n        more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_recent'),\n      ),\n      HomeSection(\n        title: 'Actors',\n        items: results[3],\n        more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_performers'),\n      ),\n      HomeSection(\n        title: 'Popular',\n        items: results[1],\n        more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_popular'),\n      ),\n      HomeSection(\n        title: 'Studios',\n        items: results[4],\n        more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_studios'),\n      ),\n      HomeSection(\n        title: 'Top Rated',\n        items: topRated,\n        more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_top_rated'),\n      ),\n    ].where((section) => section.items.isNotEmpty).toList();"""
new="""    final results = await Future.wait([\n      performers(),\n      movies(orderBy: 'recently_released'),\n      movies(orderBy: 'most_relevant'),\n      _topRated(1),\n      studios(),\n    ]);\n    return [\n      HomeSection(title: 'Actors', items: results[0], more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_performers')),\n      HomeSection(title: 'Trending', items: results[1], more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_trending')),\n      HomeSection(title: 'Popular', items: results[2], more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_popular')),\n      HomeSection(title: 'Top Rated', items: results[3], more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_top_rated')),\n      HomeSection(title: 'Popular Studios', items: results[4], more: const BrowseMore(sourceId: 'tpdb:catalog', kind: 'tpdb_studios')),\n    ].where((section) => section.items.isNotEmpty).toList();"""
s=s.replace(old,new).replace("'tpdb_recent' => movies(page: page, orderBy: 'recently_released'),", "'tpdb_recent' => movies(page: page, orderBy: 'recently_released'),\n        'tpdb_trending' => movies(page: page, orderBy: 'recently_released'),")
# insert movieDetail before _topRated
idx=s.index('  Future<List<MediaItem>> _topRated')
method='''  Future<MediaDetail> movieDetail(MediaItem item) async {\n    final rawId = item.id.replaceFirst('tpdb:movie:', '');\n    final data = await _get('/movies/$rawId');\n    final row = data['data'] is Map ? Map<String,dynamic>.from(data['data'] as Map) : data;\n    final performers = row['performers'];\n    final cast = <String>[];\n    final members = <CastMember>[];\n    if (performers is List) {\n      for (final p in performers) {\n        if (p is! Map) continue;\n        final name = (p['name'] ?? p['full_name'])?.toString();\n        if (name == null || name.isEmpty) continue;\n        cast.add(name);\n        members.add(CastMember(name: name, role: null, image: (p['image'] ?? p['thumbnail'] ?? p['face'])?.toString()));\n      }\n    }\n    final title = (row['title'] ?? row['name'] ?? item.title).toString();\n    final ep = Episode(id: 'tpdb:movie:$rawId', title: title, number: 1, url: 'tpdb://movie/$rawId');\n    return MediaDetail(id: item.id, title: title, cover: item.cover, url: item.url, description: row['description']?.toString() ?? row['synopsis']?.toString(), type: ProviderType.movie, sourceId: 'tpdb:catalog', cast: cast, castMembers: members, episodes: [ep], rating: null);\n  }\n\n'''
# MediaDetail has no rating; remove accidental arg
method=method.replace(', rating: null','')
s=s[:idx]+method+s[idx:]
s=s.replace("import '../models/media_item.dart';", "import '../models/media_item.dart';\nimport '../models/media_detail.dart';\nimport '../models/episode.dart';\nimport '../models/media_extras.dart';")
f.write_text(s)

# Repository browse routing + searchAll
f=p/'lib/core/repository/source_repository.dart'; s=f.read_text()
s=s.replace("case 'tpdb_recent':", "case 'tmdb_recent':\n        case 'tmdb_trending_movies':\n        case 'tmdb_trending_series':\n        case 'tmdb_popular_movies':\n        case 'tmdb_popular_series':\n        case 'tmdb_trending_anime':\n        case 'tmdb_top_rated_movies':\n          return sl<TmdbDiscoverService>().browseMore(more.kind, page);\n        case 'tpdb_recent':")
s=s.replace("import '../metadata/theporndb.dart';", "import '../metadata/theporndb.dart';\nimport '../metadata/tmdb_discover_service.dart';")
needle="""  Future<List<MediaItem>> search(\n    String query, {\n    String category = 'sub',\n    String? sourceId,\n  }) => _providerFor(sourceId).search(query, 1, category: category);\n"""
replacement=needle+'''\n  /// Searches every currently available streaming provider. Catalog pages use\n  /// this only when the user explicitly requests playback/download.\n  Future<List<MediaItem>> searchAll(String query, {String category = 'sub'}) async {\n    final sources = loadedSources;\n    final results = await Future.wait([\n      for (final source in sources)\n        search(query, category: category, sourceId: source.id).catchError((_) => <MediaItem>[]),\n    ]);\n    return [for (final batch in results) ...batch];\n  }\n'''
s=s.replace(needle,replacement)
f.write_text(s)

# Home screen open catalog directly, no active provider dependency
f=p/'lib/features/home/home_screen.dart'; s=f.read_text()
start=s.index('  Future<MediaItem?> _resolveCatalogItem(MediaItem item) async {')
end=s.index('\n  Future<void> _openDetail(', start)
# keep _resolve for provider noncatalog; simplify
s=s[:start]+'''  Future<MediaItem?> _resolveCatalogItem(MediaItem item) async {\n    if (item.sourceId != 'tmdb:catalog' && !item.sourceId.startsWith('tpdb:')) return item;\n    return item;\n  }\n'''+s[end:]
old_start=s.index('  Future<void> _openDetail(', s.index('Future<MediaItem?> _resolveCatalogItem'))
old_end=s.index('\n  String _typeLabel', old_start)
new='''  Future<void> _openDetail(\n    MediaItem item, {\n    DetailTrailerContext? trailerContext,\n  }) async {\n    if (!mounted) return;\n    MediaDetail? catalogDetail;\n    if (item.sourceId == 'tmdb:catalog') {\n      try { catalogDetail = await sl<TmdbDiscoverService>().movieDetail(item); } catch (_) {}\n    } else if (item.sourceId == 'tpdb:catalog' && item.id.startsWith('tpdb:movie:')) {\n      try { catalogDetail = await sl<ThePornDb>().movieDetail(item); } catch (_) {}\n    }\n    if (!mounted) return;\n    await Navigator.push(context, DetailScreen.route(item, trailerContext: trailerContext, catalogDetail: catalogDetail));\n    if (mounted) setState(() {});\n  }\n'''
s=s[:old_start]+new+s[old_end:]
# SeeAll loader catalog services via repo already
f.write_text(s)

# Search screen direct catalog detail and use service
f=p/'lib/features/home/search_screen.dart'; s=f.read_text()
# replace resolve method with identity
start=s.index('  Future<MediaItem?> _resolveCatalogItem(MediaItem item) async {')
end=s.index('\n  Future<void> _play', start)
s=s[:start]+'''  Future<MediaItem?> _resolveCatalogItem(MediaItem item) async {\n    if (item.sourceId != 'tmdb:catalog' && !item.sourceId.startsWith('tpdb:')) return item;\n    return item;\n  }\n'''+s[end:]
# replace open detail method
start=s.index('  Future<void> _openDetail(MediaItem item) async {')
end=s.index('\n  /// Opens the full-grid', start)
new='''  Future<void> _openDetail(MediaItem item) async {\n    if (!mounted) return;\n    MediaDetail? catalogDetail;\n    if (item.sourceId == 'tmdb:catalog') {\n      try { catalogDetail = await sl<TmdbDiscoverService>().movieDetail(item); } catch (_) {}\n    } else if (item.sourceId == 'tpdb:catalog' && item.id.startsWith('tpdb:movie:')) {\n      try { catalogDetail = await sl<ThePornDb>().movieDetail(item); } catch (_) {}\n    }\n    if (!mounted) return;\n    Navigator.push(context, DetailScreen.route(item, catalogDetail: catalogDetail)).then((_) { if (mounted) setState(() {}); });\n  }\n'''
s=s[:start]+new+s[end:]
# imports services
if "core/metadata/tmdb_discover_service.dart" not in s: s=s.replace("import '../../core/models/provider_info.dart';", "import '../../core/models/provider_info.dart';\nimport '../../core/metadata/tmdb_discover_service.dart';\nimport '../../core/metadata/theporndb.dart';")
f.write_text(s)

# DetailCubit catalog fallback
f=p/'lib/features/detail/cubit/detail_cubit.dart'; s=f.read_text()
s=s.replace("import '../../../core/metadata/episode_metadata_service.dart';", "import '../../../core/metadata/episode_metadata_service.dart';\nimport '../../../core/metadata/tmdb_discover_service.dart';\nimport '../../../core/metadata/theporndb.dart';")
s=s.replace("    ProviderType? seedType,\n  })", "    ProviderType? seedType,\n    MediaDetail? catalogDetail,\n  })")
s=s.replace("       _prefs = prefs ?? sl<TitlePrefsStore>(),", "       _prefs = prefs ?? sl<TitlePrefsStore>(),\n       _catalogDetail = catalogDetail,")
s=s.replace("  final TitlePrefsStore _prefs;", "  final TitlePrefsStore _prefs;\n  final MediaDetail? _catalogDetail;")
old="""    try {\n      final detail = await _repo.detail(\n        _url,\n        category: state.category,\n        sourceId: _sourceId,\n      );\n      emit(state.copyWith(status: DetailStatus.success, detail: detail));\n      _enrich(detail);\n    } catch (_) {\n      emit(state.copyWith(status: DetailStatus.error, error: 'load_failed'));\n    }"""
new="""    try {\n      final detail = _catalogDetail ?? await _repo.detail(\n        _url, category: state.category, sourceId: _sourceId,\n      );\n      emit(state.copyWith(status: DetailStatus.success, detail: detail, cast: detail.castMembers));\n      if (_catalogDetail == null) _enrich(detail);\n    } catch (_) {\n      emit(state.copyWith(status: DetailStatus.error, error: 'load_failed'));\n    }"""
s=s.replace(old,new)
f.write_text(s)

# DetailScreen constructor + route + cubit wiring
f=p/'lib/features/detail/detail_screen.dart'; s=f.read_text()
s=s.replace("const DetailScreen({super.key, required this.item, this.trailerContext});", "const DetailScreen({super.key, required this.item, this.trailerContext, this.catalogDetail});")
s=s.replace("  final DetailTrailerContext? trailerContext;", "  final DetailTrailerContext? trailerContext;\n  final MediaDetail? catalogDetail;",1)
s=s.replace("    DetailTrailerContext? trailerContext,\n  })", "    DetailTrailerContext? trailerContext,\n    MediaDetail? catalogDetail,\n  })")
s=s.replace("        trailerContext: trailerContext,\n    ),", "        trailerContext: trailerContext,\n        catalogDetail: catalogDetail,\n    ),",1)
s=s.replace("        seedType: item.type,\n      )..load(),", "        seedType: item.type,\n        catalogDetail: catalogDetail,\n      )..load(),")
s=s.replace("        trailerContext: trailerContext,\n      ),", "        trailerContext: trailerContext,\n        catalogDetail: catalogDetail,\n      ),",1)
# _DetailView constructor/field
s=s.replace("const _DetailView({required this.item, this.trailerContext});", "const _DetailView({required this.item, this.trailerContext, this.catalogDetail});")
s=s.replace("  final DetailTrailerContext? trailerContext;", "  final DetailTrailerContext? trailerContext;\n  final MediaDetail? catalogDetail;",1)
f.write_text(s)

