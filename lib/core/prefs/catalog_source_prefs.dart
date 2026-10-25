import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/hive/safe_box.dart';

enum CatalogSource { provider, tmdb, thePornDb, mixed }

extension CatalogSourceLabel on CatalogSource {
  String get label => switch (this) {
        CatalogSource.provider => 'Provider',
        CatalogSource.tmdb => 'TMDB Only',
        CatalogSource.thePornDb => 'ThePornDB Only',
        CatalogSource.mixed => 'Mixed',
      };
}

class CatalogSourcePrefs extends ChangeNotifier {
  static const String boxName = 'catalog_source_prefs';
  static const String _key = 'source';

  static const List<String> defaultTmdbKinds = [
    'tmdb_recent',
    'tmdb_upcoming',
    'tmdb_new_releases',
    'tmdb_trending_movies',
    'tmdb_trending_series',
    'tmdb_popular_movies',
    'tmdb_popular_series',
    'tmdb_trending_anime',
    'tmdb_top_rated_movies',
    'tmdb_top_rated_series',
  ];

  static const List<String> defaultTpdbKinds = [
    'tpdb_recent',
    'tpdb_trending',
    'tpdb_performers',
    'tpdb_popular',
    'tpdb_top_rated',
    'tpdb_studios',
  ];

  static const List<String> defaultMixedKinds = [
    'mixed_recent',
    'tmdb_upcoming',
    'mixed_new_releases',
    'mixed_trending_movies',
    'tmdb_trending_series',
    'mixed_popular_movies',
    'tmdb_popular_series',
    'tmdb_trending_anime',
    'mixed_top_rated_movies',
    'tmdb_top_rated_series',
    'tpdb_performers',
  ];

  static List<String> defaultKindsFor(CatalogSource source) => switch (source) {
        CatalogSource.tmdb => defaultTmdbKinds,
        CatalogSource.thePornDb => defaultTpdbKinds,
        CatalogSource.mixed => defaultMixedKinds,
        CatalogSource.provider => const [],
      };

  static String sectionTitle(String kind) => switch (kind) {
        'tpdb_recent' => 'Recent',
        'tpdb_trending' => 'Trending',
        'tpdb_performers' => 'Actors',
        'tpdb_popular' => 'Popular',
        'tpdb_top_rated' => 'Top Rated',
        'tpdb_studios' => 'Studios',
        'tmdb_recent' => 'Recent Movies & Series',
        'tmdb_upcoming' => 'Upcoming Movies & Series',
        'tmdb_new_releases' => 'New Releases',
        'tmdb_trending_movies' => 'Trending Movies',
        'tmdb_trending_series' => 'Trending Series',
        'tmdb_popular_movies' => 'Popular Movies',
        'tmdb_popular_series' => 'Popular Series',
        'tmdb_trending_anime' => 'Trending Anime',
        'tmdb_top_rated_movies' => 'Top Rated Movies',
        'tmdb_top_rated_series' => 'Top Rated Series',
        'mixed_recent' => 'Recent',
        'mixed_new_releases' => 'New Releases',
        'mixed_trending_movies' => 'Trending Movies',
        'mixed_popular_movies' => 'Popular Movies',
        'mixed_top_rated_movies' => 'Top Rated Movies',
        _ => kind,
      };

  static Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) await openBoxSafely(boxName);
  }

  Box get _box => Hive.box(boxName);

  CatalogSource get source {
    final raw = _box.get(_key, defaultValue: CatalogSource.tmdb.name);
    return CatalogSource.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => CatalogSource.tmdb,
    );
  }

  Future<void> setSource(CatalogSource value) async {
    await _box.put(_key, value.name);
    notifyListeners();
  }

  List<String> getSectionOrder(CatalogSource source) {
    final defaults = defaultKindsFor(source);
    if (defaults.isEmpty) return const [];
    final saved = _box.get('order_${source.name}');
    if (saved is List) {
      final list = saved.map((e) => e.toString()).where(defaults.contains).toList();
      for (final d in defaults) {
        if (!list.contains(d)) list.add(d);
      }
      return list;
    }
    return List<String>.from(defaults);
  }

  Future<void> setSectionOrder(CatalogSource source, List<String> order) async {
    await _box.put('order_${source.name}', order);
    notifyListeners();
  }

  Future<void> resetSectionOrder(CatalogSource source) async {
    await _box.delete('order_${source.name}');
    notifyListeners();
  }

  static const String _tpdbFilterKey = 'tpdb_filter_old_and_gay';

  bool get tpdbFilterOldAndGay =>
      _box.get(_tpdbFilterKey, defaultValue: true) as bool;

  Future<void> setTpdbFilterOldAndGay(bool value) async {
    await _box.put(_tpdbFilterKey, value);
    notifyListeners();
  }

  static const String _hideProviderSwitcherKey = 'hide_provider_switcher';

  bool get hideProviderSwitcher =>
      _box.get(_hideProviderSwitcherKey, defaultValue: false) as bool;

  Future<void> setHideProviderSwitcher(bool value) async {
    await _box.put(_hideProviderSwitcherKey, value);
    notifyListeners();
  }
}
