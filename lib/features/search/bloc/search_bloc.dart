import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injector.dart';
import '../../../core/mode/content_mode.dart';
import '../../../core/mode/content_mode_cubit.dart';
import '../../../core/models/media_item.dart';
import '../../../core/playback/search_history.dart';
import '../../../core/playback/search_prefs.dart';
import '../../../core/playback/search_source_prefs.dart';
import '../../../core/playback/source_health_store.dart';
import '../../../core/metadata/theporndb.dart';
import '../../../core/prefs/catalog_source_prefs.dart';
import '../../../core/repository/source_repository.dart';
import '../../../core/search/title_suggestion_service.dart';
import '../../../core/metadata/tmdb_discover_service.dart';
import '../../../core/state/active_source_cubit.dart';
// sourceTypeOf lives with the source picker; search_screen.dart reaches for it
// the same way for its own mode narrowing.
import '../../../core/ui/source_switcher.dart';
import 'search_event.dart';
import 'search_state.dart';

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  SearchBloc({
    required SourceRepository repo,
    required SearchHistory history,
    SearchPrefs? prefs,
    TitleSuggestionService? suggestions,
  }) : _repo = repo,
       _history = history,
       _prefs = prefs ?? sl<SearchPrefs>(),
       _suggestions = suggestions ?? sl<TitleSuggestionService>(),
       super(_restoredState(prefs ?? sl<SearchPrefs>())) {
    on<SearchStarted>(_onStarted);
    on<SearchCatalogSourceChanged>(_onCatalogSourceChanged);
    on<SearchCatalogChanged>(_onCatalogChanged);
    on<SearchDiscoverTypeChanged>(_onDiscoverTypeChanged);
    on<SearchDiscoverRequested>(_onDiscoverRequested);
    on<SearchDiscoverMore>(_onDiscoverMore);
    on<SearchQueryChanged>(_onQueryChanged);
    on<SearchSuggestionsUpdated>(_onSuggestionsUpdated);
    on<SearchSortChanged>(_onSortChanged);
    on<SearchScopeChanged>(_onScopeChanged);
    on<SearchSourceFilterChanged>(_onSourceFilterChanged);
    on<SearchEcosystemChanged>(_onEcosystemChanged);
    on<SearchContentFilterChanged>(_onContentFilterChanged);
    on<SearchAudioFilterChanged>(_onAudioFilterChanged);
    on<SearchGenreFilterChanged>(_onGenreFilterChanged);
    on<SearchStatusFilterChanged>(_onStatusFilterChanged);
    on<SearchRunRequested>(_onRunRequested);
    on<SearchSubmitted>(_onSubmitted);
    on<SearchSourceFiltersApplied>(_onSourceFiltersApplied);
    on<SearchFilteredBrowseMore>(_onFilteredBrowseMore);
    on<SearchModeChanged>(_onModeChanged);
    on<SearchRetryRequested>(_onRetryRequested);
    // Results belong to the mode they were fetched in. The Search tab stays
    // alive in the nav shell, so without this a manga search was still on
    // screen after switching to Streaming — stale results from sources this
    // mode doesn't even search. Listening here rather than in the screen means
    // it also holds when the mode is changed from Home and Search is opened
    // afterwards.
    // Guarded: bloc tests construct SearchBloc with explicit deps and never
    // register the cubit, and subscribing unconditionally would blow up at
    // construction before such a test does anything. Production always has it.
    if (sl.isRegistered<ContentModeCubit>()) {
      _modeSub = sl<ContentModeCubit>().stream.listen((_) {
        add(const SearchModeChanged());
      });
    }
  }

  final SourceRepository _repo;
  final SearchHistory _history;
  final SearchPrefs _prefs;
  final TitleSuggestionService _suggestions;
  TmdbDiscoverService? get _tmdb =>
      sl.isRegistered<TmdbDiscoverService>() ? sl<TmdbDiscoverService>() : null;
  ThePornDb? get _tpdb =>
      sl.isRegistered<ThePornDb>() ? sl<ThePornDb>() : null;
  StreamSubscription<ContentMode>? _modeSub;

  /// Hard cap on one source's search.
  ///
  /// [SourceRepository.searchStatus] never throws and has no timeout of its
  /// own — it inherits whatever the underlying provider's HTTP client does, and
  /// a provider that hangs outright (a stuck native bridge, a Cloudflare WebView
  /// solve that never resolves) simply never answers. Its `respondedSources`
  /// entry is then never written and its skeleton stays on screen forever.
  ///
  /// Sized against Aniyomi/Mihon, which cap one call at `callTimeout(2 minutes)`
  /// on top of 30s connect/read (their `NetworkHelper`). This app never got that
  /// ceiling: the vendored `NetworkHelper` wraps CloudStream's `baseClient`,
  /// which is a bare `OkHttpClient()` — OkHttp's default `callTimeout` is 0, ie.
  /// none. `callTimeout` is set exactly once app-wide, on `downloadClient`. So
  /// nothing bounded a search at all, and a source that hung simply hung.
  ///
  /// 60s sits under their per-call ceiling while leaving a genuinely slow source
  /// room to answer — [SourceHealthStore.slowThreshold] already flags merely-slow
  /// at 4s, and a timeout never marks a source dead, so a source that trips this
  /// is queried in full again on the next search.
  static const Duration sourceTimeout = Duration(seconds: 60);

  /// What a capped-out search returns — shaped like a normal empty result so it
  /// flows through the same outcome handling as any other failure.
  static ({List<MediaItem> items, SourceOutcome outcome}) _timedOut() =>
      (items: const <MediaItem>[], outcome: SourceOutcome.timeout);

  /// [SourceRepository.loadedSources] narrowed to the active content mode, so an
  /// all-sources search only fans out over sources that mode can actually show —
  /// a manga search shouldn't query novel (or anime) sources, and vice versa.
  ///
  /// Mirrors `_modeSources` in `search_screen.dart`, which already narrows the
  /// source *list* the UI offers; without the same narrowing here the bloc
  /// searched everything regardless of mode, so the picker and the results
  /// disagreed.
  ///
  /// Every mode narrows, anime included. Anime used to short-circuit to the
  /// unfiltered list — harmless when the only sources were video ones, but once
  /// Mihon (`mihon:`) and LNReader (`lnr:`) became installable it meant an
  /// anime search quietly queried every manga and novel source too, and their
  /// results rendered as ordinary groups. Nothing is lost by filtering here:
  /// `ContentMode.anime.matchesProvider` accepts anime AND movie, and
  /// `sourceTypeOf` types `cs:`/`ani:`/untyped sources as anime, so the only
  /// sources this drops are the manga and novel ones.
  List<({String id, String name})> _modeSources() {
    final mode = sl<ContentModeCubit>().state;
    return filterSourcesForMode(
      {for (final s in _repo.loadedSources) s.id: s},
      mode,
      (s) => sourceTypeOf(s.id),
    ).values.toList();
  }

  /// Seeds the bloc with the user's remembered filter/sort choices so they
  /// persist across screen opens.
  static SearchState _restoredState(SearchPrefs prefs) {
    final content = SearchContentFilter.values.firstWhere(
      (f) => f.name == prefs.contentFilterName,
      orElse: () => SearchContentFilter.all,
    );
    final sort = SearchSort.values.firstWhere(
      (s) => s.name == prefs.sortName,
      orElse: () => SearchSort.bestMatch,
    );
    // Same fallback pattern migrates an old 'rating' sort name (the enum
    // value no longer exists) straight to bestMatch — nothing else needed.
    final audio = SearchAudioFilter.values.firstWhere(
      (f) => f.name == prefs.audioFilterName,
      orElse: () => SearchAudioFilter.any,
    );
    final statusFilter = SearchStatusFilter.values.firstWhere(
      (f) => f.name == prefs.statusFilterName,
      orElse: () => SearchStatusFilter.any,
    );
    final catalogSource = sl.isRegistered<CatalogSourcePrefs>()
        ? switch (sl<CatalogSourcePrefs>().source) {
            CatalogSource.provider => SearchCatalogSource.providers,
            CatalogSource.tmdb => SearchCatalogSource.tmdb,
            CatalogSource.thePornDb => SearchCatalogSource.thePornDb,
            CatalogSource.mixed => SearchCatalogSource.mixed,
          }
        : SearchCatalogSource.providers;
    return SearchState(
      catalogSource: catalogSource,
      contentFilter: content,
      sort: sort,
      audioFilter: audio,
      genreFilter: prefs.genre,
      statusFilter: statusFilter,
      currentSourceOnly: prefs.currentSourceOnly,
    );
  }

  /// Debounce for the LIGHTWEIGHT autocomplete only — never the heavy search.
  Timer? _suggestDebounce;

  /// Bumped per autocomplete fetch so a slow response can't overwrite a newer
  /// query's suggestions.
  int _suggestSeq = 0;

  /// The last query an actual search was run for. When the field text drifts
  /// away from this, we drop back to the suggestion view so typing after a
  /// completed search shows fresh suggestions instead of stale results.
  String _lastRunQuery = '';
  // Bumped on every _runSearch. A run only emits while it's still the latest —
  // so toggling scope (or any re-run) with the SAME query can't let the previous
  // run keep streaming its (e.g. all-sources) results over the new one.
  int _runGen = 0;

  // Bumped for every discovery refresh so an older TMDB/provider request
  // cannot overwrite a newer catalog selection with a stale success/error.
  int _discoverGen = 0;

  Future<void> _onStarted(
    SearchStarted event,
    Emitter<SearchState> emit,
  ) async {
    if (state.discoverItems.isNotEmpty || state.trending.isNotEmpty) return;
    add(const SearchDiscoverRequested());
  }

  void _onCatalogSourceChanged(
    SearchCatalogSourceChanged event,
    Emitter<SearchState> emit,
  ) {
    final nextSource = switch (event.source) {
      'providers' => SearchCatalogSource.providers,
      'theporndb' => SearchCatalogSource.thePornDb,
      'mixed' => SearchCatalogSource.mixed,
      _ => SearchCatalogSource.tmdb,
    };
    final prefsSource = switch (nextSource) {
      SearchCatalogSource.providers => CatalogSource.provider,
      SearchCatalogSource.tmdb => CatalogSource.tmdb,
      SearchCatalogSource.thePornDb => CatalogSource.thePornDb,
      SearchCatalogSource.mixed => CatalogSource.mixed,
    };
    unawaited(sl<CatalogSourcePrefs>().setSource(prefsSource));
    final providerFilter = switch (state.discoverType) {
      SearchDiscoverType.all => SearchContentFilter.all,
      SearchDiscoverType.anime => SearchContentFilter.anime,
      SearchDiscoverType.movies => SearchContentFilter.movies,
      SearchDiscoverType.series => SearchContentFilter.movies,
    };
    emit(state.copyWith(
      catalogSource: nextSource,
      contentFilter: nextSource == SearchCatalogSource.providers
          ? providerFilter
          : SearchContentFilter.all,
    ));
    if (state.query.trim().isEmpty) {
      add(const SearchDiscoverRequested());
    } else {
      add(const SearchSubmitted());
    }
  }

  void _onCatalogChanged(
    SearchCatalogChanged event,
    Emitter<SearchState> emit,
  ) {
    emit(state.copyWith(catalog: event.catalog));
    if (state.query.trim().isEmpty) {
      add(const SearchDiscoverRequested());
    } else {
      add(const SearchSubmitted());
    }
  }

  void _onDiscoverTypeChanged(
    SearchDiscoverTypeChanged event,
    Emitter<SearchState> emit,
  ) {
    final providerFilter = switch (event.type) {
      SearchDiscoverType.all => SearchContentFilter.all,
      SearchDiscoverType.anime => SearchContentFilter.anime,
      SearchDiscoverType.movies => SearchContentFilter.movies,
      // Provider MediaItems do not have a universal movie-vs-series type;
      // keep the legacy non-anime bucket for Providers. TMDB has a true
      // Series filter via its TV catalog.
      SearchDiscoverType.series => SearchContentFilter.movies,
    };
    emit(state.copyWith(
      discoverType: event.type,
      contentFilter: state.catalogSource == SearchCatalogSource.providers
          ? providerFilter
          : state.contentFilter,
    ));
    if (state.catalogSource == SearchCatalogSource.providers) {
      _prefs.setContentFilterName(providerFilter.name);
    }
    if (state.query.trim().isEmpty) {
      add(const SearchDiscoverRequested());
    } else if (state.catalogSource == SearchCatalogSource.tmdb || state.catalogSource == SearchCatalogSource.thePornDb || state.catalogSource == SearchCatalogSource.mixed) {
      add(const SearchSubmitted());
    }
  }

  bool get _isCatalogMode {
    final mode = sl.isRegistered<ContentModeCubit>() ? sl<ContentModeCubit>().state : ContentMode.anime;
    return mode == ContentMode.anime && state.catalogSource != SearchCatalogSource.providers;
  }

  Future<void> _onDiscoverRequested(
    SearchDiscoverRequested event,
    Emitter<SearchState> emit,
  ) async {
    if (state.query.trim().isNotEmpty || !_isCatalogMode) return;
    final gen = ++_discoverGen;
    emit(state.copyWith(
      status: SearchStatus.loading,
      discoverItems: const [],
      discoverPage: 1,
      discoverLoadingMore: false,
      discoverAtEnd: false,
      clearError: true,
      groups: const [],
    ));
    try {
      List<MediaItem>? items;
      Object? lastError;
      // A cold-start network/TMDB request can occasionally race the first
      // rendered Search frame. Retry once without changing the visible
      // catalog or filter selection; persistent failures still surface the
      // normal retryable error state.
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          items = await _fetchDiscoverPage(1);
          lastError = null;
          break;
        } catch (e) {
          lastError = e;
          if (attempt == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 350));
            if (isClosed || gen != _discoverGen) return;
          }
        }
      }
      if (lastError != null || items == null) {
        throw lastError ?? StateError('Discovery returned no data');
      }
      if (isClosed || gen != _discoverGen) return;
      final loaded = items;
      emit(state.copyWith(
        status: SearchStatus.success,
        discoverItems: _dedupe(loaded),
        discoverPage: 1,
        // All discovery catalogs are page-based. Trending combines TMDB's
        // paginated Now Playing and On The Air feeds, so it can continue too.
        discoverAtEnd: loaded.isEmpty,
      ));
    } catch (_) {
      // A catalog switch can start another request while this one is still
      // running. Never let the older request replace the newer catalog with
      // a stale error.
      if (!isClosed && gen == _discoverGen) {
        emit(state.copyWith(status: SearchStatus.error, error: 'Could not load discovery'));
      }
    }
  }

  Future<List<MediaItem>> _fetchDiscoverPage(int page) async {
    final type = switch (state.discoverType) {
      SearchDiscoverType.anime => 'anime',
      SearchDiscoverType.movies => 'movies',
      SearchDiscoverType.series => 'series',
      SearchDiscoverType.all => 'all',
    };
    final genre = state.genreFilter;
    final tmdb = _tmdb;
    final tpdb = _tpdb;
    if (state.catalogSource == SearchCatalogSource.tmdb) {
      if (tmdb == null) return const [];
      return tmdb.discover(
        catalog: switch (state.catalog) {
          SearchCatalog.trending => 'trending',
          SearchCatalog.popular => 'popular',
          SearchCatalog.topRated => 'top_rated',
          SearchCatalog.discoverNew => 'discover_new',
        },
        type: type,
        genre: genre,
        page: page,
      );
    }
    if (state.catalogSource == SearchCatalogSource.thePornDb) {
      if (tpdb == null || state.discoverType == SearchDiscoverType.series || state.discoverType == SearchDiscoverType.anime) return const [];
      final items = await tpdb.movies(
        page: page,
        orderBy: switch (state.catalog) {
          SearchCatalog.trending => 'recently_released',
          SearchCatalog.popular => 'most_relevant',
          SearchCatalog.topRated => 'recently_released',
          SearchCatalog.discoverNew => 'recently_created',
        },
      );
      if (state.catalog == SearchCatalog.topRated) items.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
      return items;
    }
    if (state.catalogSource == SearchCatalogSource.mixed) {
      if (state.discoverType == SearchDiscoverType.series || state.discoverType == SearchDiscoverType.anime) {
        if (tmdb == null) return const [];
        return tmdb.discover(catalog: state.catalog.name == 'trending' ? 'trending' : state.catalog.name == 'popular' ? 'popular' : state.catalog.name == 'topRated' ? 'top_rated' : 'discover_new', type: type, genre: genre, page: page);
      }
      final results = await Future.wait<List<MediaItem>>([
        if (tmdb != null)
          tmdb.discover(
            catalog: switch (state.catalog) {
              SearchCatalog.trending => 'trending',
              SearchCatalog.popular => 'popular',
              SearchCatalog.topRated => 'top_rated',
              SearchCatalog.discoverNew => 'discover_new',
            },
            type: type,
            genre: genre,
            page: page,
          ).then<List<MediaItem>>((items) => items, onError: (_, __) => const <MediaItem>[])
        else
          Future.value(const <MediaItem>[]),
        if (tpdb != null)
          tpdb.movies(
            page: page,
            orderBy: switch (state.catalog) {
              SearchCatalog.trending => 'recently_released',
              SearchCatalog.popular => 'most_relevant',
              SearchCatalog.topRated => 'recently_released',
              SearchCatalog.discoverNew => 'recently_created',
            },
          ).then<List<MediaItem>>((items) => items, onError: (_, __) => const <MediaItem>[])
        else
          Future.value(const <MediaItem>[]),
      ]);
      final tmdbItems = results[0];
      final tpdbItems = results[1];
      if (state.catalog == SearchCatalog.topRated) tpdbItems.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
      return _interleaveCatalogs(tmdbItems, tpdbItems);
    }
    final sourceId = sl<ActiveSourceCubit>().state;
    final dateRange = switch (state.catalog) {
      SearchCatalog.trending => 1,
      SearchCatalog.popular => 30,
      SearchCatalog.topRated => 0,
      SearchCatalog.discoverNew => 7,
    };
    final items = await _repo.popular(
      dateRange: dateRange,
      page: page,
      sourceId: sourceId,
    );
    if (state.catalog == SearchCatalog.discoverNew) {
      items.shuffle();
    }
    return items.where((item) {
      if (!state.contentFilter.matches(item)) return false;
      if (genre != null && !SearchMeta.matchesGenre(item, genre)) return false;
      return true;
    }).toList();
  }

  List<MediaItem> _interleaveCatalogs(List<MediaItem> a, List<MediaItem> b) {
    final out = <MediaItem>[];
    var i = 0;
    while (i < a.length || i < b.length) {
      if (i < a.length) out.add(a[i]);
      if (i < b.length) out.add(b[i]);
      i++;
    }
    return out;
  }

  List<MediaItem> _dedupe(List<MediaItem> input) {
    final seen = <String>{};
    return [for (final item in input) if (seen.add('${item.title.toLowerCase()}|${item.tmdbId}|${item.tmdbIsTv}')) item];
  }

  Future<void> _onDiscoverMore(
    SearchDiscoverMore event,
    Emitter<SearchState> emit,
  ) async {
    if (state.query.trim().isNotEmpty) {
      await _onSearchMore(event, emit);
      return;
    }
    if (state.discoverLoadingMore || state.discoverAtEnd) return;
    emit(state.copyWith(discoverLoadingMore: true));
    try {
      final next = state.discoverPage + 1;
      final items = await _fetchDiscoverPage(next);
      final merged = _dedupe([...state.discoverItems, ...items]);
      if (!isClosed) emit(state.copyWith(
        discoverItems: merged,
        discoverPage: next,
        discoverLoadingMore: false,
        discoverAtEnd: items.isEmpty,
      ));
    } catch (_) {
      if (!isClosed) emit(state.copyWith(discoverLoadingMore: false));
    }
  }

  Future<void> _onSearchMore(
    SearchDiscoverMore event,
    Emitter<SearchState> emit,
  ) async {
    if (!_isCatalogMode) return;
    if (state.catalogSource == SearchCatalogSource.thePornDb || state.catalogSource == SearchCatalogSource.mixed) {
      if (state.query.trim().isEmpty || state.searchLoadingMore || state.searchAtEnd) return;
      final next = state.searchPage + 1;
      emit(state.copyWith(searchLoadingMore: true));
      final tmdb = _tmdb;
      final tpdb = _tpdb;
      try {
        final tpdbFuture = tpdb != null
            ? tpdb.search(state.query.trim(), page: next).then<List<MediaItem>>((items) => items, onError: (_, __) => const <MediaItem>[])
            : Future.value(const <MediaItem>[]);
        final tmdbFuture = (state.catalogSource == SearchCatalogSource.mixed && tmdb != null)
            ? tmdb.search(query: state.query.trim(), type: switch (state.discoverType) { SearchDiscoverType.anime => 'anime', SearchDiscoverType.movies => 'movies', SearchDiscoverType.series => 'series', SearchDiscoverType.all => 'all' }, genre: state.genreFilter, page: next).then<List<MediaItem>>((items) => items, onError: (_, __) => const <MediaItem>[])
            : Future.value(const <MediaItem>[]);
        final results = await Future.wait([tpdbFuture, tmdbFuture]);
        final tpdbItems = results[0];
        final tmdbItems = results[1];
        final existing = state.groups.expand((g) => g.items).toList();
        final merged = _dedupe([...existing, ..._interleaveCatalogs(tmdbItems, tpdbItems)]);
        emit(state.copyWith(status: SearchStatus.success, groups: [SourceResultGroup(sourceId: 'catalog:mixed', sourceName: state.catalogSource == SearchCatalogSource.mixed ? 'Mixed' : 'ThePornDB', items: merged)], searchPage: next, searchLoadingMore: false, searchAtEnd: tpdbItems.isEmpty && tmdbItems.isEmpty));
      } catch (_) {
        if (!isClosed) emit(state.copyWith(searchLoadingMore: false));
      }
      return;
    }
    if (state.catalogSource != SearchCatalogSource.tmdb ||
        state.query.trim().isEmpty ||
        state.searchLoadingMore ||
        state.searchAtEnd) {
      return;
    }

    final tmdb = _tmdb;
    if (tmdb == null) return;
    final next = state.searchPage + 1;
    emit(state.copyWith(searchLoadingMore: true));
    try {
      final type = switch (state.discoverType) {
        SearchDiscoverType.anime => 'anime',
        SearchDiscoverType.movies => 'movies',
        SearchDiscoverType.series => 'series',
        SearchDiscoverType.all => 'all',
      };
      final items = await tmdb.search(
        query: state.query.trim(),
        type: type,
        genre: state.genreFilter,
        page: next,
      );
      if (isClosed) return;

      final existing = state.groups
          .where((g) => g.sourceId == 'tmdb:catalog')
          .expand((g) => g.items)
          .toList();
      final merged = _dedupe([...existing, ...items]);
      emit(state.copyWith(
        status: SearchStatus.success,
        groups: [
          SourceResultGroup(
            sourceId: 'tmdb:catalog',
            sourceName: 'TMDB',
            items: merged,
          ),
        ],
        searchPage: next,
        searchLoadingMore: false,
        // Do not use items.length < 20 here: genre/type filtering can reduce
        // a perfectly valid TMDB page below 20 while later pages still match.
        searchAtEnd: items.isEmpty,
      ));
    } catch (_) {
      if (!isClosed) emit(state.copyWith(searchLoadingMore: false));
    }
  }

  /// Typing ONLY updates the field text and (debounced) fetches lightweight
  /// suggestions. It NEVER starts the multi-source provider search — that runs
  /// only on an explicit [SearchRunRequested] (Enter / icon / suggestion tap).
  void _onQueryChanged(SearchQueryChanged event, Emitter<SearchState> emit) {
    final q = event.query;
    emit(state.copyWith(query: q));
    _suggestDebounce?.cancel();

    final trimmed = q.trim();
    if (trimmed.isEmpty) {
      add(const SearchDiscoverRequested());
      // Clearing the field returns to the idle screen and drops suggestions.
      emit(
        state.copyWith(
          groups: const [],
          suggestions: const [],
          status: SearchStatus.idle,
          clearError: true,
        ),
      );
      return;
    }

    // History matches are instant; show them immediately. If the field has
    // drifted away from the last-searched query, leave the results view (back
    // to idle) so the suggestion list takes over while typing the next query.
    final historyMatches = _historyMatches(trimmed);
    final driftedFromResults =
        state.status == SearchStatus.success &&
        trimmed.toLowerCase() != _lastRunQuery.toLowerCase();
    emit(
      state.copyWith(
        suggestions: historyMatches,
        status: driftedFromResults ? SearchStatus.idle : null,
        groups: driftedFromResults ? const [] : null,
      ),
    );

    // Then fetch live title autocomplete (one fast call) and merge it in.
    final seq = ++_suggestSeq;
    _suggestDebounce = Timer(const Duration(milliseconds: 250), () async {
      final live = await _suggestions.suggest(trimmed);
      if (isClosed || seq != _suggestSeq) return;
      add(SearchSuggestionsUpdated(_merge(historyMatches, live)));
    });
  }

  void _onSuggestionsUpdated(
    SearchSuggestionsUpdated event,
    Emitter<SearchState> emit,
  ) {
    // Drop suggestions once results are on screen (or the field was cleared).
    if (state.query.trim().isEmpty) return;
    emit(state.copyWith(suggestions: event.suggestions));
  }

  void _onSortChanged(SearchSortChanged event, Emitter<SearchState> emit) {
    emit(state.copyWith(sort: event.sort));
    _prefs.setSortName(event.sort.name);
  }

  /// Flips the search scope (current-source-only vs all sources), persists it,
  /// and re-runs the current query so the new scope takes effect immediately.
  Future<void> _onScopeChanged(
    SearchScopeChanged event,
    Emitter<SearchState> emit,
  ) async {
    if (event.currentSourceOnly == state.currentSourceOnly) return;
    // Reset the per-source chip — it's meaningless in current-source mode and
    // stale when switching back to all-sources.
    emit(
      state.copyWith(
        currentSourceOnly: event.currentSourceOnly,
        sourceFilter: kAllSources,
        ecosystem: SearchEcosystem.all,
      ),
    );
    _prefs.setCurrentSourceOnly(event.currentSourceOnly);
    if (state.query.trim().isNotEmpty) {
      await _runSearch(state.query.trim(), emit);
    }
  }

  void _onSourceFilterChanged(
    SearchSourceFilterChanged event,
    Emitter<SearchState> emit,
  ) {
    emit(state.copyWith(sourceFilter: event.sourceId));
  }

  /// Switches the ecosystem tab. This is a pure VIEW filter over the loaded
  /// groups (no re-search). Switching tabs can hide the source group the
  /// per-source chip pointed at, so reset that chip to "all sources" — the user
  /// never lands on an empty filtered view.
  void _onEcosystemChanged(
    SearchEcosystemChanged event,
    Emitter<SearchState> emit,
  ) {
    emit(state.copyWith(ecosystem: event.ecosystem, sourceFilter: kAllSources));
  }

  void _onContentFilterChanged(
    SearchContentFilterChanged event,
    Emitter<SearchState> emit,
  ) {
    // Switching content type can hide the active source group; fall back to
    // "All sources" so the user never lands on an empty filtered view.
    emit(
      state.copyWith(contentFilter: event.filter, sourceFilter: kAllSources),
    );
    _prefs.setContentFilterName(event.filter.name);
    if (state.query.trim().isEmpty) {
      add(const SearchDiscoverRequested());
    } else {
      add(const SearchSubmitted());
    }
  }

  void _onAudioFilterChanged(
    SearchAudioFilterChanged event,
    Emitter<SearchState> emit,
  ) {
    // Switching audio can hide the active source group; fall back to "All
    // sources" so the user never lands on an empty filtered view.
    emit(state.copyWith(audioFilter: event.filter, sourceFilter: kAllSources));
    _prefs.setAudioFilterName(event.filter.name);
    if (state.query.trim().isEmpty) {
      add(const SearchDiscoverRequested());
    } else {
      add(const SearchSubmitted());
    }
  }

  void _onGenreFilterChanged(
    SearchGenreFilterChanged event,
    Emitter<SearchState> emit,
  ) {
    emit(
      state.copyWith(
        genreFilter: event.genre,
        clearGenreFilter: event.genre == null,
        sourceFilter: kAllSources,
      ),
    );
    _prefs.setGenre(event.genre);
    if (state.query.trim().isEmpty) {
      add(const SearchDiscoverRequested());
    } else {
      add(const SearchSubmitted());
    }
  }

  void _onStatusFilterChanged(
    SearchStatusFilterChanged event,
    Emitter<SearchState> emit,
  ) {
    // Switching status can hide the active source group; fall back to "All
    // sources" so the user never lands on an empty filtered view.
    emit(state.copyWith(statusFilter: event.filter, sourceFilter: kAllSources));
    _prefs.setStatusFilterName(event.filter.name);
    if (state.query.trim().isEmpty) {
      add(const SearchDiscoverRequested());
    } else {
      add(const SearchSubmitted());
    }
  }

  /// The single entry point for the heavy search. Sets [query] when provided
  /// (suggestion taps), cancels any pending autocomplete, clears suggestions,
  /// and runs the cross-source search.
  Future<void> _onRunRequested(
    SearchRunRequested event,
    Emitter<SearchState> emit,
  ) async {
    _suggestDebounce?.cancel();
    final q = (event.query ?? state.query).trim();
    if (q.isEmpty) return;
    // Reset only the per-search source chip + ecosystem tab — the user's
    // remembered sort and content/audio/genre filters persist across searches
    // (and screen opens); a fresh search always lands on the "All" tab.
    emit(
      state.copyWith(
        query: q,
        suggestions: const [],
        sourceFilter: kAllSources,
        ecosystem: SearchEcosystem.all,
      ),
    );
    await _runSearch(q, emit);
  }

  /// Re-runs the CURRENT query without resetting filters/sort — used by the
  /// filter sheet's Apply and the source picker.
  Future<void> _onSubmitted(
    SearchSubmitted event,
    Emitter<SearchState> emit,
  ) async {
    _suggestDebounce?.cancel();
    final q = state.query.trim();
    if (q.isEmpty) return;
    emit(state.copyWith(suggestions: const []));
    await _runSearch(q, emit);
  }

  /// Searches every selected source concurrently and emits each source's
  /// results as soon as they arrive (fast sources show first; one slow/broken
  /// source never blocks the rest).
  Future<void> _runSearch(String q, Emitter<SearchState> emit) async {
    if (_isCatalogMode) {
      if (state.catalogSource == SearchCatalogSource.thePornDb || state.catalogSource == SearchCatalogSource.mixed) {
        final gen = ++_runGen;
        _lastRunQuery = q;
        _history.add(q);
        emit(state.copyWith(status: SearchStatus.loading, groups: const [], discoverItems: const [], searchPage: 1, searchLoadingMore: false, searchAtEnd: false, clearError: true));
        try {
          final tmdb = _tmdb;
          final tpdb = _tpdb;
          final tpdbFuture = tpdb != null
              ? tpdb.search(q).then<List<MediaItem>>((items) => items, onError: (_, __) => const <MediaItem>[])
              : Future.value(const <MediaItem>[]);
          final tmdbFuture = (state.catalogSource == SearchCatalogSource.mixed && tmdb != null)
              ? tmdb.search(query: q, type: switch (state.discoverType) { SearchDiscoverType.anime => 'anime', SearchDiscoverType.movies => 'movies', SearchDiscoverType.series => 'series', SearchDiscoverType.all => 'all' }, genre: state.genreFilter).then<List<MediaItem>>((items) => items, onError: (_, __) => const <MediaItem>[])
              : Future.value(const <MediaItem>[]);
          final results = await Future.wait([tpdbFuture, tmdbFuture]);
          if (isClosed || gen != _runGen) return;
          final tpdbItems = results[0];
          final tmdbItems = results[1];
          final merged = _dedupe(_interleaveCatalogs(tmdbItems, tpdbItems));
          emit(state.copyWith(status: SearchStatus.success, groups: [SourceResultGroup(sourceId: 'catalog:mixed', sourceName: state.catalogSource == SearchCatalogSource.mixed ? 'Mixed' : 'ThePornDB', items: merged)], discoverItems: const [], searchPage: 1, searchLoadingMore: false, searchAtEnd: merged.isEmpty));
        } catch (_) {
          if (!isClosed && gen == _runGen) emit(state.copyWith(status: SearchStatus.error, groups: const [], error: state.catalogSource == SearchCatalogSource.mixed ? 'Catalog search failed' : 'ThePornDB search failed'));
        }
        return;
      }

      if (state.catalogSource == SearchCatalogSource.tmdb) {
        final gen = ++_runGen;
        _lastRunQuery = q;
        _history.add(q);
        emit(state.copyWith(status: SearchStatus.loading, groups: const [], discoverItems: const [], searchPage: 1, searchLoadingMore: false, searchAtEnd: false, clearError: true));
        try {
          final tmdb = _tmdb;
          if (tmdb == null) {
            emit(state.copyWith(status: SearchStatus.success, groups: const []));
            return;
          }
          final type = switch (state.discoverType) {
            SearchDiscoverType.anime => 'anime',
            SearchDiscoverType.movies => 'movies',
            SearchDiscoverType.series => 'series',
            SearchDiscoverType.all => 'all',
          };
          final items = await tmdb.search(query: q, type: type, genre: state.genreFilter);
          if (isClosed || gen != _runGen) return;
          emit(state.copyWith(status: SearchStatus.success, groups: [SourceResultGroup(sourceId: 'tmdb:catalog', sourceName: 'TMDB', items: items)], discoverItems: const [], searchPage: 1, searchLoadingMore: false, searchAtEnd: items.isEmpty));
        } catch (_) {
          if (!isClosed && gen == _runGen) emit(state.copyWith(status: SearchStatus.error, groups: const [], error: 'TMDB search failed'));
        }
        return;
      }
    }

    final gen = ++_runGen; // this run is superseded once a newer one starts
    _lastRunQuery = q;
    _history.add(q);

    emit(
      state.copyWith(
        status: SearchStatus.loading,
        groups: const [],
        respondedSources: const {},
        failedSources: const {},
        queriedSources: const {},
        clearError: true,
      ),
    );

    // Choose the sources to query. In current-source-only mode that's JUST the
    // active Home source (read live, so a later source switch is picked up). In
    // all-sources mode it's every loaded source EXCEPT the ones the user
    // switched off for search (search-only — doesn't affect Home use).
    List<({String id, String name})> sources;
    if (state.currentSourceOnly) {
      final activeId = sl<ActiveSourceCubit>().state;
      sources = [(id: activeId, name: _repo.displayName(activeId))];
    } else {
      final prefs = sl<SearchSourcePrefs>();
      sources = _modeSources().where((s) => prefs.isIncluded(s.id)).toList();
    }
    if (sources.isEmpty) {
      // Not a failure — there was nothing to search. Says so, rather than
      // reusing the generic "search failed" copy for a setup problem.
      emit(
        state.copyWith(
          status: SearchStatus.error,
          error: 'No sources are switched on for search.',
        ),
      );
      return;
    }

    // Health-aware ordering + skipping (best-effort; never breaks search). In
    // all-sources mode: drop sources with a FRESH "dead" mark (they're retried
    // after the re-check window, never permanently blacklisted) and order the
    // rest healthiest-first so good sources stream their results soonest. In
    // current-source-only mode we always query the one chosen source (never skip
    // it — the user explicitly picked it).
    final health = sl<SourceHealthStore>();
    // Sources the health check drops before they're ever queried. Reported as
    // failures rather than dropped silently: a fresh "dead" mark only comes
    // from a hard error, so "couldn't be reached" is what actually happened
    // last time — and the Retry on that row clears the mark, which is exactly
    // the recovery.
    final skipped = <String>[];
    if (!state.currentSourceOnly) {
      final live = sources.where((s) => !health.isSkippable(s.id)).toList();
      // If EVERY source is currently skippable, the windows have likely all
      // lapsed-or-not together; rather than show nothing, retry them all.
      if (live.isNotEmpty) {
        final liveIds = {for (final s in live) s.id};
        skipped.addAll(
          sources.where((s) => !liveIds.contains(s.id)).map((s) => s.id),
        );
        sources = live;
      }
      int rank(SourceHealth h) => switch (h) {
        SourceHealth.ok => 0,
        SourceHealth.slow => 1,
        SourceHealth.dead => 2,
      };
      sources.sort(
        (a, b) =>
            rank(health.statusOf(a.id)).compareTo(rank(health.statusOf(b.id))),
      );
    }

    // Wipe the search cache if the loaded-source set changed since last time, so
    // a newly added/removed source is reflected immediately (per-source keying
    // already keeps a new source out of the cache; this covers removes too).
    _repo.syncSearchCache();

    // What's genuinely in flight, so the screen's skeletons match reality
    // instead of its own guess at the source list.
    emit(
      state.copyWith(
        queriedSources: {for (final s in sources) s.id},
        failedSources: {for (final id in skipped) id: SourceOutcome.error},
      ),
    );

    final acc = <SourceResultGroup>[];
    // Which sources broke, and how. Was a single `anyError` bool, which threw
    // away the one thing the UI needed to explain itself.
    final failed = <String, SourceOutcome>{...state.failedSources};
    // Monotonic arrival counter: the Nth source to return non-empty results gets
    // arrivalIndex N, so sections render fastest-first (CloudStream-style).
    var arrived = 0;

    await Future.wait(
      sources.map((s) async {
        final sw = Stopwatch()..start();
        try {
          final res = await _repo
              .searchStatus(
                q,
                sourceId: s.id,
                filtersJson: state.filterSelectionFor(s.id),
                cache: true,
              )
              .timeout(sourceTimeout, onTimeout: _timedOut);
          sw.stop();
          if (isClosed || gen != _runGen) return; // superseded/closed
          // Record health: a response over the slow threshold downgrades an
          // otherwise-ok outcome to "slow"; error/timeout/blocked mark it dead
          // (recoverably); empty-without-error stays ok (NOT a strike).
          var outcome = res.outcome;
          final responded =
              outcome == SourceOutcome.ok || outcome == SourceOutcome.empty;
          if (responded && sw.elapsed > SourceHealthStore.slowThreshold) {
            outcome = SourceOutcome.slow;
          }
          // ignore: unawaited_futures
          health.record(s.id, outcome, responseMs: sw.elapsedMilliseconds);
          if (!responded && outcome != SourceOutcome.slow) {
            failed[s.id] = outcome;
          }
          if (res.items.isNotEmpty) {
            acc.add(
              SourceResultGroup(
                sourceId: s.id,
                sourceName: s.name,
                items: res.items,
                arrivalIndex: arrived++,
              ),
            );
            emit(
              state.copyWith(
                status: SearchStatus.success,
                groups: List.of(acc),
                respondedSources: {...state.respondedSources, s.id},
                failedSources: Map.of(failed),
              ),
            );
          } else {
            // No results, but the source DID answer — mark it responded (without
            // touching status/groups) so its pending skeleton clears instead of
            // sitting there forever. See [SearchState.respondedSources].
            emit(
              state.copyWith(
                respondedSources: {...state.respondedSources, s.id},
                failedSources: Map.of(failed),
              ),
            );
          }
        } catch (_) {
          // searchStatus is no-throw, but stay defensive — never let one source
          // break the fan-out. Still mark it responded so its skeleton clears.
          failed[s.id] = SourceOutcome.error;
          if (!isClosed && gen == _runGen) {
            emit(
              state.copyWith(
                respondedSources: {...state.respondedSources, s.id},
                failedSources: Map.of(failed),
              ),
            );
          }
        }
      }),
    );

    if (isClosed || gen != _runGen) return;
    // Finalize: if nothing came back, surface error-or-empty appropriately.
    if (acc.isEmpty) {
      emit(
        state.copyWith(
          status: failed.isNotEmpty
              ? SearchStatus.error
              : SearchStatus.success,
          groups: const [],
          failedSources: Map.of(failed),
        ),
      );
    } else {
      emit(
        state.copyWith(
          status: SearchStatus.success,
          groups: List.of(acc),
          failedSources: Map.of(failed),
        ),
      );
    }
  }

  /// Retries what failed, after clearing the health mark(s) first.
  ///
  /// That clear matters: a hard error marks a source dead, and [_runSearch]
  /// skips a freshly-dead source — so without it the retry the user just asked
  /// for would silently decline to run.
  ///
  /// With a [SearchRetryRequested.sourceId] this re-queries that one source and
  /// splices the result into the existing groups, so the sources that already
  /// answered keep their results instead of the whole view resetting. Without
  /// one it re-runs the search; the short-TTL cache means the sources that
  /// worked come back from memory while the failed ones (never cached) go live.
  Future<void> _onRetryRequested(
    SearchRetryRequested event,
    Emitter<SearchState> emit,
  ) async {
    final q = state.query.trim();
    if (q.isEmpty) return;
    final health = sl<SourceHealthStore>();
    final id = event.sourceId;

    if (id == null) {
      for (final failedId in state.failedSources.keys) {
        await health.clear(failedId);
      }
      await _runSearch(q, emit);
      return;
    }

    await health.clear(id);
    // Back to "still searching" for this one source: drops the failed row and
    // puts its skeleton back, so the retry is visibly doing something.
    emit(
      state.copyWith(
        respondedSources: {...state.respondedSources}..remove(id),
        failedSources: Map.of(state.failedSources)..remove(id),
      ),
    );

    final sw = Stopwatch()..start();
    final res = await _repo
        .searchStatus(
          q,
          sourceId: id,
          filtersJson: state.filterSelectionFor(id),
          cache: true,
        )
        .timeout(sourceTimeout, onTimeout: _timedOut);
    sw.stop();
    if (isClosed || state.query.trim() != q) return;

    var outcome = res.outcome;
    final responded =
        outcome == SourceOutcome.ok || outcome == SourceOutcome.empty;
    if (responded && sw.elapsed > SourceHealthStore.slowThreshold) {
      outcome = SourceOutcome.slow;
    }
    // ignore: unawaited_futures
    health.record(id, outcome, responseMs: sw.elapsedMilliseconds);

    final failed = Map.of(state.failedSources);
    if (responded || outcome == SourceOutcome.slow) {
      failed.remove(id);
    } else {
      failed[id] = outcome;
    }

    final groups = List<SourceResultGroup>.of(state.groups);
    if (res.items.isNotEmpty) {
      final idx = groups.indexWhere((g) => g.sourceId == id);
      final g = SourceResultGroup(
        sourceId: id,
        sourceName: _repo.displayName(id),
        items: res.items,
        arrivalIndex: idx >= 0 ? groups[idx].arrivalIndex : groups.length,
      );
      if (idx >= 0) {
        groups[idx] = g;
      } else {
        groups.add(g);
      }
    }

    emit(
      state.copyWith(
        // Mirrors _runSearch's finalize: still nothing to show and something
        // still broken means we're back on the error view.
        status: groups.isEmpty && failed.isNotEmpty
            ? SearchStatus.error
            : SearchStatus.success,
        groups: groups,
        respondedSources: {...state.respondedSources, id},
        queriedSources: {...state.queriedSources, id},
        failedSources: failed,
      ),
    );
  }

  /// Past searches that contain [query] (case-insensitive), newest-first.
  List<String> _historyMatches(String query) {
    final l = query.toLowerCase();
    return _history
        .recent()
        .where((e) {
          final el = e.toLowerCase();
          return el != l && el.contains(l);
        })
        .take(4)
        .toList();
  }

  /// History first (already de-duped against itself), then live titles that
  /// aren't already present. Capped so the list stays compact.
  List<String> _merge(List<String> history, List<String> live) {
    final out = <String>[...history];
    final seen = {for (final h in history) h.toLowerCase()};
    for (final t in live) {
      if (seen.add(t.toLowerCase())) out.add(t);
      if (out.length >= 8) break;
    }
    return out;
  }

  /// Stores the per-source filter selection (Aniyomi or Mihon, routed by the
  /// `mihon:` id prefix) and re-fetches that one source with the updated
  /// selection applied.
  ///
  /// An empty [SearchSourceFiltersApplied.selectionJson] clears the entry,
  /// reverting the source to unfiltered results on the next search.
  Future<void> _onSourceFiltersApplied(
    SearchSourceFiltersApplied event,
    Emitter<SearchState> emit,
  ) async {
    final isMihon = event.sourceId.startsWith('mihon:');
    final map = Map<String, String>.of(
      isMihon ? state.mihonFiltersBySource : state.aniFiltersBySource,
    );
    if (event.selectionJson.isEmpty) {
      map.remove(event.sourceId);
    } else {
      map[event.sourceId] = event.selectionJson;
    }
    emit(
      isMihon
          ? state.copyWith(mihonFiltersBySource: map)
          : state.copyWith(aniFiltersBySource: map),
    );
    final q = state.query.trim();
    if (q.isEmpty) {
      // Filters with an empty search box = browse. The idle screen's "Top
      // picks" comes from home(), which takes no filters, so without this the
      // selection was stored and then silently ignored — exactly what a source's
      // Sort/Genre/Year filters are for. Aniyomi treats no-query-plus-filters as
      // an ordinary search and extensions implement it that way, so we ask for
      // the same thing.
      await _browseWithFilters(event.sourceId, map[event.sourceId], emit);
      return;
    }
    final res = await _repo.searchStatus(
      q,
      sourceId: event.sourceId,
      filtersJson: map[event.sourceId],
    );
    if (isClosed || state.query.trim() != q) return;
    final groups = List<SourceResultGroup>.of(state.groups);
    final idx = groups.indexWhere((g) => g.sourceId == event.sourceId);
    if (res.items.isEmpty) {
      if (idx >= 0) groups.removeAt(idx);
    } else {
      final arrival = idx >= 0 ? groups[idx].arrivalIndex : groups.length;
      final g = SourceResultGroup(
        sourceId: event.sourceId,
        sourceName: _repo.displayName(event.sourceId),
        items: res.items,
        arrivalIndex: arrival,
      );
      if (idx >= 0) {
        groups[idx] = g;
      } else {
        groups.add(g);
      }
    }
    emit(state.copyWith(groups: groups));
  }

  /// Runs an empty-query search carrying only [filtersJson] and parks the
  /// results in `filteredBrowse`, which the idle screen shows in place of "Top
  /// picks". A cleared selection (null/empty) drops straight back to the normal
  /// idle view instead of issuing a pointless unfiltered search.
  ///
  /// Failures clear the browse rather than surfacing an error: this runs off a
  /// filter tap on the idle screen, and a source that rejects empty queries
  /// should leave the user on "Top picks", not on an error page.
  Future<void> _browseWithFilters(
    String sourceId,
    String? filtersJson,
    Emitter<SearchState> emit,
  ) async {
    if (filtersJson == null || filtersJson.isEmpty) {
      emit(
        state.copyWith(filteredBrowse: const [], filteredBrowseSourceId: ''),
      );
      return;
    }
    try {
      final res = await _repo.searchStatus(
        '',
        sourceId: sourceId,
        filtersJson: filtersJson,
      );
      if (isClosed || state.query.trim().isNotEmpty) return;
      emit(
        state.copyWith(
          filteredBrowse: res.items,
          filteredBrowseSourceId: res.items.isEmpty ? '' : sourceId,
          filteredBrowsePage: 1,
          filteredBrowseLoadingMore: false,
          filteredBrowseAtEnd: false,
        ),
      );
    } catch (_) {
      if (isClosed) return;
      emit(
        state.copyWith(filteredBrowse: const [], filteredBrowseSourceId: ''),
      );
    }
  }

  /// Appends the next page of a filters-only browse (infinite scroll).
  ///
  /// A source that returns nothing, or only titles already on screen, is out of
  /// pages — some sources repeat the first page forever rather than 404ing, so
  /// the dedupe result decides, not just an empty list.
  Future<void> _onFilteredBrowseMore(
    SearchFilteredBrowseMore event,
    Emitter<SearchState> emit,
  ) async {
    if (!state.canLoadMoreFilteredBrowse) return;
    final sourceId = state.filteredBrowseSourceId;
    final filtersJson = state.filterSelectionFor(sourceId);
    if (sourceId.isEmpty || filtersJson == null || filtersJson.isEmpty) return;

    final nextPage = state.filteredBrowsePage + 1;
    emit(state.copyWith(filteredBrowseLoadingMore: true));
    try {
      final res = await _repo.searchStatus(
        '',
        sourceId: sourceId,
        filtersJson: filtersJson,
        page: nextPage,
      );
      if (isClosed) return;
      final seen = {for (final i in state.filteredBrowse) i.url};
      final fresh = res.items.where((i) => !seen.contains(i.url)).toList();
      emit(
        state.copyWith(
          filteredBrowse: fresh.isEmpty
              ? state.filteredBrowse
              : [...state.filteredBrowse, ...fresh],
          filteredBrowsePage: nextPage,
          filteredBrowseLoadingMore: false,
          filteredBrowseAtEnd: fresh.isEmpty,
        ),
      );
    } catch (_) {
      if (isClosed) return;
      // Stop paging on failure rather than retrying on every scroll tick.
      emit(
        state.copyWith(
          filteredBrowseLoadingMore: false,
          filteredBrowseAtEnd: true,
        ),
      );
    }
  }

  /// Mode switched — drop everything the previous mode fetched. The query text
  /// is kept so re-running it in the new mode is one tap, but nothing is
  /// searched automatically: an all-sources fan-out is expensive and the user
  /// didn't ask for it by flipping mode.
  void _onModeChanged(SearchModeChanged event, Emitter<SearchState> emit) {
    _runGen++; // orphan any in-flight fan-out from the old mode
    emit(
      state.copyWith(
        status: SearchStatus.idle,
        groups: const [],
        respondedSources: const {},
        suggestions: const [],
        sourceFilter: kAllSources,
        ecosystem: SearchEcosystem.all,
      ),
    );
  }

  @override
  Future<void> close() {
    _suggestDebounce?.cancel();
    _modeSub?.cancel();
    return super.close();
  }
}
