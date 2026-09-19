import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/platform/apple_tv.dart';
import '../../../core/error/exceptions.dart';
import '../../../core/lnreader/novel_cloudflare.dart';
import '../../../core/models/home_section.dart';
import '../../../core/models/media_item.dart';
import '../../../core/metadata/theporndb.dart';
import '../../../core/metadata/tmdb_discover_service.dart';
import '../../../core/prefs/catalog_source_prefs.dart';
import '../../../core/repository/source_repository.dart';

/// Immutable view-state for the Home screen. Rows are catalog-source-driven:
/// Provider uses the active provider, while TMDB/ThePornDB/Mixed use their
/// catalog services and still resolve playback through a provider later.
///
/// A null [sections] means "not yet loaded OR failed". The first section also
/// feeds the hero carousel via [heroItems]; the screen renders the remaining
/// sections as browse rows.
class HomeState extends Equatable {
  const HomeState({this.sections, this.loading = false, this.cloudflareUrl});

  /// The provider's named home rows, in order. Null until the first load.
  final List<HomeSection>? sections;

  /// True while the rows are being (re)fetched.
  final bool loading;

  /// Set when the active (Mihon) source is blocked by a Cloudflare challenge the
  /// headless solver couldn't pass — the URL to open in the visible WebView
  /// solve. Null in every other state. Drives the "Solve Cloudflare" empty view.
  final String? cloudflareUrl;

  /// Items that drive the hero carousel — the first section's items. Empty
  /// until something loads.
  List<MediaItem> get heroItems => (sections != null && sections!.isNotEmpty)
      ? sections!.first.items
      : const [];

  HomeState copyWith({
    List<HomeSection>? sections,
    bool? loading,
    String? cloudflareUrl,
  }) => HomeState(
    sections: sections ?? this.sections,
    loading: loading ?? this.loading,
    cloudflareUrl: cloudflareUrl ?? this.cloudflareUrl,
  );

  @override
  List<Object?> get props => [sections, loading, cloudflareUrl];
}

/// Owns the Home rows and switches between Provider, TMDB, ThePornDB and Mixed
/// catalog sources without changing the existing provider playback pipeline.
class HomeCubit extends Cubit<HomeState> {
  HomeCubit(
    this._repo, [
    CatalogSourcePrefs? catalogPrefs,
    ThePornDb? tpdb,
    TmdbDiscoverService? tmdb,
  ]) : _catalogPrefs = catalogPrefs,
       _tpdb = tpdb,
       _tmdb = tmdb,
       super(const HomeState());

  final SourceRepository _repo;

  // Optional for lightweight provider-only tests; production DI supplies all
  // catalog services. When omitted, Home defaults to Provider mode.
  final CatalogSourcePrefs? _catalogPrefs;
  final ThePornDb? _tpdb;
  final TmdbDiscoverService? _tmdb;

  CatalogSource get _catalogSource =>
      _catalogPrefs?.source ??
      (_tmdb != null ? CatalogSource.tmdb : CatalogSource.provider);

  /// Monotonic load id. Each [load] bumps it; a fetch only emits its result if
  /// it's still the latest. This makes source switches "latest wins" — a slow
  /// previous-source fetch can't land after a newer switch and clobber the UI.
  int _gen = 0;

  /// In-memory cache for catalog sections (5-minute TTL) to prevent empty rows
  /// and avoid spamming TMDB/TPDB with concurrent network bursts.
  static final Map<CatalogSource, (DateTime, List<HomeSection>)> _catalogCache = {};

  /// (Re)load the rows. Emits `loading: true` (keeping any existing sections so
  /// rows don't flash empty), fetches the provider's home, and emits the fresh
  /// result. A total failure yields an empty section list rather than throwing.
  /// [reset] clears the current rows first (used on a source switch) so the UI
  /// shows loading skeletons for the NEW source instead of lingering on the old
  /// source's content while the (possibly slow) fetch runs.
  Future<void> load({bool reset = false}) async {
    final gen = ++_gen;
    final sourceId = _repo.sourceId;
    final source = _catalogSource;

    if (reset) {
      _catalogCache.remove(source);
      emit(const HomeState(loading: true));
    } else {
      // Check cache first for instant load without network flash
      final cached = _catalogCache[source];
      if (cached != null &&
          DateTime.now().difference(cached.$1).inMinutes < 5 &&
          cached.$2.isNotEmpty) {
        emit(HomeState(sections: cached.$2, loading: false));
        return;
      }
      emit(state.copyWith(loading: true));
    }

    if (source == CatalogSource.provider && sourceId.isEmpty) {
      if (isClosed || gen != _gen) return;
      emit(const HomeState(sections: [], loading: false));
      return;
    }

    List<HomeSection> sections;
    String? cloudflareUrl;
    try {
      if (source == CatalogSource.tmdb ||
          source == CatalogSource.thePornDb ||
          source == CatalogSource.mixed) {
        sections = await _loadCatalogProgressively(source, gen);
      } else {
        final homeFuture = _repo.home();
        sections = isAppleTv
            ? await homeFuture.timeout(const Duration(seconds: 20))
            : await homeFuture;
      }
    } on TimeoutException catch (_) {
      debugPrint('[home] load timed out · source=$sourceId');
      sections = const <HomeSection>[];
    } on CloudflareRequiredException catch (e) {
      debugPrint('[home] load needs Cloudflare · source=$sourceId');
      sections = const <HomeSection>[];
      cloudflareUrl = e.url;
    } catch (e, st) {
      debugPrint('[home] load failed · source=$sourceId · $e\n$st');
      sections = const <HomeSection>[];
    }

    // A novel plugin catches its own fetch errors and returns nothing, so a
    // Cloudflare challenge arrives as an empty list rather than an exception.
    // Pick it up from the latch so the solve prompt still appears. Only when
    // there is genuinely nothing to show, so a source that partly worked is
    // never interrupted.
    if (cloudflareUrl == null && sections.isEmpty) {
      cloudflareUrl = NovelCloudflare.pendingUrl;
    }
    if (sections.isNotEmpty) NovelCloudflare.clear();

    // A newer load started while we were fetching — discard this stale result.
    if (isClosed || gen != _gen) return;
    emit(
      HomeState(
        sections: sections,
        loading: false,
        cloudflareUrl: cloudflareUrl,
      ),
    );
  }

  Future<List<HomeSection>> _loadCatalogProgressively(
    CatalogSource source,
    int gen,
  ) async {
    final kinds = source == CatalogSource.thePornDb
        ? const [
            'tpdb_recent',
            'tpdb_trending',
            'tpdb_performers',
            'tpdb_popular',
            'tpdb_top_rated',
          ]
        : source == CatalogSource.mixed
            ? const [
                'mixed_recent',
                'tmdb_new_releases',
                'mixed_trending_movies',
                'tmdb_trending_series',
                'mixed_popular_movies',
                'tmdb_popular_series',
                'tmdb_trending_anime',
                'mixed_top_rated_movies',
                'tmdb_top_rated_series',
                'tpdb_performers',
              ]
            : const [
                'tmdb_recent',
                'tmdb_new_releases',
                'tmdb_trending_movies',
                'tmdb_trending_series',
                'tmdb_popular_movies',
                'tmdb_popular_series',
                'tmdb_trending_anime',
                'tmdb_top_rated_movies',
                'tmdb_top_rated_series',
              ];
    final byKind = <String, HomeSection>{};

    Future<HomeSection?> fetch(String kind) async {
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          if (source == CatalogSource.thePornDb) {
            final section = await _tpdb!.homeSection(kind);
            if (section != null && section.items.isNotEmpty) return section;
          } else if (source == CatalogSource.mixed) {
            if (kind.startsWith('mixed_')) {
              final tmdbKind = kind.replaceFirst('mixed_', 'tmdb_');
              final tpdbKind = switch (kind) {
                'mixed_recent' => 'tpdb_recent',
                'mixed_trending_movies' => 'tpdb_trending',
                'mixed_popular_movies' => 'tpdb_popular',
                'mixed_top_rated_movies' => 'tpdb_top_rated',
                _ => 'tpdb_recent',
              };
              final tpdb = _tpdb;
              final results = await Future.wait([
                _tmdb!.homeSection(tmdbKind),
                tpdb != null ? tpdb.homeSection(tpdbKind) : Future.value(null),
              ]);
              final tmdbSec = results[0];
              final tpdbSec = results[1];
              if (tmdbSec == null && tpdbSec == null) return null;
              final tmdbItems = tmdbSec?.items ?? const <MediaItem>[];
              final tpdbItems = tpdbSec?.items ?? const <MediaItem>[];
              final merged = _interleave([...tmdbItems, ...tpdbItems]);
              if (merged.isEmpty) return null;
              return HomeSection(
                title: tmdbSec?.title ?? tpdbSec?.title ?? 'Recent',
                items: merged,
                more: BrowseMore(sourceId: 'mixed:catalog', kind: kind),
              );
            } else if (kind.startsWith('tpdb_')) {
              final tpdb = _tpdb;
              if (tpdb == null) return null;
              final section = await tpdb.homeSection(kind);
              if (section != null && section.items.isNotEmpty) return section;
            } else {
              final section = await _tmdb!.homeSection(kind);
              if (section != null && section.items.isNotEmpty) return section;
            }
          } else {
            final section = await _tmdb!.homeSection(kind);
            if (section != null && section.items.isNotEmpty) return section;
          }
        } catch (e) {
          if (attempt == 2) {
            debugPrint('[home] failed to load section $kind after 3 attempts: $e');
            return null;
          }
          await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
        }
      }
      return null;
    }

    final futures = <Future<void>>[];
    for (final kind in kinds) {
      futures.add(fetch(kind).then((section) {
        if (section == null || isClosed || gen != _gen) return;
        byKind[kind] = section;
        final ordered = [for (final k in kinds) if (byKind.containsKey(k)) byKind[k]!];
        emit(state.copyWith(sections: ordered, loading: true));
      }));
    }
    await Future.wait(futures);
    final finalOrdered = [for (final k in kinds) if (byKind.containsKey(k)) byKind[k]!];
    if (finalOrdered.isNotEmpty) {
      _catalogCache[source] = (DateTime.now(), finalOrdered);
    }
    return finalOrdered;
  }

  List<MediaItem> _interleave(List<MediaItem> items) {
    final tmdb = items.where((item) => item.sourceId == 'tmdb:catalog').toList();
    final tpdb = items.where((item) => item.sourceId.startsWith('tpdb:')).toList();
    final out = <MediaItem>[];
    var i = 0, j = 0;
    while (i < tmdb.length || j < tpdb.length) {
      if (i < tmdb.length) out.add(tmdb[i++]);
      if (j < tpdb.length) out.add(tpdb[j++]);
    }
    return out;
  }

}
