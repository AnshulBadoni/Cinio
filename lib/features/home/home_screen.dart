import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/aniyomi/aniyomi_image_provider.dart';
import '../../core/app_mode.dart';
import '../../core/di/injector.dart';
import '../../core/metadata/title_logo_service.dart';
import '../../core/mihon/mihon_extension_service.dart';
import '../../core/mihon/mihon_image_provider.dart';
import '../../core/mode/content_mode.dart';
import '../../core/mode/content_mode_cubit.dart';
import '../../core/models/episode.dart';
import '../../core/models/home_section.dart';
import '../../core/models/media_detail.dart';
import '../../core/models/media_item.dart';
import '../../core/models/person.dart';
import '../../core/models/provider_info.dart';
import '../../core/models/video_source.dart';
import '../../core/notify/notification_service.dart';
import '../../core/platform/apple_tv.dart';
import '../../core/playback/my_list.dart';
import '../../core/playback/list_status_store.dart';
import '../../core/models/watch_status.dart';
import '../../core/playback/playback_prefs.dart';
import '../../core/playback/resume_store.dart';
import '../../core/playback/title_prefs.dart';
import '../../core/playback/watch_history.dart';
import '../../core/prefs/catalog_source_prefs.dart';
import '../../core/provider/cloudstream_provider.dart';
import '../../core/provider/provider_manager.dart';
import '../../core/reading/read_history.dart';
import '../../core/repository/source_repository.dart';
import '../../core/state/active_source_cubit.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/adaptive_content_row.dart';
import '../../core/ui/content_row.dart';
import '../../core/ui/featured_carousel.dart';
import '../../core/ui/featured_hero.dart';
import '../../core/ui/elastic_scroll_behavior.dart';
import '../../core/ui/list_status_sheet.dart';
import '../../core/ui/media_info_sheet.dart';
import '../../core/ui/people_row.dart';
import '../../core/ui/poster_card.dart';
import '../../core/ui/poster_quick_actions.dart';
import '../../core/ui/row_skeleton.dart';
import '../../core/ui/source_switcher.dart';
import '../../core/update/extension_auto_updater.dart';
import '../announce/announcement_sheet.dart';
import '../auth/auth_cubit.dart';
import '../auth/reconnect.dart';
import '../community/community_sheet.dart';
import '../detail/detail_screen.dart';
import '../history/history_screen.dart';
import '../people/person_page.dart';
import '../player/player_screen.dart';
import '../reader/manga_reader_screen.dart';
import '../reader/novel_reader_screen.dart';
import '../sources/aniyomi_repo_tab.dart' show kAniyomiReposBoxName;
import '../sources/providers_hub_screen.dart';
import '../sources/zangetsu_sources_screen.dart';
import '../update/update_dialog.dart';
import 'continue_section.dart';
import 'cubit/home_cubit.dart';
import 'home_screen_tv.dart';
import 'see_all_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

/// Max entries in the hero metadata LRU. Above this the oldest evicts, so
/// long browsing sessions don't leak `Future<HeroMeta?>` refs indefinitely.
const int _kMetaCacheMax = 50;

/// Sections whose titles match a "people-style" row (case-insensitive).
const Set<String> _kPeopleSectionKeys = {
  'actor',
  'actors',
  'actress',
  'actresses',
  'model',
  'models',
  'cast',
  'casts',
  'performer',
  'performers',
  'voice actor',
  'voice actors',
  'voice cast',
  'staff',
};

/// Sections whose titles indicate studio/channel/logo rows.
const Set<String> _kStudioSectionKeys = {
  'studio',
  'studios',
  'channel',
  'channels',
};

/// Slash-transition animation timing constants.
const double _kSlashPeak = 0.5;
const double _kSlashInEnd = 0.45;
const double _kSlashOutStart = 0.75;
const double _kSlashGlintStart = 0.38;
const double _kSlashGlintEnd = 0.62;

// ─────────────────────────────────────────────────────────────────────────────
// HomeScreen
// ─────────────────────────────────────────────────────────────────────────────

/// Provides the [HomeCubit] and hosts the reactive Home view.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(value: sl<HomeCubit>(), child: const _HomeView());
  }
}

class _HomeView extends StatefulWidget {
  const _HomeView();

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView>
    with SingleTickerProviderStateMixin {
  // Cached services (avoid repeated SL lookups on hot paths).
  final SourceRepository _repo = sl<SourceRepository>();
  final MyListStore _myList = sl<MyListStore>();
  final ListStatusStore _listStatus = sl<ListStatusStore>();
  final ContentModeCubit _modeCubit = sl<ContentModeCubit>();
  final PlaybackPrefs _prefs = sl<PlaybackPrefs>();

  /// Hero metadata LRU cache: key = "sourceId:id".
  final LinkedHashMap<String, Future<HeroMeta?>> _metaCache =
      LinkedHashMap<String, Future<HeroMeta?>>();
  bool _heroPrewarmed = false;
  final ValueNotifier<double> _heroStretch = ValueNotifier<double>(0);

  /// Pagination state — cleared when source switches.
  final Map<String, int> _sectionPages = {};
  final Set<String> _sectionLoading = {};

  /// Cached mode-art lookup. Rebuilt only when history boxes change or
  /// source/mode switches — not per widget rebuild.
  final Map<ContentMode, ({String? cover, Map<String, String>? headers})>
  _modeArtCache = {};

  // Slash transition state.
  late final AnimationController _slashCtrl;
  bool _slashing = false;
  bool _slashSwapped = false;
  ContentMode? _slashTarget;

  static bool _updateChecked = false;

  void rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _slashCtrl =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 600),
          )
          ..addListener(_handleSlashTick)
          ..addStatusListener(_handleSlashStatus);

    if (!isAppleTv) {
      final cubit = context.read<HomeCubit>();
      if (cubit.state.sections == null && !cubit.state.loading) {
        cubit.load();
      }
    }

    if (!_updateChecked && !isAppleTv) {
      _updateChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await maybeShowUpdateDialog(context);
        if (mounted) await maybeShowCommunitySheet(context);
        if (mounted) await maybeShowAnnouncement(context);
      });
      _checkSourceUpdates();
    }
  }

  @override
  void dispose() {
    _slashCtrl.dispose();
    _heroStretch.dispose();
    super.dispose();
  }

  void _handleSlashTick() {
    if (!_slashSwapped &&
        _slashTarget != null &&
        _slashCtrl.value >= _kSlashPeak) {
      _slashSwapped = true;
      _modeCubit.setMode(_slashTarget!);
      _modeArtCache.clear(); // mode changed → art may differ
    }
  }

  void _handleSlashStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() {
        _slashing = false;
        _slashTarget = null;
      });
    }
  }

  // ── Update checks ─────────────────────────────────────────────────────────

  Future<void> _checkSourceUpdates() async {
    final autoUpdate = _prefs.autoUpdateExtensions;
    if (!autoUpdate && !Platform.isAndroid) return;
    await Future<void>.delayed(const Duration(seconds: 4));
    if (!mounted) return;

    if (autoUpdate) {
      final now = DateTime.now().millisecondsSinceEpoch;
      const dayMs = 24 * 60 * 60 * 1000;
      if (now - _prefs.lastExtensionUpdateMs < dayMs) return;
      await _prefs.setLastExtensionUpdateMs(now);
      try {
        final updated = await ExtensionAutoUpdater.run();
        if (updated > 0) {
          await NotificationService.instance.showMessage(
            id: 779100,
            title: 'Extensions updated',
            body:
                '$updated extension${updated == 1 ? '' : 's'} updated to the latest version.',
          );
        }
      } catch (e, s) {
        _logError('auto-update', e, s);
      }
      return;
    }

    try {
      final csManager = sl<CloudStreamManager>();
      final csCount = await csManager.checkAllUpdates();

      var aniCount = 0;
      try {
        final repoUrls = Hive.isBoxOpen(kAniyomiReposBoxName)
            ? Hive.box<String>(kAniyomiReposBoxName).values.toList()
            : const <String>[];
        if (repoUrls.isNotEmpty) {
          aniCount = await sl<AniyomiManager>().checkAllUpdates(repoUrls);
        }
      } catch (e, s) {
        _logError('aniyomi-update-check', e, s);
      }

      final total = csCount + aniCount;
      if (total > 0 && csManager.notifyUpdates) {
        await NotificationService.instance.showSourceUpdates(count: total);
      }
    } catch (e, s) {
      _logError('cs-update-check', e, s);
    }
  }

  void _logError(String tag, Object e, StackTrace s) {
    developer.log(
      'Home[$tag] error',
      error: e,
      stackTrace: s,
      name: 'HomeScreen',
    );
  }

  // ── Hero metadata (LRU-cached) ────────────────────────────────────────────

  Future<HeroMeta?> _heroMeta(MediaItem m) {
    final key = '${m.sourceId}:${m.id}';
    final existing = _metaCache.remove(key);
    if (existing != null) {
      _metaCache[key] = existing; // move to MRU
      return existing;
    }
    final future = _loadHeroMeta(m);
    _metaCache[key] = future;
    if (_metaCache.length > _kMetaCacheMax) {
      _metaCache.remove(_metaCache.keys.first);
    }
    return future;
  }

  Future<HeroMeta?> _loadHeroMeta(MediaItem m) async {
    final d = await _detailOf(m.url, m.sourceId);
    if (d == null) {
      // Catalog items already carry browse-time metadata. Do not make the hero
      // blank simply because resolving a full detail object would be expensive.
      if (m.genres.isEmpty && m.year == null && m.rating == null) return null;
      return HeroMeta(
        genres: m.genres,
        year: m.year,
        rating: m.rating,
      );
    }
    return HeroMeta(
      genres: d.genres,
      episodeCount: d.episodes.length,
      year: d.year ?? m.year,
      rating: d.rating ?? m.rating,
    );
  }

  void _prewarmHeroMeta(List<MediaItem> items) {
    if (_heroPrewarmed || items.isEmpty) return;
    _heroPrewarmed = true;
    _heroMeta(items.first);
    sl<TitleLogoService>().prefetch(items);
  }

  // ── Detail / navigation helpers ───────────────────────────────────────────

  Future<MediaDetail?> _detailOf(String url, String sourceId) async {
    try {
      if (sourceId == 'tmdb:catalog' || sourceId.startsWith('tpdb:')) {
        return null;
      }
      return await _repo.detail(url, sourceId: sourceId);
    } catch (e, s) {
      _logError('detailOf', e, s);
      return null;
    }
  }

  Future<void> _openDetail(
    MediaItem item, {
    DetailTrailerContext? trailerContext,
  }) async {
    if (!mounted) return;
    await Navigator.push(
      context,
      DetailScreen.route(item, trailerContext: trailerContext),
    );
    if (mounted) setState(() {});
  }

  String _typeLabel(ProviderType t) => switch (t) {
    ProviderType.movie => 'Movie',
    ProviderType.anime => 'Anime',
    ProviderType.manga => 'Manga',
    ProviderType.novel => 'Novel',
  };

  // ── Poster quick actions ─────────────────────────────────────────────────

  Future<void> _showQuickActions(MediaItem item, String heroTag) async {
    final history = sl<WatchHistory>()
        .all()
        .where((e) => e.sourceId == item.sourceId &&
            (e.showId == item.url || e.showUrl == item.url))
        .where((e) => !e.finished)
        .fold<HistoryEntry?>(
          null,
          (best, e) => best == null || e.updatedAt > best.updatedAt ? e : best,
        );
    final watched = _listStatus.statusOf(item) == WatchStatus.completed;
    final inLibrary = _myList.contains(item) || _listStatus.statusOf(item) != null;
    final playLabel = history == null
        ? null
        : 'Resume ${((history.progress * 100).round()).clamp(1, 99)}%';

    if (!mounted) return;
    await showPosterQuickActions(
      context,
      item: item,
      heroTag: heroTag,
      playLabel: playLabel,
      inLibrary: inLibrary,
      watched: watched,
      onPlay: () => _playFeatured(item),
      onInfo: () => _openDetail(item),
      onMarkWatched: () async {
        if (!_myList.contains(item)) await _myList.add(item);
        await _listStatus.setStatus(item, WatchStatus.completed);
        await _myList.pushStatus(item);
        if (mounted) setState(() {});
      },
      onToggleLibrary: () async {
        await _myList.toggle(item);
        if (!_myList.contains(item)) {
          await _listStatus.remove(item);
        }
        if (mounted) setState(() {});
        return _myList.contains(item);
      },
    );
  }

  String _posterHeroTag(HomeSection section, int index, MediaItem item) =>
      'home-poster:${identityHashCode(section)}:$index:${item.sourceId}:${item.id}';

  // ── Info sheets ───────────────────────────────────────────────────────────

  Future<void> _showContinueQuickActions(HistoryEntry entry) async {
    final item = MediaItem(
      id: entry.showId,
      title: entry.showTitle,
      url: entry.showUrl,
      sourceId: entry.sourceId,
      cover: entry.cover,
      coverHeaders: entry.coverHeaders,
      type: ProviderType.movie,
      malId: entry.malId,
      tmdbId: _tmdbIdFromHistory(entry),
      tmdbIsTv: entry.sourceId == 'tmdb:catalog' && entry.showUrl.contains('/tv/'),
    );
    final heroTag =
        'continue-poster:${entry.sourceId}:${entry.showId}:${entry.episodeId}';
    final watched = _listStatus.statusOf(item) == WatchStatus.completed ||
        entry.finished;
    final inLibrary = _myList.contains(item) || _listStatus.statusOf(item) != null;
    final playLabel = entry.finished
        ? 'Watch Again'
        : 'Resume ${((entry.progress * 100).round()).clamp(1, 99)}%';

    if (!mounted) return;
    await showPosterQuickActions(
      context,
      item: item,
      heroTag: heroTag,
      playLabel: playLabel,
      inLibrary: inLibrary,
      watched: watched,
      onPlay: () => _resume(entry),
      onInfo: () => _openDetail(item),
      onMarkWatched: () async {
        if (!_myList.contains(item)) await _myList.add(item);
        await _listStatus.setStatus(item, WatchStatus.completed);
        await _myList.pushStatus(item);
        if (mounted) setState(() {});
      },
      onToggleLibrary: () async {
        await _myList.toggle(item);
        if (!_myList.contains(item)) await _listStatus.remove(item);
        if (mounted) setState(() {});
        return _myList.contains(item);
      },
    );
  }

  Future<void> _showContinueReadingInfo(ReadEntry entry) async {
    final item = MediaItem(
      id: entry.showId,
      title: entry.title,
      cover: entry.cover,
      url: entry.showId,
      type: entry.type,
      sourceId: entry.sourceId,
    );
    final heroTag =
        'continue-reading-poster:${entry.sourceId}:${entry.showId}:${entry.chapterId}';
    final inLibrary = _myList.contains(item) || _listStatus.statusOf(item) != null;
    final pct = entry.total > 0 ? ((entry.pos / entry.total) * 100).round() : 0;
    final playLabel = pct > 0 ? 'Resume $pct%' : 'Read';

    if (!mounted) return;
    await showPosterQuickActions(
      context,
      item: item,
      heroTag: heroTag,
      playLabel: playLabel,
      inLibrary: inLibrary,
      watched: false,
      onPlay: () => _resumeReading(entry),
      onInfo: () => _openDetail(item),
      onMarkWatched: () async {
        if (!_myList.contains(item)) await _myList.add(item);
        await _listStatus.setStatus(item, WatchStatus.completed);
        await _myList.pushStatus(item);
        if (mounted) setState(() {});
      },
      onToggleLibrary: () async {
        await _myList.toggle(item);
        if (!_myList.contains(item)) await _listStatus.remove(item);
        if (mounted) setState(() {});
        return _myList.contains(item);
      },
    );
  }

  void _showInfo(MediaItem item) {
    showMediaInfoSheet(
      context,
      title: item.title,
      englishTitle: item.englishTitle,
      cover: item.cover,
      headers: item.coverHeaders,
      typeLabel: _typeLabel(item.type),
      subCount: item.subCount,
      dubCount: item.dubCount,
      detail: _detailOf(item.url, item.sourceId),
      inMyList: _myList.contains(item),
      onPlay: () => _playFeatured(item),
      onOpenDetail: () => _openDetail(item),
      onToggleMyList: () async {
        await showListStatusSheet(
          context,
          item: item,
          onChanged: () {
            if (mounted) setState(() {});
          },
        );
        return _myList.contains(item);
      },
    );
  }


  // ── Playback / resume ─────────────────────────────────────────────────────

  Future<void> _playFeatured(MediaItem item) async {
    if (!mounted) return;
    if (_modeCubit.state.isReading) {
      _openDetail(item);
      return;
    }
    final category =
        sl<TitlePrefsStore>().category(item.sourceId, item.url) ??
        _prefs.defaultCategory;
    final isCatalog = item.sourceId == 'tmdb:catalog' || item.sourceId.startsWith('tpdb:');

    Future<List<Episode>> resolveEpisodes() async {
      if (isCatalog) {
        final resolved = await _repo.resolveCatalogTitle(item, category: category);
        if (resolved != null && resolved.detail.episodes.isNotEmpty) {
          return resolved.detail.episodes;
        }
        return [Episode(id: item.id, title: item.title, number: 1, url: item.url)];
      }
      try {
        final eps = await _repo.episodes(item.url, sourceId: item.sourceId);
        if (eps.isNotEmpty) return eps;
      } catch (_) {}
      return [Episode(id: item.id, title: item.title, number: 1, url: item.url)];
    }

    Future<List<VideoSource>> resolveVideoSources(String u) async {
      if (isCatalog) {
        final resolved = await _repo.resolveCatalogTitle(item, category: category);
        if (resolved != null) {
          String targetUrl = resolved.item.url;
          for (final ep in resolved.detail.episodes) {
            if (ep.url == u || ep.id == u) {
              targetUrl = ep.url;
              break;
            }
          }
          return _repo.sources(targetUrl, sourceId: resolved.item.sourceId, fast: true);
        }
      }
      return _repo.sources(u, sourceId: item.sourceId, fast: true);
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          sourceId: item.sourceId,
          episodesResolver: resolveEpisodes,
          resume: sl<ResumeStore>(),
          resolveSources: resolveVideoSources,
          history: sl<WatchHistory>(),
          showTitle: item.title,
          cover: item.cover,
          coverHeaders: item.coverHeaders,
          showUrl: item.url,
          category: category,
          malId: item.malId,
          scrobbleTitle: item.type == ProviderType.anime ? item.title : null,
          tmdbId: item.tmdbId,
          tmdbIsTv: item.tmdbIsTv,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  int? _tmdbIdFromHistory(HistoryEntry e) {
    if (e.sourceId != 'tmdb:catalog') return null;
    final match = RegExp(r'/((?:tv|movie))/([0-9]+)').firstMatch(e.showUrl);
    return match == null ? null : int.tryParse(match.group(2)!);
  }

  Future<void> _resume(HistoryEntry e) async {
    final isCatalog = e.sourceId == 'tmdb:catalog' || e.sourceId.startsWith('tpdb:');
    final mediaItem = MediaItem(
      id: e.showId,
      title: e.showTitle,
      url: e.showUrl,
      sourceId: e.sourceId,
      cover: e.cover,
      coverHeaders: e.coverHeaders,
      type: ProviderType.movie,
      malId: e.malId,
      tmdbIsTv: e.sourceId == 'tmdb:catalog' && e.showUrl.contains('/tv/'),
      tmdbId: _tmdbIdFromHistory(e),
    );

    Future<List<Episode>> resolveEpisodes() async {
      if (isCatalog) {
        final resolved = await _repo.resolveCatalogTitle(mediaItem, category: e.category);
        if (resolved != null && resolved.detail.episodes.isNotEmpty) {
          return resolved.detail.episodes;
        }
        throw StateError('Could not resolve a streaming provider for ${e.showTitle}');
      }
      try {
        final eps = await _repo.episodes(
          e.showUrl,
          category: e.category,
          sourceId: e.sourceId,
        );
        if (eps.isNotEmpty) return eps;
      } catch (_) {}
      return [
        Episode(
          id: e.episodeId,
          title: e.showTitle,
          number: e.episodeNumber ?? 1,
          url: e.episodeUrl.isNotEmpty ? e.episodeUrl : e.showUrl,
        ),
      ];
    }

    Future<List<VideoSource>> resolveVideoSources(String u) async {
      if (isCatalog) {
        final resolved = await _repo.resolveCatalogTitle(mediaItem, category: e.category);
        if (resolved != null) {
          String targetUrl = resolved.item.url;
          for (final ep in resolved.detail.episodes) {
            if (ep.url == u ||
                ep.id == u ||
                (e.episodeNumber != null && ep.number == e.episodeNumber)) {
              targetUrl = ep.url;
              break;
            }
          }
          return _repo.sources(targetUrl, sourceId: resolved.item.sourceId, fast: true);
        }
      }
      return _repo.sources(u, sourceId: e.sourceId, fast: true);
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          sourceId: e.sourceId,
          episodesResolver: resolveEpisodes,
          resumeEpisodeId: e.episodeId,
          resumeEpisodeNumber: e.episodeNumber,
          resumePosition: e.position,
          resume: sl<ResumeStore>(),
          resolveSources: resolveVideoSources,
          history: sl<WatchHistory>(),
          showTitle: e.showTitle,
          cover: e.cover,
          coverHeaders: e.coverHeaders,
          showUrl: e.showUrl,
          category: e.category,
          malId: e.malId,
          scrobbleTitle: e.malId != null ? e.showTitle : null,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _resumeReading(ReadEntry e) async {
    final chapter = Episode(
      id: e.chapterId,
      title: e.chapterNumber != null
          ? 'Chapter ${e.chapterNumber!.toInt()}'
          : 'Chapter',
      number: e.chapterNumber,
      url: e.chapterUrl,
    );
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => readerFor(e, chapter)),
    );
    if (mounted) setState(() {});
  }

  // ── People / studio navigation ────────────────────────────────────────────

  Future<void> _openPerformer(MediaItem performer) async {
    final raw = performer.id.replaceFirst('tpdb:performer:', '');
    final numeric = int.tryParse(raw) ?? 0;
    await Navigator.of(context).push(
      PersonPage.route(
        PersonRef(
          id: numeric,
          externalId: raw,
          source: PersonSource.thePornDbPerformer,
          name: performer.title,
          photo: performer.cover,
        ),
        sourceId: performer.sourceId,
      ),
    );
  }

  Future<void> _openStudio(MediaItem studio) async {
    final raw = studio.id.replaceFirst('tpdb:studio:', '');
    final numeric = int.tryParse(raw) ?? 0;
    await Navigator.of(context).push(
      PersonPage.route(
        PersonRef(
          id: numeric,
          externalId: raw,
          source: PersonSource.thePornDbStudio,
          name: studio.title,
          photo: studio.cover,
        ),
        sourceId: studio.sourceId,
      ),
    );
  }

  // ── Section classifiers (pure — inlined string-set lookups) ───────────────

  static bool _isPeopleSection(String title) {
    final t = title.trim().toLowerCase();
    if (_kPeopleSectionKeys.contains(t)) return true;
    for (final label in _kPeopleSectionKeys) {
      if (t.startsWith('$label ') ||
          t.startsWith('$label:') ||
          t.startsWith('$label -')) {
        return true;
      }
    }
    return false;
  }

  static bool _isStudioSection(String title) {
    final t = title.trim().toLowerCase();
    if (_kStudioSectionKeys.contains(t)) return true;
    for (final label in _kStudioSectionKeys) {
      if (t.startsWith('$label ') ||
          t.startsWith('$label:') ||
          t.startsWith('$label -')) {
        return true;
      }
    }
    return false;
  }

  // ── Pagination ────────────────────────────────────────────────────────────

  Future<void> _loadMoreForSection(HomeSection section) async {
    if (section.more == null) return;
    final key = section.title;
    if (_sectionLoading.contains(key)) return;
    _sectionLoading.add(key);
    final nextPage = (_sectionPages[key] ?? 1) + 1;
    try {
      final newItems = await _repo.browseMore(section.more!, nextPage);
      if (newItems.isNotEmpty && mounted) {
        _sectionPages[key] = nextPage;
        // Delegate to cubit so state stays immutable and reactive.
        context.read<HomeCubit>().appendItems(section.title, newItems);
      }
    } catch (e, s) {
      _logError('loadMoreForSection', e, s);
    } finally {
      _sectionLoading.remove(key);
    }
  }

  // ── Section rows ──────────────────────────────────────────────────────────

  Widget _sectionRow(HomeSection section, String cardStyle) {
    if (_isPeopleSection(section.title)) {
      return PeopleRow(
        title: section.title,
        items: section.items,
        onSeeAll: () => _openSeeAll(section),
        onLoadMore: section.more != null
            ? () => _loadMoreForSection(section)
            : null,
        onTap: (item) {
          if (item.sourceId == 'tpdb:performer') {
            _openPerformer(item);
          } else if (item.sourceId == 'tpdb:studio') {
            _openStudio(item);
          } else {
            _openDetail(item, trailerContext: DetailTrailerContext.model);
          }
        },
        onLongPress: _showInfo,
      );
    }
    if (_isStudioSection(section.title)) return _studioRow(section);

    if (cardStyle == 'poster') {
      return _fixedContentRow(section, landscape: false);
    }
    if (cardStyle == 'landscape') {
      return _fixedContentRow(section, landscape: true);
    }

    return AdaptiveContentRow(
      title: section.title,
      items: section.items,
      onSeeAll: () => _openSeeAll(section),
      onTap: _openDetail,
      onLongPress: (item) => _showQuickActions(
        item,
        _posterHeroTag(section, section.items.indexOf(item), item),
      ),
      heroTagBuilder: (item, index) => _posterHeroTag(section, index, item),
    );
  }

  Widget _studioRow(HomeSection section) {
    const width = 160.0;
    const rowHeight = 188.0;
    return ContentRow(
      title: section.title,
      itemWidth: width,
      itemHeight: rowHeight,
      itemCount: section.items.length,
      onSeeAll: () => _openSeeAll(section),
      itemBuilder: (c, i) {
        final item = section.items[i];
        return SizedBox(
          height: rowHeight,
          child: PosterCard(
            title: item.title,
            imageUrl: item.cover,
            headers: item.coverHeaders,
            cellWidth: width,
            qualityBadge: item.quality,
            dubBadge: item.dubBadge,
            heroTag: _posterHeroTag(section, i, item),
            completed: _listStatus.statusOf(item) == WatchStatus.completed,
            onTap: () {
              if (item.sourceId == 'tpdb:studio') {
                _openStudio(item);
              } else {
                _openDetail(item, trailerContext: DetailTrailerContext.studio);
              }
            },
            onLongPress: () => _showQuickActions(item, _posterHeroTag(section, i, item)),
          ),
        );
      },
    );
  }

  Widget _fixedContentRow(HomeSection section, {required bool landscape}) {
    final width = landscape ? 210.0 : 140.0;
    const height = 236.0;
    return ContentRow(
      title: section.title,
      itemWidth: width,
      itemHeight: height,
      itemCount: section.items.length,
      onSeeAll: () => _openSeeAll(section),
      itemBuilder: (c, i) {
        final item = section.items[i];
        return PosterCard(
          title: item.title,
          imageUrl: item.cover,
          headers: item.coverHeaders,
          cellWidth: width,
          qualityBadge: item.quality,
          dubBadge: item.dubBadge,
          completed: _listStatus.statusOf(item) == WatchStatus.completed,
          heroTag: _posterHeroTag(section, i, item),
          onTap: () => _openDetail(item),
          onLongPress: () => _showQuickActions(item, _posterHeroTag(section, i, item)),
        );
      },
    );
  }

  // ── History / SeeAll ──────────────────────────────────────────────────────

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HistoryScreen(initialIndex: _modeCubit.state.index),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  DetailTrailerContext? _trailerContextForSection(HomeSection section) {
    if (_isPeopleSection(section.title)) return DetailTrailerContext.model;
    if (_isStudioSection(section.title)) return DetailTrailerContext.studio;
    return null;
  }

  void _openSeeAll(HomeSection section) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SeeAllScreen(
          title: section.title,
          items: section.items,
          onTap: (item) {
            if (item.sourceId == 'tpdb:performer') {
              _openPerformer(item);
            } else if (item.sourceId == 'tpdb:studio') {
              _openStudio(item);
            } else {
              _openDetail(
                item,
                trailerContext: _trailerContextForSection(section),
              );
            }
          },
          onLongPress: _showInfo,
          onLoadMore: section.more == null
              ? null
              : (page) => _repo.browseMore(section.more!, page),
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  // ── Reconnect banner ──────────────────────────────────────────────────────

  Widget _reconnectBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            final ok = await showReconnectDialog(context) ?? false;
            if (ok && mounted) context.read<HomeCubit>().load();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                 Icon(
                  Icons.sync_problem_rounded,
                  color: AppColors.accent,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Reconnect to sync', style: AppText.body),
                      Text(
                        'Your session expired — tap to sign in and sync your library.',
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Mode cards ────────────────────────────────────────────────────────────

  Widget _modeCards() {
    return BlocBuilder<ContentModeCubit, ContentMode>(
      bloc: _modeCubit,
      builder: (context, current) {
        final others = ContentMode.values
            .where((m) => m != current)
            .toList(growable: false);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Row(
            children: [
              for (var i = 0; i < others.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: _modeCard(others[i])),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _modeCard(ContentMode m) {
    final cover = _modeArt(m);
    return GestureDetector(
      onTap: _slashing ? null : () => _enterMode(m),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 52,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _modeArtBg(cover),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xCC000000), Color(0x55000000)],
                  ),
                ),
              ),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(m.icon, size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      m.label,
                      style: AppText.body.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        shadows: const [
                          Shadow(color: Colors.black, blurRadius: 6),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Cached mode-art lookup. Only re-scans history when the cache is invalidated
  /// (source switch, mode swap, or history box change via ValueListenable).
  ({String? cover, Map<String, String>? headers}) _modeArt(ContentMode m) {
    final cached = _modeArtCache[m];
    if (cached != null) return cached;
    final result = _computeModeArt(m);
    _modeArtCache[m] = result;
    return result;
  }

  ({String? cover, Map<String, String>? headers}) _computeModeArt(
    ContentMode m,
  ) {
    if (m == ContentMode.anime) {
      if (!Hive.isBoxOpen(WatchHistory.boxName)) {
        return (cover: null, headers: null);
      }
      for (final e in sl<WatchHistory>().all()) {
        final c = e.thumbnail ?? e.cover;
        if (c != null && c.isNotEmpty) {
          return (cover: c, headers: e.coverHeaders);
        }
      }
      return (cover: null, headers: null);
    }
    if (!Hive.isBoxOpen(ReadHistory.boxName)) {
      return (cover: null, headers: null);
    }
    final type = m == ContentMode.manga
        ? ProviderType.manga
        : ProviderType.novel;
    for (final e in sl<ReadHistory>().all()) {
      if (e.type == type && (e.cover?.isNotEmpty ?? false)) {
        return (cover: e.cover, headers: e.coverHeaders);
      }
    }
    return (cover: null, headers: null);
  }

  Widget _modeArtBg(({String? cover, Map<String, String>? headers}) art) {
    final url = art.cover;
    if (url == null || url.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.surface2, AppColors.surface],
          ),
        ),
      );
    }
    if (art.headers?['x-ani-src'] != null ||
        art.headers?['x-mihon-src'] != null) {
      return Image(
        image: ResizeImage(
          art.headers?['x-ani-src'] != null
              ? AniyomiImage(int.parse(art.headers!['x-ani-src']!), url)
              : MihonImage(int.parse(art.headers!['x-mihon-src']!), url),
          width: 420,
        ),
        fit: BoxFit.cover,
        alignment: const Alignment(0, -0.2),
        errorBuilder: (_, __, ___) => ColoredBox(color: AppColors.surface2),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: art.headers,
      memCacheWidth: 420,
      fit: BoxFit.cover,
      alignment: const Alignment(0, -0.2),
      placeholder: (_, __) => ColoredBox(color: AppColors.surface2),
      errorWidget: (_, __, ___) => ColoredBox(color: AppColors.surface2),
    );
  }

  void _enterMode(ContentMode m) {
    if (_slashing) return;
    setState(() {
      _slashing = true;
      _slashSwapped = false;
      _slashTarget = m;
    });
    _slashCtrl.forward(from: 0);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (sl<AppMode>().isTv) return const HomeScreenTv();

    return BlocListener<ActiveSourceCubit, String>(
      listenWhen: (prev, curr) => prev != curr,
      listener: (context, _) {
        if (!mounted) return;
        _metaCache.clear();
        _sectionPages.clear();
        _sectionLoading.clear();
        _modeArtCache.clear();
        _heroPrewarmed = false;
        context.read<HomeCubit>().load(reset: true);
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Stack(
          children: [
            RefreshIndicator(
              color: AppColors.accent,
              onRefresh: () => context.read<HomeCubit>().load(),
              child: _HomeScrollView(stretch: _heroStretch),
            ),
            if (_slashing) _SlashOverlay(controller: _slashCtrl),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scroll view — extracted so BlocBuilder scope stays tight
// ─────────────────────────────────────────────────────────────────────────────

class _HomeScrollView extends StatelessWidget {
  const _HomeScrollView({required this.stretch});

  final ValueNotifier<double> stretch;

  @override
  Widget build(BuildContext context) {
    final state = context
        .select<AuthCubit, ({bool loggedIn, bool needsReconnect})>(
          (c) => (
            loggedIn: c.state.isLoggedIn,
            needsReconnect: c.state.needsReconnect,
          ),
        );
    return BlocBuilder<HomeCubit, HomeState>(
      buildWhen: (prev, curr) =>
          prev.loading != curr.loading ||
          prev.sections != curr.sections ||
          prev.heroItems != curr.heroItems ||
          prev.cloudflareUrl != curr.cloudflareUrl,
      builder: (context, homeState) {
        final view = context.findAncestorStateOfType<_HomeViewState>()!;
        final sections = homeState.sections ?? const <HomeSection>[];
        final firstId = sections.isNotEmpty
            ? (sections.first.more?.sourceId ?? '')
            : '';
        final firstIsNativeCatalog =
            firstId.startsWith('ani:') || firstId.startsWith('mihon:');
        final rowSections = (sections.length > 1 && !firstIsNativeCatalog)
            ? sections.sublist(1)
            : sections;
        final showSkeletons = homeState.loading;
        final loadedEmpty =
            !homeState.loading &&
            homeState.sections != null &&
            homeState.sections!.isEmpty;
        final activeId = context.read<ActiveSourceCubit>().state;
        final mode = sl<ContentModeCubit>().state;
        final noSourceForMode = !hasSourcesFor(mode);
        final activeSourceValid =
            activeId.isNotEmpty && view._repo.hasSource(activeId);
        final showSourceSwitcher = !noSourceForMode;
        final cardStyle = view._prefs.homeCardStyle;

        return ScrollConfiguration(
          behavior: const CinioBounceOnlyScrollBehavior(),
          child: NotificationListener<OverscrollNotification>(
            onNotification: (notification) {
              if (notification.depth == 0 &&
                  notification.overscroll < 0 &&
                  notification.metrics.pixels <= 0) {
                stretch.value = (stretch.value - notification.overscroll).clamp(0.0, 150.0);
              }
              return false;
            },
            child: NotificationListener<ScrollEndNotification>(
              onNotification: (_) {
                stretch.value = 0;
                return false;
              },
              child: CustomScrollView(
            slivers: [
            _HomeHeroSliver(
              heroItems: homeState.heroItems,
              noSourceForMode: noSourceForMode,
              activeSourceValid: activeSourceValid,
              showSourceSwitcher: showSourceSwitcher,
            ),
            if (noSourceForMode)
              SliverToBoxAdapter(
                child: HomeLoadedEmptyView(
                  mode: mode,
                  sourceName: 'No provider selected',
                  onRetry: () => context.read<HomeCubit>().load(reset: true),
                  onInstallSources: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ProvidersHubScreen(),
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(child: view._modeCards()),
            if (state.needsReconnect)
              SliverToBoxAdapter(child: view._reconnectBanner()),
            ContinueSection(
              loggedIn: state.loggedIn,
              onResume: view._resume,
              onLongPress: view._showContinueQuickActions,
              onSeeAll: view._openHistory,
              onResumeReading: view._resumeReading,
              onLongPressReading: view._showContinueReadingInfo,
            ),
            if (showSkeletons && !noSourceForMode)
              const SliverToBoxAdapter(
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: RowSkeleton(),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: RowSkeleton(),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: RowSkeleton(),
                    ),
                  ],
                ),
              )
            else if (loadedEmpty && !noSourceForMode)
              SliverFillRemaining(
                hasScrollBody: false,
                child: HomeLoadedEmptyView(
                  mode: mode,
                  sourceName: switch (sl<CatalogSourcePrefs>().source) {
                    CatalogSource.provider =>
                      sl<SourceRepository>().displayName(activeId),
                    CatalogSource.tmdb => 'TMDB',
                    CatalogSource.thePornDb => 'ThePornDB',
                    CatalogSource.mixed => 'Catalogs',
                  },
                  onRetry: () => context.read<HomeCubit>().load(reset: true),
                  onInstallSources: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ProvidersHubScreen(),
                    ),
                  ),
                  cloudflareUrl: homeState.cloudflareUrl,
                  onSolveCloudflare: homeState.cloudflareUrl == null
                      ? null
                      : () async {
                          await MihonExtensionService.solveCloudflare(
                            homeState.cloudflareUrl!,
                          );
                          if (context.mounted) {
                            context.read<HomeCubit>().load(reset: true);
                          }
                        },
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (c, i) => Padding(
                    key: ValueKey('row-${rowSections[i].title}'),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: view._sectionRow(rowSections[i], cardStyle),
                  ),
                  childCount: rowSections.length,
                ),
              ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 18,
              ),
            ),
          ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero / header section — isolated so hero-only state changes don't rebuild rows
// ─────────────────────────────────────────────────────────────────────────────

class _HomeHeroSliver extends StatelessWidget {
  const _HomeHeroSliver({
    required this.heroItems,
    required this.noSourceForMode,
    required this.activeSourceValid,
    required this.showSourceSwitcher,
  });

  final List<MediaItem> heroItems;
  final bool noSourceForMode;
  final bool activeSourceValid;
  final bool showSourceSwitcher;

  @override
  Widget build(BuildContext context) {
    final view = context.findAncestorStateOfType<_HomeViewState>()!;
    final hasHero = heroItems.isNotEmpty;
    if (hasHero) view._prewarmHeroMeta(heroItems);

    if (hasHero && !noSourceForMode && activeSourceValid) {
      return SliverAppBar(
        pinned: false,
        primary: false,
        toolbarHeight: 0,
        expandedHeight: kHeroHeight,
        collapsedHeight: 0,
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        stretch: true,
        stretchTriggerOffset: 120,
        flexibleSpace: FlexibleSpaceBar(
          collapseMode: CollapseMode.pin,
          stretchModes: const [
            StretchMode.zoomBackground,
          ],
          background: Stack(
            fit: StackFit.expand,
            children: [
              FeaturedCarousel(
                items: heroItems,
                reading: sl<ContentModeCubit>().state.isReading,
                inList: view._myList.contains,
                onPlay: view._playFeatured,
                onInfo: view._openDetail,
                onToggleList: (item) => showListStatusSheet(
                  context,
                  item: item,
                  onChanged: () {
                    view.rebuild();
                  },
                ),
                meta: view._heroMeta,
                style: HeroTransition.cinematic,
                fullBleed: true,
                height: kHeroHeight,
                stretch: view._heroStretch,
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 10,
                right: 16,
                child: BlocBuilder<ActiveSourceCubit, String>(
                  builder: (context, id) => SourceSwitcher(
                    currentId: id,
                    compact: true,
                    onChanged: (newId) =>
                        context.read<ActiveSourceCubit>().setSource(newId),
                    onInstallSources: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const ZangetsuSourcesScreen(openToRepos: true),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (showSourceSwitcher) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 16,
            bottom: 8,
          ),
          child: Align(
            alignment: Alignment.centerRight,
            child: BlocBuilder<ActiveSourceCubit, String>(
              builder: (context, id) => SourceSwitcher(
                currentId: id,
                compact: false,
                onChanged: (newId) =>
                    context.read<ActiveSourceCubit>().setSource(newId),
                onInstallSources: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const ZangetsuSourcesScreen(openToRepos: true),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return const SliverToBoxAdapter(child: SizedBox.shrink());
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Slash overlay — extracted into its own widget for testability
// ─────────────────────────────────────────────────────────────────────────────

class _SlashOverlay extends StatelessWidget {
  const _SlashOverlay({required this.controller});

  final AnimationController controller;

  static const double _logoSize = 152.0;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final t = controller.value;
            final scrim = (1 - (t * 2 - 1).abs()).clamp(0.0, 1.0);
            final inP = (t / _kSlashInEnd).clamp(0.0, 1.0);
            final outP = ((t - _kSlashOutStart) / (1.0 - _kSlashOutStart))
                .clamp(0.0, 1.0);
            final scale =
                0.62 + 0.38 * Curves.easeOutBack.transform(inP) + outP * 0.12;
            final logoOpacity =
                (t < 0.12
                        ? t / 0.12
                        : t > 0.8
                        ? (1 - t) / 0.2
                        : 1.0)
                    .clamp(0.0, 1.0);
            final glintOn = t > _kSlashGlintStart && t < _kSlashGlintEnd;
            final glintP =
                ((t - _kSlashGlintStart) /
                        (_kSlashGlintEnd - _kSlashGlintStart))
                    .clamp(0.0, 1.0);
            final glintPulse = (1 - (glintP * 2 - 1).abs()).clamp(0.0, 1.0);

            return Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: AppColors.bg.withValues(alpha: scrim * 0.92),
                  ),
                ),
                Center(
                  child: Opacity(
                    opacity: logoOpacity,
                    child: Transform.scale(
                      scale: scale,
                      child: SizedBox(
                        width: _logoSize,
                        height: _logoSize,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: _logoSize * 0.8,
                              height: _logoSize * 0.8,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.accent.withValues(
                                        alpha: 0.5 * scrim,
                                      ),
                                      blurRadius: 48,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Image.asset(
                              'assets/icon/logo_mark.png',
                              width: _logoSize,
                              height: _logoSize,
                            ),
                            if (glintOn)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(26),
                                child: SizedBox(
                                  width: _logoSize,
                                  height: _logoSize,
                                  child: Transform.translate(
                                    offset: Offset(
                                      (glintP * 2 - 1) * _logoSize * 0.9,
                                      0,
                                    ),
                                    child: Transform.rotate(
                                      angle: -0.5,
                                      child: Container(
                                        width: 34,
                                        height: _logoSize * 2,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.white.withValues(alpha: 0),
                                              Colors.white.withValues(
                                                alpha: 0.85 * glintPulse,
                                              ),
                                              Colors.white.withValues(alpha: 0),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty-state widgets (unchanged UI, extracted for clarity)
// ─────────────────────────────────────────────────────────────────────────────

class HomeLoadedEmptyView extends StatelessWidget {
  const HomeLoadedEmptyView({
    super.key,
    required this.mode,
    required this.sourceName,
    required this.onRetry,
    required this.onInstallSources,
    this.cloudflareUrl,
    this.onSolveCloudflare,
  });

  final ContentMode mode;
  final String sourceName;
  final VoidCallback onRetry;
  final VoidCallback onInstallSources;
  final String? cloudflareUrl;
  final Future<void> Function()? onSolveCloudflare;

  @override
  Widget build(BuildContext context) {
    if (cloudflareUrl != null && onSolveCloudflare != null) {
      return _SourceUnavailable(
        sourceName: sourceName,
        onRetry: onRetry,
        onSolveCloudflare: onSolveCloudflare,
      );
    }
    if (!hasSourcesFor(mode)) {
      return _NoSourcesGuide(mode: mode, onBrowse: onInstallSources);
    }
    return _SourceUnavailable(sourceName: sourceName, onRetry: onRetry);
  }
}

class _NoSourcesGuide extends StatelessWidget {
  const _NoSourcesGuide({required this.mode, required this.onBrowse});

  final ContentMode mode;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final label = mode.label;
    final (icon, noun) = switch (mode) {
      ContentMode.anime => (Icons.live_tv_rounded, 'shows'),
      ContentMode.manga => (Icons.auto_stories_rounded, 'manga'),
      ContentMode.novel => (Icons.menu_book_rounded, 'novels'),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 24, 40, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 46, color: AppColors.accent),
            ),
            const SizedBox(height: 22),
            Text(
              'No $label sources yet',
              textAlign: TextAlign.center,
              style: AppText.headline.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 10),
            Text(
              'Add a source from Providers and your $noun will show up here.',
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: onBrowse,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Browse sources'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                textStyle: AppText.button.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceUnavailable extends StatelessWidget {
  const _SourceUnavailable({
    required this.sourceName,
    required this.onRetry,
    this.onSolveCloudflare,
  });

  final String sourceName;
  final VoidCallback onRetry;
  final Future<void> Function()? onSolveCloudflare;

  static const Color _cloudflareOrange = Color(0xFFF48120);

  @override
  Widget build(BuildContext context) {
    final isCloudflare = onSolveCloudflare != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 40, 36, 56),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: isCloudflare
                  ? _cloudflareOrange.withValues(alpha: 0.14)
                  : AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCloudflare ? Icons.shield_rounded : Icons.cloud_off_rounded,
              size: 40,
              color: isCloudflare ? _cloudflareOrange : AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isCloudflare
                ? '$sourceName is protected by Cloudflare'
                : "Couldn't load $sourceName",
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            isCloudflare
                ? 'Complete the Cloudflare check once and this source will '
                      'load normally from then on.'
                : "This source isn't responding right now. It may be down or "
                      "blocking requests — try again, or switch to another "
                      "source from the top.",
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),
          if (isCloudflare) ...[
            ElevatedButton.icon(
              onPressed: () => onSolveCloudflare!(),
              icon: const Icon(Icons.shield_rounded, size: 20),
              label: const Text('Solve Cloudflare'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _cloudflareOrange,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 13,
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
            ),
          ] else
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 13,
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Widget readerFor(ReadEntry e, Episode chapter) {
  if (e.type == ProviderType.manga) {
    return MangaReaderScreen(
      sourceId: e.sourceId,
      showId: e.showId,
      showTitle: e.title,
      cover: e.cover,
      chapters: [chapter],
      startIndex: 0,
      resolveChapters: true,
    );
  }
  return NovelReaderScreen(
    sourceId: e.sourceId,
    showId: e.showId,
    showTitle: e.title,
    cover: e.cover,
    chapters: [chapter],
    startIndex: 0,
    resolveChapters: true,
  );
}
