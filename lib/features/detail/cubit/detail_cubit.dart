import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injector.dart';
import '../../../core/metadata/episode_metadata_service.dart';
import '../../../core/metadata/tmdb_discover_service.dart';
import '../../../core/metadata/theporndb.dart';
import '../../../core/metadata/metadata_enrichment.dart';
import '../../../core/models/episode.dart';
import '../../../core/models/media_detail.dart';
import '../../../core/models/media_extras.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/provider_info.dart';
import '../../../core/playback/title_prefs.dart';
import '../../../core/repository/source_repository.dart';

export '../../../core/models/episode_title.dart' show cleanTitle;

/// Lifecycle of the detail load. Mirrors Sozo Read's `DetailStatus`
/// (we drop `initial` — the cubit starts in `loading` since `load()`
/// fires immediately on construction).
enum DetailStatus { loading, success, error }

/// Immutable view-state for the Detail screen. Owns everything that used
/// to live in `_DetailScreenState`'s setState fields: the fetched
/// [MediaDetail], the sub/dub [category], the selected season, and the
/// description-expanded flag. The scroll-driven app-bar title fade is
/// pure UI state and intentionally stays widget-level.
class DetailState extends Equatable {
  const DetailState({
    this.status = DetailStatus.loading,
    this.detail,
    this.category = 'sub',
    this.selectedSeason = 1,
    this.descExpanded = false,
    this.error,
    this.cast = const [],
    this.relations = const [],
    this.extrasLoading = false,
  });

  final DetailStatus status;
  final MediaDetail? detail;

  /// Cast + related titles, fetched async from a metadata API after the detail
  /// loads (AniList for anime, TMDB for movie/TV). Empty until resolved.
  final List<CastMember> cast;
  final List<MediaRelation> relations;
  final bool extrasLoading;

  /// 'sub' | 'dub'. Drives the Sub/Dub toggle and the player `category`.
  final String category;
  final int selectedSeason;
  final bool descExpanded;
  final String? error;

  DetailState copyWith({
    DetailStatus? status,
    MediaDetail? detail,
    String? category,
    int? selectedSeason,
    bool? descExpanded,
    String? error,
    bool clearError = false,
    List<CastMember>? cast,
    List<MediaRelation>? relations,
    bool? extrasLoading,
  }) => DetailState(
    status: status ?? this.status,
    detail: detail ?? this.detail,
    category: category ?? this.category,
    selectedSeason: selectedSeason ?? this.selectedSeason,
    descExpanded: descExpanded ?? this.descExpanded,
    error: clearError ? null : (error ?? this.error),
    cast: cast ?? this.cast,
    relations: relations ?? this.relations,
    extrasLoading: extrasLoading ?? this.extrasLoading,
  );

  @override
  List<Object?> get props => [
    status,
    detail,
    category,
    selectedSeason,
    descExpanded,
    error,
    cast,
    relations,
    extrasLoading,
  ];
}

class DetailCubit extends Cubit<DetailState> {
  DetailCubit({
    required SourceRepository repo,
    required String url,
    String? sourceId,
    TitlePrefsStore? prefs,
    int? seedMalId,
    ProviderType? seedType,
    MediaDetail? catalogDetail,
    MediaItem? catalogItem,
  }) : _repo = repo,
       _url = url,
       _sourceId = sourceId,
       _prefs = prefs ?? sl<TitlePrefsStore>(),
       _catalogDetail = catalogDetail,
       _catalogItem = catalogItem,
       // Seed the INITIAL category from the per-title remembered choice so the
       // Sub/Dub toggle reflects the saved value on the very first render (no
       // flash from 'sub' → remembered). Falls back to 'sub' when unset.
        super(
          DetailState(
            // Catalog details render immediately from the tapped card. The full
            // catalog response is fetched in the background and replaces this
            // lightweight shell, so TPDB/TMDB latency never blocks navigation.
            status: catalogDetail != null || catalogItem != null
                ? DetailStatus.success
                : DetailStatus.loading,
            detail: catalogDetail ?? _shellDetail(catalogItem, sourceId, url),
            category:
                (prefs ?? sl<TitlePrefsStore>()).category(sourceId ?? '', url) ??
                'sub',
            extrasLoading: sourceId == 'tmdb:catalog' ||
                sourceId == 'tpdb:catalog' ||
                catalogItem?.sourceId == 'tmdb:catalog' ||
                catalogItem?.sourceId == 'tpdb:catalog' ||
                catalogDetail != null,
          ),
        ) {
    // Prefetch episode metadata using the MAL id we already know from the
    // tapped item, so the AniZip call overlaps the detail fetch and episodes
    // render already-enriched instead of popping in ~0.3s later. Fire-and-
    // forget; the service dedupes this against the enrichment call and never
    // throws. Id-less titles (no seed id) just enrich after load, as before.
    if (seedType == ProviderType.anime && seedMalId != null) {
      sl<EpisodeMetadataService>().animeEpisodeMeta(seedMalId);
    }
  }

  final SourceRepository _repo;
  final String _url;
  final TitlePrefsStore _prefs;
  final MediaDetail? _catalogDetail;
  final MediaItem? _catalogItem;

  /// The in-flight (or completed) movie→anime MAL-id resolution for this title,
  /// if it's a movie-typed candidate. The player launch awaits this so a fast
  /// Play still scrobbles to AniList/MAL instead of losing the race. Null when
  /// the title isn't a movie-typed promotion candidate.
  Future<int?>? _animePromotion;
  Future<int?>? get animePromotion => _animePromotion;

  /// The owning item's source. When null, repo calls fall back to the
  /// active source. Set from `DetailScreen(item:).sourceId` so a title
  /// opened from My List / cross-source rows queries its OWN provider.
  final String? _sourceId;

  /// Stable key component for per-title prefs. Falls back to '' when the
  /// owning source is unknown (active-source title) — robust, never throws.
  String get _prefsSourceId => _sourceId ?? '';

  static MediaDetail? _shellDetail(
    MediaItem? item,
    String? sourceId,
    String url,
  ) {
    if (item == null || sourceId == null) return null;
    final isTmdb = sourceId == 'tmdb:catalog';
    final isTpdb = sourceId == 'tpdb:catalog';
    if (!isTmdb && !isTpdb) return null;
    return MediaDetail(
      id: item.id,
      title: item.title,
      englishTitle: item.englishTitle,
      cover: item.cover,
      coverHeaders: item.coverHeaders,
      url: url,
      type: item.type,
      sourceId: sourceId,
      genres: item.genres,
      tmdbId: item.tmdbId,
      tmdbIsTv: item.tmdbIsTv,
      episodes: item.type == ProviderType.movie && !item.tmdbIsTv
          ? [Episode(id: item.id, title: item.title, number: 1, url: item.url)]
          : const [],
      isSeries: item.tmdbIsTv,
    );
  }

  /// Initial fetch with automatic progressive retries. Catalog detail is always
  /// owned by its metadata catalog; streaming providers are resolved lazily only by Play/Download.
  Future<void> load() async {
    if (state.detail == null) {
      emit(state.copyWith(status: DetailStatus.loading, clearError: true));
    }
    MediaDetail? detail;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        detail = await _loadDetailForCurrentSource(state.category);
        break;
      } catch (_) {
        if (attempt < 2) {
          await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
        }
      }
    }

    if (detail != null) {
      emit(state.copyWith(
        status: DetailStatus.success,
        detail: detail,
        cast: detail.castMembers,
        relations: detail.relations,
        extrasLoading: _sourceId == 'tmdb:catalog' || _sourceId == 'tpdb:catalog',
        clearError: true,
      ));
      unawaited(_enrich(detail));
    } else {
      if (state.detail != null) {
        emit(state.copyWith(status: DetailStatus.success, extrasLoading: false, error: 'load_failed'));
      } else {
        emit(state.copyWith(status: DetailStatus.error, error: 'load_failed'));
      }
    }
  }

  Future<void> retry() async {
    await _repo.clearHttpCache();
    emit(state.copyWith(clearError: true));
    return load();
  }

  Future<MediaDetail> _loadDetailForCurrentSource(String category) async {
    final isCatalog = _sourceId == 'tmdb:catalog' ||
        (_sourceId?.startsWith('tpdb:') ?? false);
    if (!isCatalog) {
      try {
        return await _repo.detail(_url, category: category, sourceId: _sourceId);
      } catch (_) {
        if (_catalogDetail != null) return _catalogDetail!;
        if (_catalogItem != null) {
          final shell = _shellDetail(_catalogItem, _sourceId, _url);
          if (shell != null) return shell;
        }
        rethrow;
      }
    }

    final catalogItem = _catalogItem ?? MediaItem(
      id: _catalogDetail?.id ?? _url,
      title: _catalogDetail?.title ?? _url,
      englishTitle: _catalogDetail?.englishTitle,
      cover: _catalogDetail?.cover,
      url: _url,
      type: _catalogDetail?.type ?? ProviderType.movie,
      sourceId: _sourceId ?? '',
      tmdbId: _catalogDetail?.tmdbId,
      tmdbIsTv: _catalogDetail?.tmdbIsTv ?? false,
    );
    if (_catalogDetail != null) return _catalogDetail!;

    if (_sourceId == 'tmdb:catalog') {
      return sl<TmdbDiscoverService>().movieDetail(catalogItem);
    }
    return sl<ThePornDb>().movieDetail(catalogItem);
  }

  /// Pull-to-refresh. Drops the source's HTTP cache first so the re-fetch is
  /// genuinely fresh (new chapters show now instead of after the 10-min cache
  /// expires), then reloads detail+chapters for the current category. Keeps the
  /// current content on screen while refreshing — no skeleton flash — and a
  /// failed refresh leaves the page as-is rather than wiping it. Cast/Relations
  /// are already loaded and don't change, so enrichment isn't re-run.
  Future<void> refresh() async {
    await _repo.clearHttpCache();
    try {
      final detail = await _loadDetailForCurrentSource(state.category);
      if (isClosed) return;
      emit(state.copyWith(
        status: DetailStatus.success,
        detail: detail,
        cast: detail.castMembers,
        relations: detail.relations,
      ));
    } catch (_) {
      // Keep what's on screen — a failed pull shouldn't blank the page.
    }
  }

  /// Fetch Cast + Relations in the background (AniList for anime, TMDB for
  /// movie/TV) and merge into state. Best-effort — failures leave the tabs in
  /// their empty state. Runs once per title; Sub/Dub switches keep the result.
  Future<void> _enrich(MediaDetail detail) async {
    if (detail.sourceId == 'tpdb:catalog') {
      try {
        final extras = await sl<MetadataEnrichment>().fetch(detail);
        if (isClosed) return;
        emit(state.copyWith(
          cast: extras.cast.isNotEmpty ? extras.cast : detail.castMembers,
          relations: extras.relations.isNotEmpty ? extras.relations : detail.relations,
          extrasLoading: false,
        ));
      } catch (_) {
        if (!isClosed) {
          emit(state.copyWith(cast: detail.castMembers, relations: detail.relations, extrasLoading: false));
        }
      }
      return;
    }
    if (state.cast.isNotEmpty && state.relations.isNotEmpty) {
      emit(state.copyWith(extrasLoading: false));
      return;
    }
    var d = detail;

    // TMDB fallback: an id-less movie/series (e.g. some CloudStream sources)
    // can't track on Simkl and can't be id-enriched. Resolve a TMDB id from
    // title (+ year) so it gains BOTH — then re-emit the detail so the player
    // scrobbles by the resolved id.
    //
    // Gated to `== movie` explicitly, NOT `!= anime` — this is a TMDB (video
    // metadata) lookup, and `!= anime` silently let manga/novel through once
    // Task 1 added those to ProviderType. Manga often shares its anime
    // adaptation's title, so that resolved a real TMDB id and displayed the
    // ANIME's Cast/Relations on the manga's own detail page.
    if (d.malId == null &&
        d.tmdbId == null &&
        d.type == ProviderType.movie) {
      try {
        final id = await sl<MetadataEnrichment>().resolveTmdbId(
          d.title,
          d.year,
          d.tmdbIsTv,
        );
        if (isClosed) return;
        if (id != null) {
          d = d.copyWith(tmdbId: id);
          emit(state.copyWith(detail: d));
        }
      } catch (_) {/* keep going with what we have */}
    }

    // Id-less anime (Aniyomi, most CloudStream): resolve the MAL id from title
    // via AniList and store it, so the player, scrobbler AND the filler-episode
    // lookup all key off a real id instead of nothing.
    if (d.malId == null && d.type == ProviderType.anime) {
      try {
        final resolved = await sl<MetadataEnrichment>().resolveMalId(d);
        if (isClosed) return;
        if (resolved != null) {
          d = d.copyWith(malId: resolved);
          emit(state.copyWith(detail: d));
        }
      } catch (_) {/* keep going without it */}
    }

    // A movie-typed title from an anime-capable (mixed) source might actually be
    // anime the plugin tagged as TvSeries/Movie. Promote it — and route it to
    // the anime trackers — ONLY on a strict AniList match (exact title + year).
    // Gated to anime-capable sources so real movie catalogs never hit AniList.
    if (d.malId == null && d.type == ProviderType.movie) {
      final promotion = sl<MetadataEnrichment>().promoteMovieToAnimeMalId(d);
      _animePromotion = promotion; // Play awaits this same future
      try {
        final mal = await promotion;
        if (isClosed) return;
        if (mal != null) {
          d = d.copyWith(malId: mal, type: ProviderType.anime);
          emit(state.copyWith(detail: d));
        }
      } catch (_) {/* stays a movie */}
    }

    // Fill in per-episode descriptions (AniZip for anime, TMDB season for a
    // movie-source TV series). Best-effort — a miss leaves the row on its date.
    if (d.episodes.isNotEmpty) {
      try {
        final enriched = await sl<EpisodeMetadataService>().enrich(
          episodes: d.episodes,
          type: d.type,
          malId: d.malId,
          tmdbId: d.tmdbId,
          tmdbIsTv: d.tmdbIsTv,
        );
        if (isClosed) return;
        if (!identical(enriched, d.episodes)) {
          d = d.copyWith(episodes: enriched);
          emit(state.copyWith(detail: d));
        }
      } catch (_) {/* keep episodes as-is */}
    }

    // Prefer id-based enrichment (AniList/TMDB) — it's richer: actor photos,
    // more entries, properly-linked relations. Id-less anime (Aniyomi, most
    // CloudStream) also go through fetch(), which resolves extras by title.
    // Manga/novel join the id-less title-search path. They resolve no id at
    // all above (the TMDB step is movie-only, the MAL step anime-only), so
    // without them named here the gate was false three ways and Cast/Relations
    // never loaded for a reading title.
    if (d.malId != null ||
        d.tmdbId != null ||
        d.type == ProviderType.anime ||
        d.type == ProviderType.manga ||
        d.type == ProviderType.novel) {
      try {
        final extras = await sl<MetadataEnrichment>().fetch(d);
        if (isClosed) return;
        if (extras.cast.isNotEmpty || extras.relations.isNotEmpty) {
          emit(state.copyWith(cast: extras.cast, relations: extras.relations, extrasLoading: false));
          return;
        }
      } catch (_) {/* fall through to source-supplied extras */}
    }
    // Fall back to Cast/Relations the source supplied directly (e.g.
    // CloudStream's actors/recommendations) — so the tabs fill even without ids.
    if (isClosed) return;
    emit(state.copyWith(
      cast: detail.castMembers,
      relations: detail.relations,
      extrasLoading: false,
    ));
  }

  /// Sub/Dub re-fetch. No-op when the category is unchanged. Otherwise
  /// flips to loading for the new category and re-fetches, resetting the
  /// selected season to 1 (the new audio track may have a different set
  /// of seasons). Matches the original `onAudioChanged` behavior.
  Future<void> setCategory(String cat) async {
    if (cat == state.category) return;
    emit(state.copyWith(category: cat));
    try {
      // Catalog metadata is independent of audio category. Never replace the
      // catalog detail with a provider detail just because Sub/Dub changed.
      final detail = await _loadDetailForCurrentSource(cat);
      if (isClosed) return;
      emit(state.copyWith(
        status: DetailStatus.success,
        detail: detail,
        selectedSeason: 1,
      ));
      await _prefs.setCategory(_prefsSourceId, _url, cat);
    } catch (_) {
      emit(state.copyWith(status: DetailStatus.error, error: 'load_failed'));
    }
  }

  void selectSeason(int s) {
    if (s == state.selectedSeason) return;
    emit(state.copyWith(selectedSeason: s));
  }

  void toggleDesc() => emit(state.copyWith(descExpanded: !state.descExpanded));
}

// ─────────────────────────────────────────────────────────────────────────────
// Pure helpers — moved off the screen state. Stateless, so they live as
// top-level functions for both the cubit and the view to share.
// ─────────────────────────────────────────────────────────────────────────────

String statusLabel(MediaStatus status) {
  switch (status) {
    case MediaStatus.ongoing:
      return 'Ongoing';
    case MediaStatus.completed:
      return 'Completed';
    case MediaStatus.hiatus:
      return 'Hiatus';
    case MediaStatus.cancelled:
      return 'Cancelled';
    case MediaStatus.unknown:
      return '';
  }
}

/// Parse the season number from the start of an episode title.
/// Returns null if no such prefix exists.
/// E.g. "S1 E3 - Attack" gives 1; "Episode 5" gives null.
int? parseSeason(String title) {
  final m = RegExp(r'^S(\d+)').firstMatch(title.trim());
  if (m == null) return null;
  return int.tryParse(m.group(1)!);
}

/// The season an episode belongs to: the source-reported field when present
/// (CloudStream sets it per episode), else parsed from the title's `S<n>`
/// prefix. Sources that report neither are treated as single-season.
int? seasonOf(Episode ep) => ep.season ?? parseSeason(ep.title);

/// Derive the set of seasons present in the episode list or known from metadata.
/// Returns an empty set when no episode reports a season (single-season).
Set<int> seasonsOf(List<Episode> eps, [List<int>? knownSeasons]) {
  final result = <int>{};
  if (knownSeasons != null && knownSeasons.isNotEmpty) {
    result.addAll(knownSeasons);
  }
  for (final ep in eps) {
    final s = seasonOf(ep);
    if (s != null) result.add(s);
  }
  return result;
}

/// Whether to show the Sub/Dub toggle:
/// - Only for anime (ProviderType.anime)
/// - And at least one of subCount / dubCount is non-zero / non-null
bool showSubDubFor(MediaDetail detail) {
  if (detail.type != ProviderType.anime) return false;
  final hasSub = (detail.subCount ?? 0) > 0;
  final hasDub = (detail.dubCount ?? 0) > 0;
  return hasSub || hasDub;
}
