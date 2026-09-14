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
      _catalogPrefs?.source ?? CatalogSource.provider;

  /// Monotonic load id. Each [load] bumps it; a fetch only emits its result if
  /// it's still the latest. This makes source switches "latest wins" — a slow
  /// previous-source fetch can't land after a newer switch and clobber the UI.
  int _gen = 0;

  /// (Re)load the rows. Emits `loading: true` (keeping any existing sections so
  /// rows don't flash empty), fetches the provider's home, and emits the fresh
  /// result. A total failure yields an empty section list rather than throwing.
  /// [reset] clears the current rows first (used on a source switch) so the UI
  /// shows loading skeletons for the NEW source instead of lingering on the old
  /// source's content while the (possibly slow) fetch runs.
  Future<void> load({bool reset = false}) async {
    final gen = ++_gen;
    final sourceId = _repo.sourceId;
    emit(
      reset ? const HomeState(loading: true) : state.copyWith(loading: true),
    );

    // An empty active id means the user has not selected a provider yet.
    // Do not call the repository with an invalid source: that turns a normal
    // first-run setup state into a misleading generic load failure.
    if (_catalogSource == CatalogSource.provider && !_repo.hasSource(sourceId)) {
      if (isClosed || gen != _gen) return;
      emit(const HomeState(sections: [], loading: false));
      return;
    }

    List<HomeSection> sections;
    String? cloudflareUrl;
    try {
      final source = _catalogSource;
      final homeFuture = switch (source) {
        CatalogSource.provider => _repo.home(),
        CatalogSource.tmdb => _tmdb!.home(),
        CatalogSource.thePornDb => _tpdb!.home(),
        CatalogSource.mixed => _mixedHome(),
      };
      sections = isAppleTv
          ? await homeFuture.timeout(const Duration(seconds: 20))
          : await homeFuture;
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

  Future<List<HomeSection>> _mixedHome() async {
    final results = await Future.wait([_tmdb!.home(), _tpdb!.home()]);
    final tmdb = results[0];
    final tpdb = results[1];
    final byTitle = <String, List<MediaItem>>{};
    for (final section in [...tmdb, ...tpdb]) {
      byTitle.putIfAbsent(section.title.toLowerCase(), () => <MediaItem>[])
        .addAll(section.items);
    }
    return [
      for (final entry in byTitle.entries)
        if (entry.value.isNotEmpty)
          HomeSection(title: _mixedTitle(entry.key, tmdb, tpdb), items: _interleave(entry.value)),
    ];
  }

  String _mixedTitle(String key, List<HomeSection> tmdb, List<HomeSection> tpdb) {
    for (final section in [...tmdb, ...tpdb]) {
      if (section.title.toLowerCase() == key) return section.title;
    }
    return key;
  }

  List<MediaItem> _interleave(List<MediaItem> items) {
    final tmdb = items.where((item) => item.sourceId == 'tmdb:catalog').toList();
    final tpdb = items.where((item) => item.sourceId.startsWith('tpdb:')).toList();
    final out = <MediaItem>[];
    var i = 0;
    while (i < tmdb.length || i < tpdb.length) {
      if (i < tmdb.length) out.add(tmdb[i]);
      if (i < tpdb.length) out.add(tpdb[i]);
      i++;
    }
    return out;
  }
}
