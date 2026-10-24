import 'dart:async';
import 'dart:developer' as developer;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive/hive.dart';

import '../../../core/error/exceptions.dart';
import '../../../core/lnreader/novel_cloudflare.dart';
import '../../../core/metadata/theporndb.dart';
import '../../../core/metadata/tmdb_discover_service.dart';
import '../../../core/models/home_section.dart';
import '../../../core/models/media_item.dart';
import '../../../core/platform/apple_tv.dart';
import '../../../core/prefs/catalog_source_prefs.dart';
import '../../../core/repository/source_repository.dart';

/// Immutable view-state for the Home screen.
class HomeState extends Equatable {
  const HomeState({
    this.sections, 
    this.loading = false, 
    this.cloudflareUrl,
  });

  /// The provider's named home rows, in order. Null until the first load.
  final List<HomeSection>? sections;

  /// True while the rows are being (re)fetched.
  final bool loading;

  /// Set when the active source is blocked by a Cloudflare challenge.
  final String? cloudflareUrl;

  /// Items that drive the hero carousel — the first section's items.
  List<MediaItem> get heroItems => (sections != null && sections!.isNotEmpty)
      ? sections!.first.items
      : const <MediaItem>[];

  HomeState copyWith({
    List<HomeSection>? sections,
    bool? loading,
    String? cloudflareUrl,
    bool clearCloudflareUrl = false,
  }) => HomeState(
    sections: sections ?? this.sections,
    loading: loading ?? this.loading,
    cloudflareUrl: clearCloudflareUrl ? null : (cloudflareUrl ?? this.cloudflareUrl),
  );

  @override
  List<Object?> get props => [sections, loading, cloudflareUrl];
}

/// Owns the Home rows and manages Provider, TMDB, ThePornDB and Mixed catalog loads.
class HomeCubit extends Cubit<HomeState> {
  HomeCubit(
    this._repo, [
    CatalogSourcePrefs? catalogPrefs,
    ThePornDb? tpdb,
    TmdbDiscoverService? tmdb,
  ]) : _catalogPrefs = catalogPrefs,
       _tpdb = tpdb,
       _tmdb = tmdb,
       super(
         HomeState(
           sections: getInitialCachedSections(
             catalogPrefs?.source ??
                 (tmdb != null ? CatalogSource.tmdb : CatalogSource.provider),
           ),
         ),
       );

  final SourceRepository _repo;
  final CatalogSourcePrefs? _catalogPrefs;
  final ThePornDb? _tpdb;
  final TmdbDiscoverService? _tmdb;

  static const String boxName = 'home_sections_cache';

  /// Loads cached home sections from Hive storage for instant 0ms startup.
  static List<HomeSection>? getInitialCachedSections(CatalogSource source) {
    try {
      if (!Hive.isBoxOpen(boxName)) return null;
      final raw = Hive.box(boxName).get(source.name);
      if (raw is List && raw.isNotEmpty) {
        final parsed = <HomeSection>[];
        for (final entry in raw) {
          if (entry is! Map) continue;
          final map = Map<String, dynamic>.from(entry);
          final title = map['title'] as String? ?? '';
          final itemsRaw = map['items'] as List? ?? const [];
          final items = <MediaItem>[];
          for (final it in itemsRaw) {
            if (it is Map) {
              items.add(MediaItem.fromJson(Map<String, dynamic>.from(it)));
            }
          }
          BrowseMore? more;
          if (map['more'] is Map) {
            final m = Map<String, dynamic>.from(map['more'] as Map);
            more = BrowseMore(
              sourceId: m['sourceId'] as String? ?? '',
              kind: m['kind'] as String? ?? '',
              categoryId: m['categoryId'] as String?,
            );
          }
          parsed.add(HomeSection(title: title, items: List<MediaItem>.unmodifiable(items), more: more));
        }
        if (parsed.isNotEmpty) return List<HomeSection>.unmodifiable(parsed);
      }
    } catch (_) {}
    return null;
  }

  /// Persists home sections into local Hive storage.
  static void saveSectionsToCache(CatalogSource source, List<HomeSection> sections) {
    try {
      if (!Hive.isBoxOpen(boxName)) return;
      final payload = sections.map((s) => {
        'title': s.title,
        'items': s.items.map((i) => i.toJson()).toList(),
        if (s.more != null) 'more': {
          'sourceId': s.more!.sourceId,
          'kind': s.more!.kind,
          'categoryId': s.more!.categoryId,
        },
      }).toList();
      Hive.box(boxName).put(source.name, payload);
    } catch (_) {}
  }

  CatalogSource get _catalogSource =>
      _catalogPrefs?.source ??
      (_tmdb != null ? CatalogSource.tmdb : CatalogSource.provider);

  /// Monotonic generation counter to prevent async race conditions (latest wins).
  int _gen = 0;

  /// In-memory cache for catalog sections (5-minute TTL) to prevent empty row flashing.
  static final Map<CatalogSource, (DateTime, List<HomeSection>)> _catalogCache = {};

  /// Appends paged items to a specific section's list in a strictly immutable way.
  /// Prevents any duplicate list items and ensures safe reactive widget updates.
  /// Returns the number of unique items added.
  int appendItems(String sectionTitle, List<MediaItem> newItems) {
    final currentSections = state.sections;
    if (currentSections == null || isClosed) return 0;

    var addedCount = 0;
    final updatedSections = currentSections.map((s) {
      if (s.title == sectionTitle) {
        final existingKeys = s.items.map((it) => it.id.isNotEmpty ? it.id : it.url).toSet();
        final uniqueNewItems = newItems
            .where((it) => !existingKeys.contains(it.id.isNotEmpty ? it.id : it.url))
            .toList();

        if (uniqueNewItems.isEmpty) return s;
        addedCount = uniqueNewItems.length;

        return HomeSection(
          title: s.title,
          items: List<MediaItem>.unmodifiable([...s.items, ...uniqueNewItems]),
          more: s.more,
        );
      }
      return s;
    }).toList(growable: false);

    if (addedCount > 0) {
      emit(state.copyWith(sections: List<HomeSection>.unmodifiable(updatedSections)));
    }
    return addedCount;
  }

  /// (Re)loads the rows.
  Future<void> load({bool reset = false}) async {
    final gen = ++_gen;
    final sourceId = _repo.sourceId;
    final source = _catalogSource;

    if (reset) {
      _catalogCache.remove(source);
      emit(const HomeState(loading: true));
    } else {
      final cached = _catalogCache[source];
      if (cached != null &&
          DateTime.now().difference(cached.$1).inMinutes < 5 &&
          cached.$2.isNotEmpty) {
        emit(HomeState(sections: List<HomeSection>.unmodifiable(cached.$2), loading: false));
        return;
      }

      // If in-memory is empty but disk cache exists, preserve existing sections while loading
      if (state.sections == null) {
        final diskSections = getInitialCachedSections(source);
        if (diskSections != null && diskSections.isNotEmpty) {
          emit(state.copyWith(sections: diskSections, loading: true));
        } else {
          emit(state.copyWith(loading: true));
        }
      } else {
        emit(state.copyWith(loading: true));
      }
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
            ? await homeFuture.timeout(const Duration(seconds: 15))
            : await homeFuture.timeout(const Duration(seconds: 15));
        if (sections.isNotEmpty) {
          saveSectionsToCache(source, sections);
        }
      }
    } on TimeoutException catch (_) {
      _logDiagnostic('Load timed out for source: $sourceId');
      sections = const <HomeSection>[];
    } on CloudflareRequiredException catch (e) {
      _logDiagnostic('Cloudflare challenge required for source: $sourceId');
      sections = const <HomeSection>[];
      cloudflareUrl = e.url;
    } catch (e, st) {
      _logDiagnostic('Load failed for source: $sourceId', error: e, stackTrace: st);
      sections = const <HomeSection>[];
    }

    if (cloudflareUrl == null && sections.isEmpty) {
      cloudflareUrl = NovelCloudflare.pendingUrl;
    }
    if (sections.isNotEmpty) NovelCloudflare.clear();

    if (isClosed || gen != _gen) return;
    
    emit(
      HomeState(
        sections: List<HomeSection>.unmodifiable(sections),
        loading: false,
        cloudflareUrl: cloudflareUrl,
      ),
    );
  }

  Future<List<HomeSection>> _loadCatalogProgressively(
    CatalogSource source,
    int gen,
  ) async {
    final kinds = _resolveKindsForSource(source);
    final byKind = <String, HomeSection>{};

    Future<HomeSection?> fetch(String kind) async {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          if (source == CatalogSource.thePornDb) {
            final section = await _tpdb!.homeSection(kind).timeout(const Duration(seconds: 6));
            if (section != null && section.items.isNotEmpty) return section;
          } else if (source == CatalogSource.mixed) {
            if (kind.startsWith('mixed_')) {
              final tmdbKind = kind.replaceFirst('mixed_', 'tmdb_');
              final tpdbKind = _resolveTpdbKind(kind);
              final tpdb = _tpdb;
              final results = await Future.wait([
                _tmdb!.homeSection(tmdbKind).timeout(const Duration(seconds: 5), onTimeout: () => null),
                tpdb != null
                    ? tpdb.homeSection(tpdbKind).timeout(const Duration(seconds: 5), onTimeout: () => null)
                    : Future.value(null),
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
                items: List<MediaItem>.unmodifiable(merged),
                more: BrowseMore(sourceId: 'mixed:catalog', kind: kind),
              );
            } else if (kind.startsWith('tpdb_')) {
              final tpdb = _tpdb;
              if (tpdb == null) return null;
              final section = await tpdb.homeSection(kind).timeout(const Duration(seconds: 6));
              if (section != null && section.items.isNotEmpty) return section;
            } else {
              final section = await _tmdb!.homeSection(kind).timeout(const Duration(seconds: 5));
              if (section != null && section.items.isNotEmpty) return section;
            }
          } else {
            final section = await _tmdb!.homeSection(kind).timeout(const Duration(seconds: 5));
            if (section != null && section.items.isNotEmpty) return section;
          }
        } catch (e, st) {
          if (attempt == 1) {
            _logDiagnostic('Failed to load section $kind after 2 attempts', error: e, stackTrace: st);
            return null;
          }
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
      return null;
    }

    final futures = <Future<void>>[];
    for (final kind in kinds) {
      futures.add(fetch(kind).then((section) {
        if (section == null || isClosed || gen != _gen) return;
        byKind[kind] = section;
        final ordered = [
          for (final k in kinds) 
            if (byKind.containsKey(k)) byKind[k]!
        ];
        emit(state.copyWith(sections: List<HomeSection>.unmodifiable(ordered), loading: true));
      }));
    }

    await Future.wait(futures);
    final finalOrdered = [
      for (final k in kinds) 
        if (byKind.containsKey(k)) byKind[k]!
    ];
    if (finalOrdered.isNotEmpty) {
      _catalogCache[source] = (DateTime.now(), finalOrdered);
      saveSectionsToCache(source, finalOrdered);
    }
    return finalOrdered;
  }

  // ── Helper Resolvers ──────────────────────────────────────────────────────

  List<String> _resolveKindsForSource(CatalogSource source) {
    final prefs = _catalogPrefs;
    if (prefs != null) {
      final custom = prefs.getSectionOrder(source);
      if (custom.isNotEmpty) return custom;
    }
    return CatalogSourcePrefs.defaultKindsFor(source);
  }

  String _resolveTpdbKind(String kind) => switch (kind) {
        'mixed_recent' => 'tpdb_recent',
        'mixed_trending_movies' => 'tpdb_trending',
        'mixed_popular_movies' => 'tpdb_popular',
        'mixed_top_rated_movies' => 'tpdb_top_rated',
        _ => 'tpdb_recent',
      };

  List<MediaItem> _interleave(List<MediaItem> items) {
    final tmdb = items.where((item) => item.sourceId == 'tmdb:catalog').toList(growable: false);
    final tpdb = items.where((item) => item.sourceId.startsWith('tpdb:')).toList(growable: false);
    final out = <MediaItem>[];
    
    var i = 0, j = 0;
    while (i < tmdb.length || j < tpdb.length) {
      if (i < tmdb.length) out.add(tmdb[i++]);
      if (j < tpdb.length) out.add(tpdb[j++]);
    }
    return out;
  }

  void _logDiagnostic(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(
      message,
      name: 'HomeCubit',
      error: error,
      stackTrace: stackTrace,
    );
  }
}