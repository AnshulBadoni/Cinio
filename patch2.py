from pathlib import Path
p=Path('.')
# HomeCubit mixed
f=p/'lib/features/home/cubit/home_cubit.dart'; s=f.read_text(); a=s.index('  Future<List<HomeSection>> _mixedHome() async {'); b=s.index('\n  String _mixedTitle',a)
new='''  Future<List<HomeSection>> _mixedHome() async {\n    final results = await Future.wait([_tmdb!.home(), _tpdb!.home()]);\n    final tmdb = results[0];\n    final tpdb = results[1];\n    final tpdbRecent = tpdb.firstWhere((s) => s.title == 'Trending', orElse: () => const HomeSection(title: '', items: []));\n    final tpdbPopular = tpdb.firstWhere((s) => s.title == 'Popular', orElse: () => const HomeSection(title: '', items: []));\n    final tpdbTop = tpdb.firstWhere((s) => s.title == 'Top Rated', orElse: () => const HomeSection(title: '', items: []));\n    List<MediaItem> adult(String name) => switch (name) {\n      'Recent Movies & Series' || 'Trending Movies' => tpdbRecent.items,\n      'Popular Movies' => tpdbPopular.items,\n      'Top Rated Movies' => tpdbTop.items,\n      _ => const <MediaItem>[],\n    };\n    final out = <HomeSection>[];\n    for (final section in tmdb) {\n      final extra = adult(section.title);\n      out.add(HomeSection(\n        title: section.title,\n        items: _interleave([...section.items, ...extra]),\n        more: BrowseMore(sourceId: 'mixed:catalog', kind: 'mixed_${_mixedKind(section.title)}'),\n      ));\n    }\n    return out.where((s) => s.items.isNotEmpty).toList();\n  }\n\n  String _mixedKind(String title) => switch (title) {\n    'Recent Movies & Series' => 'recent',\n    'Trending Movies' => 'trending_movies',\n    'Trending Series' => 'trending_series',\n    'Popular Movies' => 'popular_movies',\n    'Popular Series' => 'popular_series',\n    'Trending Anime' => 'trending_anime',\n    'Top Rated Movies' => 'top_rated_movies',\n    _ => 'recent',\n  };\n'''
s=s[:a]+new+s[b:]
# _interleave currently source filtering may omit unknown? inspect and replace with robust alternation
start=s.index('  List<MediaItem> _interleave(List<MediaItem> items) {'); end=s.index('\n  }', start)+4
old=s[start:end]
new2='''  List<MediaItem> _interleave(List<MediaItem> items) {\n    final tmdb = items.where((item) => item.sourceId == 'tmdb:catalog').toList();\n    final tpdb = items.where((item) => item.sourceId.startsWith('tpdb:')).toList();\n    final out = <MediaItem>[];\n    var i = 0, j = 0;\n    while (i < tmdb.length || j < tpdb.length) {\n      if (i < tmdb.length) out.add(tmdb[i++]);\n      if (j < tpdb.length) out.add(tpdb[j++]);\n    }\n    return out;\n  }\n'''
s=s[:start]+new2+s[end:]
f.write_text(s)

# repository mixed browse
f=p/'lib/core/repository/source_repository.dart'; s=f.read_text()
needle="""        case 'tmdb_top_rated_movies':\n          return sl<TmdbDiscoverService>().browseMore(more.kind, page);\n"""
rep=needle+'''        case 'mixed_recent':\n          return _mixedBrowse('tmdb_recent', 'tpdb_trending', page);\n        case 'mixed_trending_movies':\n          return _mixedBrowse('tmdb_trending_movies', 'tpdb_trending', page);\n        case 'mixed_trending_series':\n          return _mixedBrowse('tmdb_trending_series', 'tpdb_trending', page);\n        case 'mixed_popular_movies':\n          return _mixedBrowse('tmdb_popular_movies', 'tpdb_popular', page);\n        case 'mixed_popular_series':\n          return _mixedBrowse('tmdb_popular_series', 'tpdb_popular', page);\n        case 'mixed_trending_anime':\n          return sl<TmdbDiscoverService>().browseMore('tmdb_trending_anime', page);\n        case 'mixed_top_rated_movies':\n          return _mixedBrowse('tmdb_top_rated_movies', 'tpdb_top_rated', page);\n'''
s=s.replace(needle,rep)
idx=s.index('  Future<List<MediaItem>> search(')
method='''  Future<List<MediaItem>> _mixedBrowse(String tmdbKind, String tpdbKind, int page) async {\n    final results = await Future.wait([\n      sl<TmdbDiscoverService>().browseMore(tmdbKind, page),\n      _tpdb?.browseMore(tpdbKind, page) ?? Future.value(const <MediaItem>[]),\n    ]);\n    final out = <MediaItem>[];\n    final tmdb = results[0];\n    final tpdb = results[1];\n    var i = 0, j = 0;\n    while (i < tmdb.length || j < tpdb.length) {\n      if (i < tmdb.length) out.add(tmdb[i++]);\n      if (j < tpdb.length) out.add(tpdb[j++]);\n    }\n    return out;\n  }\n\n'''
s=s[:idx]+method+s[idx:]
f.write_text(s)

# home imports and performer flow
f=p/'lib/features/home/home_screen.dart'; s=f.read_text()
if "../../core/metadata/tmdb_discover_service.dart" not in s: s=s.replace("import '../../core/models/provider_info.dart';", "import '../../core/models/provider_info.dart';\nimport '../../core/metadata/tmdb_discover_service.dart';\nimport '../../core/metadata/theporndb.dart';")
old="""          onTap: (item) {\n            if (item.sourceId == 'tpdb:performer' || item.sourceId == 'tpdb:studio') {\n              launchUrl(Uri.parse(item.url), mode: LaunchMode.externalApplication);\n            } else {\n              _openDetail(item, trailerContext: DetailTrailerContext.model);\n            }\n          },"""
new="""          onTap: (item) {\n            if (item.sourceId == 'tpdb:performer') {\n              _openPerformer(item);\n            } else if (item.sourceId == 'tpdb:studio') {\n              launchUrl(Uri.parse(item.url), mode: LaunchMode.externalApplication);\n            } else {\n              _openDetail(item, trailerContext: DetailTrailerContext.model);\n            }\n          },"""
s=s.replace(old,new)
# insert performer method before _sectionRow
idx=s.index('  Widget _sectionRow(HomeSection section) {')
method='''  Future<void> _openPerformer(MediaItem performer) async {\n    _snack('Finding videos for ${performer.title}…');\n    final results = await _repo.searchAll(performer.title);\n    if (!mounted) return;\n    if (results.isEmpty) { _snack('No provider videos found for ${performer.title}'); return; }\n    Navigator.push(context, MaterialPageRoute(builder: (_) => SeeAllScreen(\n      title: performer.title, items: results, onTap: _openDetail, onLongPress: _showInfo,\n    )));\n  }\n\n'''
s=s[:idx]+method+s[idx:]
f.write_text(s)

# detail imports and catalog playback helper modifications
f=p/'lib/features/detail/detail_screen.dart'; s=f.read_text()
if "../../core/metadata/tmdb_discover_service.dart" not in s: s=s.replace("import '../../core/metadata/metadata_enrichment.dart';", "import '../../core/metadata/metadata_enrichment.dart';\nimport '../../core/metadata/tmdb_discover_service.dart';\nimport '../../core/metadata/theporndb.dart';")
# Add helper before _openPlayer
idx=s.index('  Future<void> _openPlayer(\n')
helper='''  Future<({MediaItem item, MediaDetail detail})?> _resolveCatalogPlayback() async {\n    final catalog = widget.item;\n    if (catalog.sourceId != 'tmdb:catalog' && !catalog.sourceId.startsWith('tpdb:')) return null;\n    var results = await sl<SourceRepository>().searchAll(catalog.title);\n    if (results.isEmpty) {\n      results = await sl<SourceRepository>().searchAll(catalog.title, category: 'dub');\n    }\n    final match = bestTitleMatch(results, catalog.title, altTitle: catalog.englishTitle);\n    if (match == null) return null;\n    try {\n      final d = await sl<SourceRepository>().detail(match.url, sourceId: match.sourceId);\n      return (item: match, detail: d);\n    } catch (_) {\n      return null;\n    }\n  }\n\n'''
s=s[:idx]+helper+s[idx:]
# inject at beginning openPlayer after signature closing before comment; locate exact first comment after signature
needle="""  }) async {\n    // Opening something other than where they left off?"""
replacement="""  }) async {\n    if (widget.item.sourceId == 'tmdb:catalog' || widget.item.sourceId.startsWith('tpdb:')) {\n      final resolved = await _resolveCatalogPlayback();\n      if (!mounted) return;\n      if (resolved == null) { _snack('No playable provider result found for ${widget.item.title}'); return; }\n      detail = resolved.detail;\n      episodes = detail.episodes;\n      if (episodes.isEmpty) { _snack('No playable episodes found for ${widget.item.title}'); return; }\n    }\n    // Opening something other than where they left off?"""
s=s.replace(needle,replacement,1)
# Replace widget source refs inside _openPlayer only
start=s.index('  Future<void> _openPlayer('); end=s.index('  /// Routes a reading-type title', start)
seg=s[start:end]
seg=seg.replace('widget.item.sourceId','(detail.sourceId)').replace('widget.item.url','(detail.url)').replace('widget.item.type','(detail.type)').replace('widget.item.malId','(detail.malId)')
# Avoid weird `detail.sourceId` okay. But prefs use source/url now provider detail.
s=s[:start]+seg+s[end:]
# download sheet resolve catalog before total
needle="""  }) async {\n    final total = episodesBySeason.values.fold<int>(0, (a, b) => a + b.length);"""
rep="""  }) async {\n    if (widget.item.sourceId == 'tmdb:catalog' || widget.item.sourceId.startsWith('tpdb:')) {\n      final resolved = await _resolveCatalogPlayback();\n      if (!mounted) return;\n      if (resolved == null) { _snack('No downloadable provider result found for ${widget.item.title}'); return; }\n      detail = resolved.detail;\n      episodesBySeason = <int, List<Episode>>{};\n      for (final e in detail.episodes) { (episodesBySeason[seasonOf(e) ?? 1] ??= <Episode>[]).add(e); }\n      if (episodesBySeason.isEmpty) { _snack('No downloadable episodes found for ${widget.item.title}'); return; }\n    }\n    final total = episodesBySeason.values.fold<int>(0, (a, b) => a + b.length);"""
s=s.replace(needle,rep,1)
# pick source download resolve provider at start
needle="""  }) async {\n    final item = widget.item;\n    final res ="""
# only first occurrence after _pickSourceAndDownload by using segment
start=s.index('  Future<void> _pickSourceAndDownload('); end=s.index('  void _startDownload(',start); seg=s[start:end]
seg=seg.replace(needle,"""  }) async {\n    var item = widget.item;\n    if (item.sourceId == 'tmdb:catalog' || item.sourceId.startsWith('tpdb:')) {\n      final resolved = await _resolveCatalogPlayback();\n      if (!mounted) return;\n      if (resolved == null) { _snack('No downloadable provider result found for ${item.title}'); return; }\n      item = resolved.item;\n      detail = resolved.detail;\n      if (detail.episodes.isNotEmpty) ep = detail.episodes.first;\n    }\n    final res =""",1)
s=s[:start]+seg+s[end:]
f.write_text(s)
