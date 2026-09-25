import 'dart:async';
import 'dart:io';

import 'package:palette_generator/palette_generator.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart' show CupertinoPicker, CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ui/native_cover_provider.dart';
import '../../core/ui/jump_prompt.dart';
import '../../core/util/title_matcher.dart';
import '../../core/app_mode.dart';
import '../../core/cache/app_image_cache.dart';
import '../../core/di/injector.dart';
import '../../core/discord/discord_rpc.dart';
import '../../core/metadata/episode_metadata_service.dart';
import '../../core/metadata/tmdb_discover_service.dart';
import '../../core/metadata/title_logo_service.dart';
import '../../core/notify/cs_notify.dart';
import '../../core/notify/notification_service.dart';
import '../../core/notify/subscription_store.dart';
import '../../core/share/share_link.dart';
import '../../core/download/chapter_download.dart';
import '../../core/download/chapter_download_store.dart';
import '../../core/download/chapter_downloader.dart';
import '../../core/download/download_manager.dart';
import '../../core/download/download_record.dart';
import '../../core/mode/content_mode.dart';
import '../../core/mode/content_mode_cubit.dart';
import '../../core/models/episode.dart';
import '../../core/models/episode_title.dart';
import '../../core/models/media_detail.dart';
import 'chapter_meta.dart';
import '../../core/tv/tv_episode_range_chips.dart';
import 'episode_filter.dart';
import '../../core/models/media_item.dart';
import '../../core/models/media_extras.dart';
import '../../core/models/person.dart';
import '../home/search_screen.dart';
import '../../core/ui/cinio_title_style.dart';
import '../people/person_page.dart';
import '../../core/models/video_source.dart';
import '../../core/models/provider_info.dart';
import '../../core/models/watch_status.dart';
import '../../core/playback/filler_service.dart';
import '../../core/playback/list_status_store.dart';
import '../../core/privacy/incognito_mode.dart';
import '../../core/playback/my_list.dart';
import '../../core/ui/episode_player_sheet.dart';
import '../../core/ui/list_status_sheet.dart';
import '../../core/ui/tracker_list_sheet.dart';
import '../../core/ui/tracker_sync_sheet.dart';
import '../../core/tracker/airing_countdown.dart';
import '../../core/tracker/tracker.dart';
import '../../core/tracker/tracker_binding_store.dart';
import '../../core/tracker/tracker_hub.dart';
import '../../core/playback/playback_prefs.dart';
import '../../core/playback/resume_store.dart';
import '../../core/playback/title_prefs.dart';
import '../../core/playback/watch_history.dart';
import '../../core/provider/cloudstream_provider.dart';
import '../../core/provider/provider_registry.dart';
import '../../core/reading/read_history.dart';
import '../../core/reading/read_store.dart';
import '../../core/repository/source_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/trailer/trailer_service.dart';
import '../../core/tv/tv_back_button.dart';
import '../../core/tv/tv_focusable.dart';
import '../../core/tv/tv_list_focusable.dart';
import '../../core/aniyomi/aniyomi_image_provider.dart';
import '../../core/mihon/mihon_image_provider.dart';
import '../../core/ui/badge.dart';
import '../../core/ui/route_observer.dart';
import '../../core/ui/states.dart';
import '../player/player_screen.dart';
import '../player/tv_playback_launch.dart';
import '../reader/manga_reader_screen.dart';
import '../reader/novel_reader_screen.dart';
import '../trailer/trailer_screen.dart';
import 'cubit/detail_cubit.dart';

part 'detail_hero.dart';
part 'detail_info.dart';
part 'detail_episodes.dart';
part 'detail_sheets.dart';
part 'detail_tabs.dart';
part 'detail_skeleton.dart';

part 'detail_screen_tv.dart';

/// Last-resort friendly name for a [sourceId] that's neither a loaded JS nor CS
/// provider (e.g. its source was uninstalled): drop the `cs:` prefix and the
/// `@version@tag` file-id suffix so the detail screen never shows "cs:X@31".
String _friendlySourceId(String sourceId) {
  var s = sourceId.startsWith('cs:')
      ? sourceId.substring(3)
      : sourceId.startsWith('ani:')
      ? sourceId.substring(4)
      : sourceId;
  final at = s.indexOf('@');
  if (at > 0) s = s.substring(0, at);
  return s;
}

/// "Source · Repo" label for the detail screen, so the user can see which repo
/// a source came from. Falls back to just the name when no repo is resolvable.
String _sourceLabel(String sourceId) {
  if (sourceId.startsWith('ani:')) {
    final name = sl<SourceRepository>().displayName(sourceId);
    return name == sourceId ? _friendlySourceId(sourceId) : name;
  }
  final js = sl<ProviderRegistry>().entryFor(sourceId);
  if (js != null) {
    final name = js.displayName.isNotEmpty ? js.displayName : js.name;
    final repo = _repoLabelFromUrl(js.originRepoUrl);
    return repo != null ? '$name · $repo' : name;
  }
  final cs = sl<CloudStreamManager>().get(sourceId);
  if (cs is CloudStreamProvider) {
    final repo = cs.disambiguate
        ? null
        : sl<CloudStreamManager>().repoNameForSourceId(sourceId);
    return repo != null ? '${cs.displayName} · $repo' : cs.displayName;
  }
  return cs?.displayName ?? _friendlySourceId(sourceId);
}

/// Short repo label from a manifest URL (GitHub repo name, else owner, else
/// host). Null for bundled/blank URLs. Mirrors the source switcher's logic.
String? _repoLabelFromUrl(String? repoUrl) {
  if (repoUrl == null || repoUrl.isEmpty || repoUrl.startsWith('bundled://')) {
    return null;
  }
  try {
    final u = Uri.parse(repoUrl);
    final segs = u.pathSegments.where((s) => s.isNotEmpty).toList();
    if (u.host.contains('github')) {
      if (segs.length >= 2) return segs[1];
      if (segs.isNotEmpty) return segs.first;
    }
    return u.host.isEmpty ? null : u.host;
  } catch (_) {
    return null;
  }
}

Episode _matchTargetEpisode(MediaDetail targetDetail, MediaItem targetItem, Episode origEp) {
  if (targetDetail.episodes.isNotEmpty) {
    for (final candidate in targetDetail.episodes) {
      if (candidate.id == origEp.id) return candidate;
    }
    final wantedSeason = seasonOf(origEp);
    final wantedNumber = origEp.number;
    for (final candidate in targetDetail.episodes) {
      if (candidate.number == wantedNumber &&
          (wantedSeason == null || seasonOf(candidate) == wantedSeason)) {
        return candidate;
      }
    }
    if (wantedNumber != null) {
      for (final candidate in targetDetail.episodes) {
        if (candidate.number == wantedNumber) return candidate;
      }
    }
    return targetDetail.episodes.first;
  }
  return Episode(
    id: targetItem.id,
    number: 1,
    title: targetDetail.title.trim().isNotEmpty ? targetDetail.title : targetItem.title,
    url: targetItem.url,
  );
}

enum DetailTrailerContext { model, studio }

class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key, required this.item, this.trailerContext, this.catalogDetail});
  final MediaItem item;
  final DetailTrailerContext? trailerContext;
  final MediaDetail? catalogDetail;

  static Route<void> route(
    MediaItem item, {
    DetailTrailerContext? trailerContext,
    MediaDetail? catalogDetail,
  }) => PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 340),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, _, _) => DetailScreen(
      item: item,
      trailerContext: trailerContext,
      catalogDetail: catalogDetail,
    ),
    transitionsBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.035),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DetailCubit(
        repo: sl<SourceRepository>(),
        url: item.url,
        sourceId: item.sourceId,
        prefs: sl<TitlePrefsStore>(),
        seedMalId: item.malId,
        seedType: item.type,
        catalogDetail: catalogDetail,
        catalogItem: item,
      )..load(),
      child: _DetailView(
        item: item,
        trailerContext: trailerContext,
        catalogDetail: catalogDetail,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DetailView — StatefulWidget for the scroll-driven app-bar title fade and the
// four-tab layout (Episodes / Cast / Relations / Details).
// ─────────────────────────────────────────────────────────────────────────────

class _DetailView extends StatefulWidget {
  const _DetailView({required this.item, this.trailerContext, this.catalogDetail});
  final MediaItem item;
  final DetailTrailerContext? trailerContext;
  final MediaDetail? catalogDetail;

  @override
  State<_DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<_DetailView>
    with TickerProviderStateMixin {
  double _expandedHeightFor({required bool isReading, required bool hasDownload}) {
    if (isReading) return 520.0;
    if (hasDownload) return 610.0;
    return 540.0;
  }

  bool _showAppBarTitle = false;
  final ValueNotifier<double> _heroStretch = ValueNotifier<double>(0.0);
  String? _titleLogoUrl;
  String? _titleLogoKey;
  Color? _titleAccent;
  String? _titleAccentKey;
  static final Map<String, Color> _paletteCache = {};

  String? _prefetchedEpUrl;
  bool _actionInFlight = false;

  Set<int> _fillerEps = const {};
  int? _fillerForMal;
  void _ensureFiller(int? malId) {
    if (malId == null || malId == _fillerForMal) return;
    _fillerForMal = malId;
    FillerService.instance.fillerEpisodes(malId).then((s) {
      if (mounted && s.isNotEmpty) setState(() => _fillerEps = s);
    });
  }

  late final ScrollController _scrollController = ScrollController()
    ..addListener(_onScroll);

  late TabController _tabController;
  bool _tabShowsEpisodes = true;

  void _configureTabController(bool showEpisodes) {
    if (_tabShowsEpisodes == showEpisodes && _tabController.length == (showEpisodes ? 4 : 3)) return;
    final oldIndex = _tabController.index;
    _tabController.dispose();
    _tabShowsEpisodes = showEpisodes;
    _tabController = TabController(
      length: showEpisodes ? 4 : 3,
      vsync: this,
      initialIndex: (showEpisodes ? oldIndex.clamp(0, 3) : oldIndex.clamp(0, 2)).toInt(),
    );
  }

  final MyListStore _myList = sl<MyListStore>();
  final ListStatusStore _listStatus = sl<ListStatusStore>();
  late WatchStatus? _status = _listStatus.statusOf(widget.item);
  late bool _inMyList = _status != null || _myList.contains(widget.item);

  TrailerSource? _trailerSource;
  Timer? _trailerDelayTimer;
  String? _trailerDetailKey;
  bool _trailerResolving = false;

  void _scheduleTrailerResolution(MediaDetail detail) {
    final key = '${detail.sourceId}:${detail.id}:${detail.title}:${detail.year ?? ''}';
    if (_trailerDetailKey == key || _trailerResolving) return;
    _trailerDetailKey = key;
    _trailerDelayTimer?.cancel();
    _trailerDelayTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      _resolveTrailer(detail);
    });
  }

  void _resolveTrailer(MediaDetail detail) {
    if (_trailerResolving) return;
    _trailerResolving = true;

    var nsfwEnabled = false;
    try {
      if (sl.isRegistered<PlaybackPrefs>()) {
        nsfwEnabled = sl<PlaybackPrefs>().nsfwTrailers;
      }
    } catch (_) {}
    final isTpdb = widget.item.sourceId.startsWith('tpdb:');
    final hasNsfwContext = widget.trailerContext != null || isTpdb;

    final TrailerAlternateContext? alternateContext;
    if (hasNsfwContext && nsfwEnabled) {
      final name = detail.title;
      if (widget.trailerContext == DetailTrailerContext.studio) {
        alternateContext = TrailerAlternateContext.studio(name);
      } else if (widget.trailerContext == DetailTrailerContext.model) {
        alternateContext = TrailerAlternateContext.model(name);
      } else {
        alternateContext = TrailerAlternateContext.movie(name);
      }
    } else {
      alternateContext = null;
    }

    unawaited(() async {
      try {
        final source = await sl<TrailerService>()
            .resolveTrailer(
              title: detail.title,
              englishTitle: detail.englishTitle,
              type: detail.type,
              year: detail.year,
              alternateContext: alternateContext,
              tpdbId: isTpdb ? widget.item.id : null,
            )
            .timeout(const Duration(seconds: 10));
        if (!mounted) return;
        if (source != null && source != _trailerSource) {
          setState(() => _trailerSource = source);
        }
      } catch (_) {
        // Trailer lookup is optional; keep the static hero if it fails.
      } finally {
        _trailerResolving = false;
      }
    }());
  }

  @override
  void initState() {
    super.initState();
    _tabShowsEpisodes = widget.item.type == ProviderType.anime ||
        widget.item.type == ProviderType.manga ||
        widget.item.type == ProviderType.novel ||
        widget.item.tmdbIsTv;
    _tabController = TabController(
      length: _tabShowsEpisodes ? 4 : 3,
      vsync: this,
    );
    // Detail opens as a static artwork page. Trailer extraction is intentionally
    // not started automatically here because native stream extraction/player
    // creation can monopolize the UI on some Android devices.
    if (sl.isRegistered<DiscordRpc>()) {
      sl<DiscordRpc>().setBrowsing(
        title: widget.item.title,
        posterUrl: widget.item.cover,
      );
    }
  }

  @override
  void dispose() {
    if (sl.isRegistered<DiscordRpc>()) sl<DiscordRpc>().setBrowsing();
    _trailerDelayTimer?.cancel();
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _maybePrefetch(String epUrl, String sourceId) {
    if (_prefetchedEpUrl == epUrl) return;
    _prefetchedEpUrl = epUrl;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      sl<SourceRepository>().prefetch(epUrl, sourceId: sourceId);
    });
  }

  void _maybePrefetchCatalog({String category = 'sub'}) {
    // Background catalog prefetching is disabled because fanning out searches
    // across all providers in the background freezes the UI isolate on mobile.
    // Provider resolution is performed on-demand when the user presses Play.
  }

  void _loadTitleLogo(MediaDetail detail) {
    if (!sl.isRegistered<TitleLogoService>()) return;
    final tmdbId = detail.tmdbId ?? widget.item.tmdbId;
    final isTv = detail.tmdbIsTv || widget.item.tmdbIsTv;
    final key = '$tmdbId|$isTv|${detail.title}';
    if (_titleLogoKey == key) return;
    _titleLogoKey = key;
    sl<TitleLogoService>()
        .logoForDetail(
          title: detail.title,
          tmdbId: tmdbId,
          isTv: isTv,
          year: detail.year,
          sourceId: widget.item.sourceId,
        )
        .then((url) {
      if (!mounted || _titleLogoKey != key) return;
      if (url != null && url.isNotEmpty) {
        setState(() => _titleLogoUrl = url);
      }
    });
  }

  void _loadTitleAccent(MediaDetail detail) {
    final cover = widget.item.cover ?? detail.cover;
    if (cover == null || cover.isEmpty) return;
    final key = cover;
    if (_titleAccentKey == key) return;
    _titleAccentKey = key;
    final cached = _paletteCache[key];
    if (cached != null) {
      _titleAccent = cached;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        final palette = await PaletteGenerator.fromImageProvider(
          ResizeImage(
            nativeCoverProvider(
              cover,
              widget.item.coverHeaders ?? detail.coverHeaders,
            ),
            width: 80,
          ),
          size: const Size(80, 120),
          maximumColorCount: 4,
        );
        final color = palette.vibrantColor?.color ??
            palette.darkVibrantColor?.color ??
            palette.dominantColor?.color ??
            palette.mutedColor?.color;
        if (mounted && color != null) {
          _paletteCache[key] = color;
          setState(() => _titleAccent = color);
        }
      } catch (_) {}
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final isReading = sl<ContentModeCubit>().state.isReading;
    final height = _expandedHeightFor(isReading: isReading, hasDownload: !isReading);
    final shouldShow =
        _scrollController.offset > (height - kToolbarHeight - 24);
    if (shouldShow != _showAppBarTitle) {
      setState(() => _showAppBarTitle = shouldShow);
    }
  }

  void _revealTab(int index) {
    _tabController.animateTo(index);
    if (_scrollController.hasClients) {
      final target = _scrollController.position.maxScrollExtent;
      if (_scrollController.offset < target - 1) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  Future<void> _openListSheet(MediaDetail detail) async {
    await showListStatusSheet(
      context,
      item: widget.item,
      malId: detail.malId ?? widget.item.malId,
      tmdbId: detail.tmdbId ?? widget.item.tmdbId,
      tmdbIsTv: detail.tmdbIsTv,
      imdbId: detail.imdbId ?? widget.item.imdbId,
      onChanged: () {
        if (!mounted) return;
        setState(() {
          _status = _listStatus.statusOf(widget.item);
          _inMyList = _status != null || _myList.contains(widget.item);
        });
      },
    );
  }

  int? _trackerProgress;
  bool _tracked = false;
  int? _nextAiringEpisode;
  DateTime? _nextAiringAt;
  bool _trackerFetchStarted = false;
  String? _postFrameForDetailKey;

  void _maybeFetchTrackerProgress(MediaDetail detail) {
    if (_trackerFetchStarted) return;
    _trackerFetchStarted = true;
    final hub = sl<TrackerHub>();
    if (!hub.anyConnected) return;
    final isAnime = detail.type == ProviderType.anime;
    final reading =
        detail.type == ProviderType.manga || detail.type == ProviderType.novel;
    final pins = sl<TrackerBindingStore>()
        .get(TrackerBindingStore.keyOf(widget.item.sourceId, widget.item.url));
    hub
        .fetchEntry(
          malId: detail.malId ?? widget.item.malId,
          title: (isAnime || reading) ? detail.title : null,
          tmdbId: detail.tmdbId ?? widget.item.tmdbId,
          tmdbIsTv: detail.tmdbIsTv,
          imdbId: detail.imdbId ?? widget.item.imdbId,
          pinnedIds: pins.isEmpty ? null : pins,
          kind: reading ? MediaKind.manga : MediaKind.anime,
          novel: detail.type == ProviderType.novel,
        )
        .then((e) {
      if (!mounted) return;
      final ep = e?.nextAiringEpisode;
      final at = e?.nextAiringAt;
      final p = e?.progress;
      final onList = e?.onList ?? false;
      if (p == null || p <= 0) {
        setState(() {
          _tracked = onList;
          if (ep != null && at != null) {
            _nextAiringEpisode = ep;
            _nextAiringAt = at;
          }
        });
        return;
      }
      setState(() {
        _tracked = onList;
        _trackerProgress = p;
        _nextAiringEpisode = ep;
        _nextAiringAt = at;
      });
    });
  }

  bool _trackingAvailable(MediaDetail detail) {
    final hub = sl<TrackerHub>();
    if (!hub.anyConnected) return false;
    if (detail.type == ProviderType.anime ||
        detail.type == ProviderType.manga ||
        detail.type == ProviderType.novel) {
      return true;
    }
    final simklOn = hub.connected.any((t) => t.displayName == 'Simkl');
    final hasId = (detail.tmdbId ?? widget.item.tmdbId) != null ||
        ((detail.imdbId ?? widget.item.imdbId)?.isNotEmpty ?? false);
    return simklOn && hasId;
  }

  Future<void> _openTrackingSheet(MediaDetail detail) async {
    final reading = detail.type == ProviderType.manga ||
        detail.type == ProviderType.novel;
    final applied = await showTrackerListSheet(
      context,
      title: detail.title,
      isAnime: detail.type == ProviderType.anime,
      reading: reading,
      malId: detail.malId ?? widget.item.malId,
      tmdbId: detail.tmdbId ?? widget.item.tmdbId,
      tmdbIsTv: detail.tmdbIsTv,
      imdbId: detail.imdbId ?? widget.item.imdbId,
      bindingKey: TrackerBindingStore.keyOf(
        widget.item.sourceId,
        widget.item.url,
      ),
    );
    if (applied != null && mounted && applied > (_trackerProgress ?? 0)) {
      setState(() => _trackerProgress = applied);
    }
    if (!mounted) return;
    _trackerFetchStarted = false;
    _maybeFetchTrackerProgress(detail);
  }

  Future<void> _openRelation(MediaRelation r) async {
    _snack('Opening “${r.title}”…');
    try {
      if (r.tmdbId != null) {
        final isTv = r.tmdbIsTv;
        final related = MediaItem(
          id: 'tmdb:${isTv ? 'tv' : 'movie'}:${r.tmdbId}',
          title: r.title,
          cover: r.cover,
          url: 'tmdb://${isTv ? 'tv' : 'movie'}/${r.tmdbId}',
          type: ProviderType.movie,
          sourceId: 'tmdb:catalog',
          tmdbId: r.tmdbId,
          tmdbIsTv: isTv,
        );
        MediaDetail? catalogDetail;
        try {
          catalogDetail = await sl<TmdbDiscoverService>().movieDetail(related);
        } catch (_) {}
        if (!mounted) return;
        Navigator.of(context).push(DetailScreen.route(related, catalogDetail: catalogDetail));
        return;
      }
      if (r.catalogId != null || widget.item.sourceId == 'tpdb:catalog') {
        final id = r.catalogId ?? r.title;
        final related = MediaItem(
          id: 'tpdb:movie:$id',
          title: r.title,
          cover: r.cover,
          url: 'tpdb://movie/$id',
          type: ProviderType.movie,
          sourceId: 'tpdb:catalog',
        );
        if (!mounted) return;
        Navigator.of(context).push(DetailScreen.route(related));
        return;
      }

      if (widget.item.sourceId != 'tmdb:catalog') {
        final results = await sl<SourceRepository>().search(
          r.title,
          sourceId: widget.item.sourceId,
        );
        if (!mounted) return;
        final match = bestTitleMatch(
          results,
          r.title,
          altTitle: r.romaji,
          wantedMalId: r.malId,
        );
        if (match != null) {
          Navigator.of(context).push(DetailScreen.route(match));
          return;
        }
      }

      // Universal fallback: search TMDB catalog by relation title
      final tmdbMatches = await sl<TmdbDiscoverService>().search(
        query: r.title,
        type: 'all',
      );
      if (!mounted) return;
      if (tmdbMatches.isNotEmpty) {
        final best = tmdbMatches.first;
        MediaDetail? catalogDetail;
        try {
          catalogDetail = await sl<TmdbDiscoverService>().movieDetail(best);
        } catch (_) {}
        if (!mounted) return;
        Navigator.of(context).push(DetailScreen.route(best, catalogDetail: catalogDetail));
        return;
      }

      _snack('“${r.title}” isn’t available');
    } catch (_) {
      if (mounted) _snack('Couldn’t open “${r.title}”');
    }
  }

  void _share(MediaDetail detail, String sourceName) {
    SharePlus.instance.share(
      ShareParams(text: ShareLink.shareText(widget.item)),
    );
  }

  Future<void> _openSourceSite() async {
    final url = _sourceWebUrl();
    if (url == null) {
      _snack('No web page for this source');
      return;
    }
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) _snack('Could not open the source site');
  }

  String? _sourceWebUrl() {
    final u = widget.item.url.trim();
    if (u.isEmpty) return null;
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    final base = sl<SourceRepository>().baseUrlFor(widget.item.sourceId).trim();
    if (base.isEmpty) return null;
    if (base.endsWith('/') && u.startsWith('/')) return base + u.substring(1);
    return base + u;
  }

  bool get _subscribed =>
      sl<SubscriptionStore>().contains(widget.item.sourceId, widget.item.url);

  Future<void> _toggleSubscribe(MediaDetail detail) async {
    final store = sl<SubscriptionStore>();
    final item = widget.item;
    final reading =
        detail.type == ProviderType.manga || detail.type == ProviderType.novel;
    final unit = reading ? 'chapters' : 'episodes';
    if (_subscribed) {
      await store.remove(item.sourceId, item.url);
      _snack('Notifications off for “${item.title}”');
    } else {
      await store.add(
        Subscription(
          sourceId: item.sourceId,
          url: item.url,
          title: item.title.isNotEmpty ? item.title : detail.title,
          cover: item.cover,
          coverHeaders: item.coverHeaders,
          lastCount: detail.episodes.length,
          mode: detail.type == ProviderType.novel
              ? ContentMode.novel
              : detail.type == ProviderType.manga
              ? ContentMode.manga
              : ContentMode.anime,
        ),
      );
      await NotificationService.instance.init();
      _snack('You’ll be notified of new $unit of “${item.title}”');
    }
    await CsNotify.sync(store.all());
    if (mounted) setState(() {});
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            msg,
            style: AppText.caption.copyWith(color: Colors.white),
          ),
          backgroundColor: AppColors.surface2,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<List<VideoSource>> _resolveWithProgress(Episode ep) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      return await sl<SourceRepository>().sources(
        ep.url,
        sourceId: widget.item.sourceId,
        fast: false,
      );
    } catch (_) {
      return const [];
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _scrobbleUpTo(Episode ep, MediaDetail detail) async {
    final n = ep.number;
    if (n == null || n <= 0 || n != n.truncateToDouble()) return;
    await sl<TrackerHub>().scrobble(
      malId: detail.malId ?? widget.item.malId,
      title: detail.type == ProviderType.anime ? detail.title : null,
      tmdbId: widget.item.tmdbId,
      tmdbIsTv: widget.item.tmdbIsTv,
      imdbId: widget.item.imdbId,
      episode: n.toInt(),
      auto: false,
    );
  }

  Future<void> _pickPlayerFor(
    List<Episode> episodes,
    int index,
    MediaDetail detail,
    String category,
  ) async {
    if (index < 0 || index >= episodes.length) return;
    final ep = episodes[index];
    final label = ep.title.trim().isNotEmpty
        ? ep.title.trim()
        : 'Episode ${ep.number?.toInt() ?? index + 1}';
    final prefs = sl<PlaybackPrefs>();

    final resume = sl<ResumeStore>();
    final hub = sl<TrackerHub>();
    final action = await showEpisodeActionSheet(
      context,
      episodeLabel: label,
      currentPlayerLabel: prefs.externalPlayerPackage.isEmpty
          ? 'Built-in'
          : (prefs.externalPlayerLabel.isEmpty
                ? 'External'
                : prefs.externalPlayerLabel),
      isWatched:
          resume.get(widget.item.sourceId, widget.item.url, ep.id)?.finished ??
          false,
      tracksToServices: hub.anyConnected,
      thumbnailUrl: (ep.thumbnail != null && ep.thumbnail!.isNotEmpty)
          ? ep.thumbnail
          : (detail.cover ?? widget.item.cover),
      // Episode thumbnails are their own URLs. Never pass the show's native
      // x-ani-src/x-mihon-src marker to them — that routes the thumbnail through
      // the wrong image client and was the cause of the blank focused sheet.
      thumbnailHeaders: null,
      fallbackThumbnailUrl: detail.cover ?? widget.item.cover,
      fallbackThumbnailHeaders: detail.coverHeaders ?? widget.item.coverHeaders,
      rating: ep.rating,
      heroTag: 'episode-quick:${widget.item.sourceId}:${widget.item.id}:${ep.id}',
    );
    if (action == null || !mounted) return;

    switch (action) {
      case EpisodeAction.pickPlayer:
        final choice = await showEpisodePlayerSheet(
          context,
          episodeLabel: label,
          defaultPackage: prefs.externalPlayerPackage,
        );
        if (choice == null || !mounted) return;
        await _openPlayer(
          episodes,
          index,
          detail,
          category,
          playerOverride: choice,
        );
      case EpisodeAction.reloadLinks:
        sl<SourceRepository>().invalidateSources(
          ep.url,
          sourceId: widget.item.sourceId,
          includePrefetch: true,
        );
        sl<SourceRepository>().prefetch(
          ep.url,
          sourceId: widget.item.sourceId,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Links reloaded')));

      case EpisodeAction.playMirror:
        final sources = await _resolveWithProgress(ep);
        if (!mounted) return;
        if (sources.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No sources found for this episode')),
          );
          return;
        }
        final picked = await showMirrorSheet(
          context,
          episodeLabel: label,
          sources: sources,
        );
        if (picked == null || !mounted) return;
        await _openPlayer(
          episodes,
          index,
          detail,
          category,
          initialSource: picked,
        );

      case EpisodeAction.toggleWatched:
        final nowWatched =
            !(resume
                    .get(widget.item.sourceId, widget.item.url, ep.id)
                    ?.finished ??
                false);
        await resume.setWatched(
          widget.item.sourceId,
          widget.item.url,
          ep.id,
          watched: nowWatched,
        );
        if (nowWatched) await _scrobbleUpTo(ep, detail);
        if (!mounted) return;
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nowWatched ? 'Marked as watched' : 'Marked unwatched'),
          ),
        );

      case EpisodeAction.markAboveWatched:
        final currentSeason = seasonOf(ep);
        final sameSeason = currentSeason == null
            ? episodes
            : episodes.where((candidate) => seasonOf(candidate) == currentSeason).toList();
        final targetIndex = sameSeason.indexWhere((candidate) => candidate.id == ep.id);
        if (targetIndex < 0) return;
        for (var i = 0; i <= targetIndex; i++) {
          await resume.setWatched(
            widget.item.sourceId,
            widget.item.url,
            sameSeason[i].id,
            watched: true,
          );
        }
        await _scrobbleUpTo(ep, detail);
        if (!mounted) return;
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Marked ${targetIndex + 1} episodes as watched')),
        );
    }
  }

  Future<({MediaItem item, MediaDetail detail})?> _showProviderPickerSheet(
    MediaDetail detail, {
    String category = 'sub',
    bool ignoreActionInFlight = false,
  }) async {
    if (_actionInFlight && !ignoreActionInFlight) return null;
    final prevInFlight = _actionInFlight;
    _actionInFlight = true;
    try {
      return await showModalBottomSheet<({MediaItem item, MediaDetail detail})>(
        context: context,
        backgroundColor: AppColors.surface,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _ProviderPickerSheet(
          catalogItem: widget.item,
          catalogDetail: detail,
          category: category,
        ),
      );
    } finally {
      if (mounted) _actionInFlight = prevInFlight;
    }
  }

  Future<({MediaItem item, MediaDetail detail})?> _resolveCatalogPlayback({
    String category = 'sub',
  }) async {
    final catalog = widget.item;
    if (catalog.sourceId != 'tmdb:catalog' && !catalog.sourceId.startsWith('tpdb:')) {
      return null;
    }
    return sl<SourceRepository>().resolveCatalogTitle(
      catalog,
      category: category,
    );
  }

  Future<void> _openPlayer(
    List<Episode> episodes,
    int index,
    MediaDetail detail,
    String category, {
    PlayerChoice? playerOverride,
    VideoSource? initialSource,
  }) async {
    if (_actionInFlight) return;
    _actionInFlight = true;
    try {
      final inFlightPromotion = context.read<DetailCubit>().animePromotion;

      var eps = episodes;
      if (eps.isEmpty && (!detail.isSeries || widget.item.sourceId == 'tmdb:catalog' || widget.item.sourceId.startsWith('tpdb:'))) {
        eps = [
          Episode(
            id: widget.item.id,
            number: 1,
            title: detail.title.trim().isNotEmpty ? detail.title : widget.item.title,
            url: widget.item.url,
          ),
        ];
      }
      index = index.clamp(0, eps.isNotEmpty ? eps.length - 1 : 0);

      final reading =
          detail.type == ProviderType.novel ||
          detail.type == ProviderType.manga ||
          widget.item.type == ProviderType.novel ||
          widget.item.type == ProviderType.manga;
      final resume = reading
          ? _readResumeIndex(eps)
          : (index: _resumeIndex(eps), hasResume: _hasVideoResume(eps));
      var peek = false;
      if (shouldAskBeforeJump(
        resumeIndex: resume.index,
        targetIndex: index,
        hasResume: resume.hasResume,
        askEnabled: jumpPromptEnabled,
      )) {
        final choice = await showJumpPrompt(context, reading: reading);
        if (choice == null || !mounted) return;
        peek = choice == JumpChoice.peek;
      }

      final t = detail.type;
      final it = widget.item.type;
      if (t == ProviderType.novel ||
          t == ProviderType.manga ||
          it == ProviderType.novel ||
          it == ProviderType.manga) {
        if (sl<PlaybackPrefs>().autoAddToMyList &&
            !IncognitoMode.on &&
            !_myList.contains(widget.item)) {
          _myList.add(widget.item);
          _listStatus.setStatus(widget.item, WatchStatus.watching);
        }
        _openReader(eps, index, detail, peek: peek);
        return;
      }

      if (sl<PlaybackPrefs>().autoAddToMyList &&
          !IncognitoMode.on &&
          !_myList.contains(widget.item)) {
        _myList.add(widget.item);
        _listStatus.setStatus(widget.item, WatchStatus.watching);
      }

      final available = <String>[
        if ((detail.subCount ?? 0) > 0) 'sub',
        if ((detail.dubCount ?? 0) > 0) 'dub',
      ];
      final availableCategories = available.isEmpty ? [category] : available;

      final preferred =
          sl<TitlePrefsStore>().category(detail.sourceId, detail.url) ??
          sl<PlaybackPrefs>().defaultCategory;
      final launchCategory = availableCategories.contains(preferred)
          ? preferred
          : category;

      var malId = detail.malId ?? widget.item.malId;
      var scrobbleTitle =
          detail.type == ProviderType.anime ? detail.title : null;
      if (malId == null && detail.type == ProviderType.movie) {
        final promotion = inFlightPromotion;
        if (promotion != null) {
          try {
            final promoted = await promotion.timeout(const Duration(milliseconds: 50), onTimeout: () => null);
            if (promoted != null) {
              malId = promoted;
              scrobbleTitle = detail.title;
            }
          } catch (_) {}
        }
      }
      if (!mounted) return;

      Future<({String url, String sourceId})> resolvePlaybackTarget(String u) async {
        if (widget.item.sourceId != 'tmdb:catalog' && !widget.item.sourceId.startsWith('tpdb:')) {
          return (url: u, sourceId: detail.sourceId);
        }
        final resolved = await _resolveCatalogPlayback(category: category);
        if (resolved == null) {
          return (url: u, sourceId: detail.sourceId);
        }
        final targetSourceId = resolved.item.sourceId;
        if (resolved.detail.episodes.isEmpty) {
          return (url: resolved.item.url, sourceId: targetSourceId);
        }
        for (final e in resolved.detail.episodes) {
          if (e.url == u || e.id == u) {
            return (url: e.url, sourceId: targetSourceId);
          }
        }
        Episode? origEp;
        for (final e in eps) {
          if (e.url == u || e.id == u) {
            origEp = e;
            break;
          }
        }
        if (origEp != null) {
          final wantedSeason = seasonOf(origEp);
          final wantedNumber = origEp.number;
          for (final e in resolved.detail.episodes) {
            if (e.number == wantedNumber &&
                (wantedSeason == null || seasonOf(e) == wantedSeason)) {
              return (url: e.url, sourceId: targetSourceId);
            }
          }
          if (wantedNumber != null) {
            for (final e in resolved.detail.episodes) {
              if (e.number == wantedNumber) {
                return (url: e.url, sourceId: targetSourceId);
              }
            }
          }
        }
        return (url: resolved.detail.episodes.first.url, sourceId: targetSourceId);
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            playerOverride: playerOverride?.package,
            initialSource: initialSource,
            sourceId: detail.sourceId,
            episodes: eps,
            startIndex: index,
            resume: sl<ResumeStore>(),
            resolveSources: (u) async {
              final target = await resolvePlaybackTarget(u);
              return sl<SourceRepository>().sources(
                target.url,
                sourceId: target.sourceId,
                fast: true,
              );
            },
            pollSources: (u) async {
              final target = await resolvePlaybackTarget(u);
              return sl<SourceRepository>().polledSources(
                target.url,
                sourceId: target.sourceId,
              );
            },
            history: sl<WatchHistory>(),
            showTitle: detail.title,
            cover: detail.cover ?? widget.item.cover,
            coverHeaders: detail.coverHeaders ?? widget.item.coverHeaders,
            showUrl: detail.url,
            category: launchCategory,
            malId: malId,
            scrobbleTitle: scrobbleTitle,
            tmdbId: detail.tmdbId ?? widget.item.tmdbId,
            tmdbIsTv: detail.tmdbIsTv,
            imdbId: detail.imdbId ?? widget.item.imdbId,
            availableCategories: availableCategories,
            peek: peek,
          ),
        ),
      );
    } finally {
      if (mounted) _actionInFlight = false;
    }
  }

  void _openReader(
    List<Episode> chapters,
    int index,
    MediaDetail detail, {
    bool peek = false,
  }) {
    final readingType =
        (detail.type == ProviderType.novel || detail.type == ProviderType.manga)
        ? detail.type
        : widget.item.type;
    switch (readingType) {
      case ProviderType.novel:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => NovelReaderScreen(
              sourceId: widget.item.sourceId,
              showId: widget.item.id,
              showTitle: detail.title,
              cover: detail.cover ?? widget.item.cover,
              chapters: chapters,
              startIndex: index,
              malId: detail.malId ?? widget.item.malId,
              peek: peek,
            ),
          ),
        );
        return;
      case ProviderType.manga:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MangaReaderScreen(
              sourceId: widget.item.sourceId,
              showId: widget.item.id,
              showTitle: detail.title,
              cover: detail.cover ?? widget.item.cover,
              chapters: chapters,
              startIndex: index,
              malId: detail.malId ?? widget.item.malId,
              peek: peek,
            ),
          ),
        );
        return;
      case ProviderType.anime:
      case ProviderType.movie:
        return;
    }
  }

  void _openTrailer(TrailerSource source) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => TrailerScreen(title: widget.item.title, source: source)));
  }

  String _downloadLabel(
    MediaDetail detail,
    List<Episode> seasonEps,
    bool hasMultipleSeasons,
    int currentSeason,
  ) {
    if (!detail.isSeries || seasonEps.isEmpty) return 'Download';
    final first = seasonEps.first;
    final epNum = first.number?.toInt() ?? 1;
    if (hasMultipleSeasons) return 'Download S$currentSeason:E$epNum';
    return 'Download E$epNum';
  }

  int? _resumePercent(List<Episode> eps, int index) {
    if (eps.isEmpty || index < 0 || index >= eps.length) return null;
    final mark = sl<ResumeStore>().get(
      widget.item.sourceId,
      widget.item.url,
      eps[index].id,
    );
    if (mark == null || mark.duration.inMilliseconds <= 0) return null;
    final fraction = mark.position.inMilliseconds / mark.duration.inMilliseconds;
    return (fraction.clamp(0.0, 1.0) * 100).round();
  }

  bool _hasVideoResume(List<Episode> eps) {
    final store = sl<ResumeStore>();
    for (final e in eps) {
      if (store.get(widget.item.sourceId, widget.item.url, e.id) != null) {
        return true;
      }
    }
    return false;
  }

  int _resumeIndex(List<Episode> eps) {
    final store = sl<ResumeStore>();
    int? highestMarked;
    for (int j = 0; j < eps.length; j++) {
      final mark = store.get(widget.item.sourceId, widget.item.url, eps[j].id);
      if (mark != null) {
        highestMarked = j;
      }
    }
    if (highestMarked == null) return 0;
    final mark = store.get(
      widget.item.sourceId,
      widget.item.url,
      eps[highestMarked].id,
    )!;
    if (!mark.finished) return highestMarked;
    if (highestMarked + 1 < eps.length) return highestMarked + 1;
    return highestMarked;
  }

  ({int index, bool hasResume}) _resumeTarget(List<Episode> eps) {
    if (eps.isEmpty) return (index: 0, hasResume: false);
    final store = sl<ResumeStore>();
    final hasLocal = eps.any(
      (e) => store.get(widget.item.sourceId, widget.item.url, e.id) != null,
    );
    if (hasLocal) return (index: _resumeIndex(eps), hasResume: true);
    final p = _trackerProgress;
    if (p != null && p > 0 && seasonsOf(eps).length <= 1) {
      for (var j = 0; j < eps.length; j++) {
        final n = eps[j].number?.toInt();
        if (n != null && n > p) return (index: j, hasResume: true);
      }
    }
    return (index: 0, hasResume: false);
  }

  ({int index, bool hasResume}) _readResumeIndex(List<Episode> chapters) {
    if (chapters.isEmpty) return (index: 0, hasResume: false);
    final store = sl<ReadStore>();
    int? highestMarked;
    for (var j = 0; j < chapters.length; j++) {
      if (store.get(widget.item.sourceId, widget.item.id, chapters[j].id) !=
          null) {
        highestMarked = j;
      }
    }
    if (highestMarked != null) {
      if (!store.finished(
        widget.item.sourceId,
        widget.item.id,
        chapters[highestMarked].id,
      )) {
        return (index: highestMarked, hasResume: true);
      }
      final next = highestMarked + 1 < chapters.length
          ? highestMarked + 1
          : highestMarked;
      return (index: next, hasResume: true);
    }
    final entry = sl<ReadHistory>().get(widget.item.sourceId, widget.item.id);
    if (entry != null) {
      var idx = chapters.indexWhere((c) => c.id == entry.chapterId);
      if (idx < 0) idx = chapters.indexWhere((c) => c.url == entry.chapterUrl);
      if (idx >= 0) {
        if (entry.finished && idx + 1 < chapters.length) idx += 1;
        return (index: idx, hasResume: true);
      }
    }
    return (index: 0, hasResume: false);
  }

  Future<void> _openDownloadSheet({
    required MediaDetail detail,
    required String category,
    required Map<int, List<Episode>> episodesBySeason,
    required int initialSeason,
  }) async {
    if (_actionInFlight) return;
    _actionInFlight = true;
    try {
      final isCatalog = widget.item.sourceId == 'tmdb:catalog' || widget.item.sourceId.startsWith('tpdb:');
      final total = episodesBySeason.values.fold<int>(0, (a, b) => a + b.length);
      if (total == 0) {
        if (isCatalog || !detail.isSeries) {
          final ep = Episode(
            id: widget.item.id,
            number: 1,
            title: detail.title.trim().isNotEmpty ? detail.title : widget.item.title,
            url: widget.item.url,
          );
          await _pickSourceAndDownload(ep, detail, category);
          return;
        }
        _snack('No episodes to download');
        return;
      }
      if (total == 1 || (!detail.isSeries && isCatalog)) {
        final ep = episodesBySeason.values.isNotEmpty && episodesBySeason.values.first.isNotEmpty
            ? episodesBySeason.values.first.first
            : (detail.episodes.isNotEmpty
                ? detail.episodes.first
                : Episode(id: widget.item.id, number: 1, title: detail.title, url: widget.item.url));
        await _pickSourceAndDownload(
          ep,
          detail,
          category,
        );
        return;
      }
      final availableCategories = <String>[
        if ((detail.subCount ?? 0) > 0) 'sub',
        if ((detail.dubCount ?? 0) > 0) 'dub',
      ];
      final res =
          await showModalBottomSheet<
            ({String quality, String category, List<Episode> episodes})
          >(
            context: context,
            backgroundColor: AppColors.surface,
            isScrollControlled: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (_) => _DownloadSheet(
              minimal:
                  !sl<AppMode>().isTv &&
                  sl<PlaybackPrefs>().batchDownloadStyle == 'minimal',
              title: detail.title,
              episodesBySeason: episodesBySeason,
              initialSeason: initialSeason,
              initialCategory: category,
              availableCategories: availableCategories,
              coverUrl: detail.cover ?? widget.item.cover ?? '',
              coverHeaders: detail.coverHeaders ?? widget.item.coverHeaders,
              resolve: (ep) async {
                var sId = detail.sourceId;
                var epUrl = ep.url;
                if (isCatalog) {
                  final resolved = await _resolveCatalogPlayback(category: category);
                  if (resolved != null) {
                    sId = resolved.item.sourceId;
                    if (resolved.detail.episodes.isNotEmpty) {
                      final match = resolved.detail.episodes.firstWhere(
                        (e) => e.number == ep.number && (seasonOf(e) == seasonOf(ep) || seasonOf(ep) == null),
                        orElse: () => resolved.detail.episodes.first,
                      );
                      epUrl = match.url;
                    } else {
                      epUrl = resolved.item.url;
                    }
                  }
                }
                return sl<SourceRepository>().sources(
                  epUrl,
                  sourceId: sId,
                );
              },
              resolveEpisodes: _episodesByCategory,
            ),
          );
      if (res == null || !mounted) return;
      _startDownload(detail, res.category, res.quality, res.episodes);
    } finally {
      if (mounted) _actionInFlight = false;
    }
  }

  Future<Map<int, List<Episode>>> _episodesByCategory(String category) async {
    MediaDetail d;
    if (widget.item.sourceId == 'tmdb:catalog' || widget.item.sourceId.startsWith('tpdb:')) {
      final resolved = await _resolveCatalogPlayback(category: category);
      if (resolved == null) return const {};
      d = await sl<SourceRepository>().detail(resolved.item.url, category: category, sourceId: resolved.item.sourceId);
    } else {
      d = await sl<SourceRepository>().detail(widget.item.url, category: category, sourceId: widget.item.sourceId);
    }
    var eps = d.episodes;
    if (mounted) {
      final cd = context.read<DetailCubit>().state.detail ?? d;
      eps = await sl<EpisodeMetadataService>().enrich(
        episodes: eps, type: cd.type, malId: cd.malId, tmdbId: cd.tmdbId, tmdbIsTv: cd.tmdbIsTv,
      );
    }
    final byS = <int, List<Episode>>{};
    for (final e in eps) { (byS[seasonOf(e) ?? 1] ??= <Episode>[]).add(e); }
    if (byS.isEmpty) byS[1] = eps;
    return byS;
  }

  Future<void> _downloadSingle(
    Episode ep,
    MediaDetail detail,
    String category,
  ) => _pickSourceAndDownload(ep, detail, category);

  Future<void> _downloadChapter(Episode ep, MediaDetail detail) =>
      _downloadChapters([ep], detail);

  Future<void> _downloadChapters(List<Episode> eps, MediaDetail detail) {
    final item = widget.item;
    return sl<ChapterDownloader>().enqueueMany(
      chapters: eps,
      sourceId: item.sourceId,
      showId: item.id,
      showTitle: detail.title,
      cover: detail.cover ?? item.cover,
      mode: detail.type == ProviderType.novel
          ? ContentMode.novel
          : ContentMode.manga,
    );
  }

  Future<void> _pickSourceAndDownload(
    Episode ep,
    MediaDetail detail,
    String category,
  ) async {
    final isCatalog = widget.item.sourceId == 'tmdb:catalog' || widget.item.sourceId.startsWith('tpdb:');
    var targetItem = widget.item;
    var targetDetail = detail;
    var targetEp = ep;

    if (isCatalog) {
      if (detail.sourceId != 'tmdb:catalog' && !detail.sourceId.startsWith('tpdb:')) {
        targetItem = MediaItem(
          id: detail.id,
          title: detail.title,
          url: detail.url,
          type: detail.type,
          sourceId: detail.sourceId,
        );
        targetDetail = detail;
        targetEp = ep;
      }
    }

    if (!mounted) return;

    final res = await showModalBottomSheet<SourcePickerResult>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SourcePickerSheet(
        title: targetEp.title.trim().isNotEmpty ? targetEp.title : targetDetail.title,
        loadingMessage: isCatalog
            ? 'Searching providers for download sources…'
            : 'Resolving download options…',
        onChooseProvider: isCatalog
            ? () async {
                final picked = await _showProviderPickerSheet(detail, category: category, ignoreActionInFlight: true);
                if (picked != null && mounted) {
                  final pickedEp = _matchTargetEpisode(picked.detail, picked.item, ep);
                  await _pickSourceAndDownload(pickedEp, picked.detail, category);
                }
              }
            : null,
        resolve: ([onProgress]) async {
          if (isCatalog && (targetDetail.sourceId == 'tmdb:catalog' || targetDetail.sourceId.startsWith('tpdb:'))) {
            final resolved = await _resolveCatalogPlayback(category: category);
            if (resolved != null) {
              targetItem = resolved.item;
              targetDetail = resolved.detail;
              targetEp = _matchTargetEpisode(targetDetail, targetItem, ep);
            } else {
              return (
                sources: <VideoSource>[],
                resolvedItem: targetItem,
                resolvedDetail: targetDetail,
                resolvedEpisode: targetEp,
                error: 'No matching title found on installed providers',
              );
            }
          }
          var s = await sl<SourceRepository>().sources(
            targetEp.url,
            sourceId: targetDetail.sourceId,
            fast: true,
          );
          if (s.isNotEmpty) {
            onProgress?.call(
              sources: s,
              resolvedItem: targetItem,
              resolvedDetail: targetDetail,
              resolvedEpisode: targetEp,
            );
          }

          var done = false;
          var pollTries = 0;
          final knownUrls = s.map((e) => e.url).toSet();

          while (!done && pollTries < 15) {
            await Future.delayed(const Duration(milliseconds: 750));
            pollTries++;
            final polled = await sl<SourceRepository>().polledSources(
              targetEp.url,
              sourceId: targetDetail.sourceId,
            );
            done = polled.done;
            final newSources = polled.sources.where((e) => !knownUrls.contains(e.url)).toList();
            if (newSources.isNotEmpty) {
              for (final ns in newSources) {
                knownUrls.add(ns.url);
              }
              s = [...s, ...newSources];
              onProgress?.call(
                sources: s,
                resolvedItem: targetItem,
                resolvedDetail: targetDetail,
                resolvedEpisode: targetEp,
              );
            }
          }

          if (s.isEmpty) {
            final fallbackSources = await sl<SourceRepository>().sources(
              targetEp.url,
              sourceId: targetDetail.sourceId,
              fast: false,
            );
            if (fallbackSources.isNotEmpty) {
              s = fallbackSources;
            }
          }

          return (
            sources: s,
            resolvedItem: targetItem,
            resolvedDetail: targetDetail,
            resolvedEpisode: targetEp,
            error: s.isEmpty ? 'No download sources found on installed providers' : null,
          );
        },
      ),
    );

    if (res == null || !mounted) return;
    final finalItem = res.resolvedItem ?? widget.item;
    final finalDetail = res.resolvedDetail ?? detail;
    final finalEp = res.resolvedEpisode ?? ep;

    final catalogCover = (detail.cover != null && detail.cover!.isNotEmpty)
        ? detail.cover
        : ((widget.item.cover != null && widget.item.cover!.isNotEmpty) ? widget.item.cover : null);
    final catalogHeaders = detail.coverHeaders ?? widget.item.coverHeaders;
    final catalogTitle = detail.title.trim().isNotEmpty ? detail.title : widget.item.title;

    final effectiveCover = isCatalog
        ? (catalogCover ?? finalDetail.cover ?? finalItem.cover)
        : (finalDetail.cover ?? finalItem.cover ?? catalogCover);
    final effectiveHeaders = isCatalog
        ? (catalogHeaders ?? finalDetail.coverHeaders ?? finalItem.coverHeaders)
        : (finalDetail.coverHeaders ?? finalItem.coverHeaders ?? catalogHeaders);
    final effectiveTitle = isCatalog && catalogTitle.isNotEmpty ? catalogTitle : finalDetail.title;

    unawaited(
      sl<DownloadManager>().enqueueSource(
        sourceId: finalDetail.sourceId,
        showId: isCatalog ? widget.item.id : finalDetail.id,
        showTitle: effectiveTitle,
        cover: effectiveCover,
        coverHeaders: effectiveHeaders,
        showUrl: finalDetail.url,
        category: category,
        episode: finalEp,
        source: res.chosen,
        qualityLabel: res.chosen.quality ?? 'auto',
        fallbacks: res.all,
        nowMs: DateTime.now().millisecondsSinceEpoch,
        malId: finalDetail.malId ?? finalItem.malId,
      ),
    );
    _snack('Added to downloads');
  }

  void _startDownload(
    MediaDetail detail,
    String category,
    String quality,
    List<Episode> episodes,
  ) {
    final item = widget.item;
    final isCatalog = item.sourceId == 'tmdb:catalog' || item.sourceId.startsWith('tpdb:');
    final catalogCover = (detail.cover != null && detail.cover!.isNotEmpty)
        ? detail.cover
        : ((item.cover != null && item.cover!.isNotEmpty) ? item.cover : null);
    final catalogHeaders = detail.coverHeaders ?? item.coverHeaders;
    final catalogTitle = detail.title.trim().isNotEmpty ? detail.title : item.title;

    unawaited(
      sl<DownloadManager>().enqueueEpisodes(
        sourceId: detail.sourceId,
        showId: isCatalog ? item.id : detail.id,
        showTitle: isCatalog ? catalogTitle : detail.title,
        cover: isCatalog ? (catalogCover ?? detail.cover ?? item.cover) : (detail.cover ?? item.cover),
        coverHeaders: isCatalog ? (catalogHeaders ?? detail.coverHeaders ?? item.coverHeaders) : (detail.coverHeaders ?? item.coverHeaders),
        showUrl: detail.url,
        category: category,
        quality: quality,
        episodes: episodes,
        nowMs: DateTime.now().millisecondsSinceEpoch,
        malId: detail.malId ?? item.malId,
      ),
    );
    _snack(
      episodes.length == 1
          ? 'Added to downloads'
          : 'Downloading ${episodes.length} episodes',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (sl<AppMode>().isTv) return DetailScreenTv(item: widget.item);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: BlocBuilder<DetailCubit, DetailState>(
        builder: (context, state) {
          if (state.status == DetailStatus.loading) {
            return const _DetailSkeleton(heroHeight: 450);
          }
          if (state.detail == null && state.status == DetailStatus.error) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const EmptyState(
                      icon: Icons.error_outline,
                      message: 'Failed to load this title',
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: () => context.read<DetailCubit>().retry(),
                          icon: Icon(Icons.refresh_rounded, color: AppColors.accent),
                          label: Text('Tap to retry', style: TextStyle(color: AppColors.accent)),
                        ),
                        const SizedBox(width: 12),
                        TextButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => SearchScreen(initialQuery: widget.item.title),
                            ),
                          ),
                          icon: Icon(Icons.search_rounded, color: AppColors.accent),
                          label: Text('Search sources', style: TextStyle(color: AppColors.accent)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }
          if (state.detail == null) return const _DetailSkeleton(heroHeight: 450);
          return _buildBody(context, state, state.detail!);
        },
      ),
    );
  }

  Widget _heroMetaLine(MediaDetail detail) {
    final parts = <String>[];
    final year = detail.year ?? widget.item.year;
    final rating = detail.rating ?? widget.item.rating;
    if (year != null && year.trim().isNotEmpty) parts.add(year.trim());
    if (rating != null && rating > 0) parts.add(rating.toStringAsFixed(1));
    if (detail.genres.isNotEmpty) {
      parts.addAll(detail.genres.take(3));
    } else if (widget.item.genres.isNotEmpty) {
      parts.addAll(widget.item.genres.take(3));
    }
    if (parts.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0)
            Container(
              width: 3,
              height: 3,
              decoration: const BoxDecoration(
                color: AppColors.textTertiary,
                shape: BoxShape.circle,
              ),
            ),
          if (i == 1 && rating != null)
            const Icon(
              Icons.star_rounded,
              color: Color(0xFFFFC107),
              size: 14,
            ),
          Text(
            parts[i],
            style: AppText.caption.copyWith(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  Widget _titleHeader(MediaDetail detail, {bool compact = false}) {
    final logo = _titleLogoUrl;
    if (logo != null && logo.isNotEmpty) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: compact ? 200 : 290,
          maxHeight: compact ? 32 : 60,
        ),
        child: CachedNetworkImage(
          imageUrl: logo,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          fadeInDuration: const Duration(milliseconds: 220),
          placeholder: (_, _) => _styledFallbackTitle(
            detail,
            fontSize: compact ? 17 : 26,
            maxLines: compact ? 1 : 2,
          ),
          errorWidget: (_, _, _) => _styledFallbackTitle(
            detail,
            fontSize: compact ? 17 : 26,
            maxLines: compact ? 1 : 2,
          ),
        ),
      );
    }
    return _styledFallbackTitle(
      detail,
      fontSize: compact ? 17 : 26,
      maxLines: compact ? 1 : 2,
    );
  }

  Widget _styledFallbackTitle(
    MediaDetail detail, {
    double fontSize = 26,
    int maxLines = 2,
  }) {
    final seed = detail.tmdbId ?? widget.item.tmdbId ?? detail.title;
    final accent = _titleAccent ?? AppColors.textPrimary;
    return cinioFallbackTitle(
      title: detail.title,
      seed: seed,
      accent: accent,
      fontSize: fontSize,
      maxLines: maxLines,
    );
  }

  Widget _buildBody(
    BuildContext context,
    DetailState state,
    MediaDetail detail,
  ) {
    final item = widget.item;
    final cubit = context.read<DetailCubit>();
    _loadTitleLogo(detail);
    final category = state.category;
    final selectedSeason = state.selectedSeason;
    final eps = detail.episodes;
    final store = sl<ResumeStore>();
    final isReading =
        detail.type == ProviderType.novel || detail.type == ProviderType.manga;
    final showEpisodesTab = isReading ||
        detail.isSeries ||
        detail.type == ProviderType.anime ||
        eps.length > 1;
    if (_tabShowsEpisodes != showEpisodesTab) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _configureTabController(showEpisodesTab));
      });
    }
    final detailKey = '${detail.sourceId}:${detail.id}';
    if (_postFrameForDetailKey != detailKey) {
      _postFrameForDetailKey = detailKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureFiller(detail.malId ?? item.malId);
        _maybeFetchTrackerProgress(detail);
        _loadTitleAccent(detail);
        _scheduleTrailerResolution(detail);
      });
    }

    final resume = _resumeTarget(eps);
    final readResume = isReading ? _readResumeIndex(eps) : null;
    final resumeIdx = isReading ? readResume!.index : resume.index;
    if (!isReading && eps.isNotEmpty &&
        !(item.sourceId == 'tmdb:catalog' || item.sourceId.startsWith('tpdb:'))) {
      _maybePrefetch(eps[resumeIdx].url, item.sourceId);
    } else if (!isReading && (item.sourceId == 'tmdb:catalog' || item.sourceId.startsWith('tpdb:'))) {
      _maybePrefetchCatalog(category: category);
    }
    final hasAnyMark = eps.any(
      (e) => store.get(item.sourceId, item.url, e.id) != null,
    );
    final episodeNum = eps.isNotEmpty
        ? (eps[resumeIdx].number?.toInt() ?? resumeIdx + 1)
        : 1;
    final resumePercent = detail.isSeries ? null : _resumePercent(eps, resumeIdx);
    final buttonLabel = isReading
        ? (readResume!.hasResume ? 'Continue' : 'Read')
        : (detail.isSeries
            ? (resume.hasResume ? 'Continue E$episodeNum' : 'Play E$episodeNum')
            : (resume.hasResume
                ? (resumePercent != null ? 'Continue $resumePercent%' : 'Continue')
                : (_isInCinema(detail) ? 'In Cinema' : 'Play')));

    final coverUrl = detail.cover ?? item.cover ?? '';
    final heroCoverUrl = item.heroImage ?? coverUrl;
    final coverHeaders = detail.coverHeaders ?? item.coverHeaders;
    final hasCover = heroCoverUrl.isNotEmpty;

    // Do not resolve or mount a native trailer player during detail rendering.

    final seasonSet = seasonsOf(eps, detail.availableSeasons);
    final hasMultipleSeasons = seasonSet.length > 1;
    final currentSeason = hasMultipleSeasons
        ? (seasonSet.contains(selectedSeason)
              ? selectedSeason
              : (seasonSet.isNotEmpty ? seasonSet.first : 1))
        : 1;
    final filteredBySeason = hasMultipleSeasons
        ? eps.where((e) => (seasonOf(e) ?? 1) == currentSeason).toList()
        : eps;
    final seasonEps = (filteredBySeason.isEmpty && eps.isNotEmpty)
        ? eps
        : filteredBySeason;

    final episodesBySeason = <int, List<Episode>>{};
    if (hasMultipleSeasons) {
      for (final e in eps) {
        (episodesBySeason[seasonOf(e) ?? 1] ??= <Episode>[]).add(e);
      }
    } else {
      episodesBySeason[1] = eps;
    }

    final downloadLabel = _downloadLabel(
      detail,
      seasonEps,
      hasMultipleSeasons,
      currentSeason,
    );

    final castNames = state.cast.isNotEmpty
        ? state.cast.map((c) => c.name).toList()
        : detail.cast;
    final starring = castNames.isNotEmpty ? castNames.take(3).join(', ') : null;
    final starringMore = castNames.length > 3;
    final creators = detail.studios.isNotEmpty
        ? detail.studios.join(', ')
        : null;
    final genresLine = (starring == null && detail.genres.isNotEmpty)
        ? detail.genres.take(4).join(', ')
        : null;

    final sourceName = _sourceLabel(item.sourceId);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis == Axis.vertical) {
          if (notification.metrics.pixels < 0) {
            _heroStretch.value = (-notification.metrics.pixels).clamp(0.0, 180.0);
          } else if (_heroStretch.value > 0) {
            _heroStretch.value = 0.0;
          }
        }
        return false;
      },
      child: NestedScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            expandedHeight: _expandedHeightFor(
              isReading: isReading,
              hasDownload: !isReading,
            ),
            pinned: true,
            floating: false,
            snap: false,
            backgroundColor: _showAppBarTitle ? AppColors.bg : Colors.transparent,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.black54,
            elevation: _showAppBarTitle ? 3 : 0,
            stretch: true,
            stretchTriggerOffset: 80,
            leading: Center(
              child: Container(
                margin: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _showAppBarTitle
                      ? Colors.transparent
                      : Colors.black.withValues(alpha: 0.45),
                ),
                child: IconButton(
                  icon: const Icon(CupertinoIcons.chevron_back, color: Colors.white, size: 19.5),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
            title: AnimatedOpacity(
              opacity: _showAppBarTitle ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 220),
              child: _titleHeader(detail, compact: true),
            ),
            centerTitle: true,
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              stretchModes: const [
                StretchMode.zoomBackground,
              ],
              background: _Hero(
                coverUrl: heroCoverUrl,
                coverHeaders: coverHeaders,
                hasCover: hasCover,
                trailer: _trailerSource,
                collapsed: _showAppBarTitle,
                stretch: _heroStretch,
                onTapFullscreen: _trailerSource != null
                    ? () => _openTrailer(_trailerSource!)
                    : null,
                bottomContent: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SearchScreen(initialQuery: detail.title),
                        ),
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 390),
                        child: _titleHeader(detail),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _heroMetaLine(detail),
                    const SizedBox(height: 16),
                    if (_isFutureRelease(detail))
                      const _ComingSoonButton()
                    else ...[
                      _PlayButton(
                        label: buttonLabel,
                        icon: isReading
                            ? CupertinoIcons.book
                            : CupertinoIcons.play_arrow_solid,
                        onPressed: (eps.isNotEmpty ||
                                widget.item.sourceId == 'tmdb:catalog' ||
                                widget.item.sourceId.startsWith('tpdb:'))
                            ? () => _openPlayer(eps, resumeIdx, detail, category)
                            : null,
                        onLongPress: (widget.item.sourceId == 'tmdb:catalog' ||
                                widget.item.sourceId.startsWith('tpdb:'))
                            ? () async {
                                final picked = await _showProviderPickerSheet(detail, category: category);
                                if (picked != null && mounted) {
                                  _openPlayer(picked.detail.episodes, 0, picked.detail, category);
                                }
                              }
                            : null,
                      ),
                      if (!isReading) ...[
                        const SizedBox(height: 10),
                        _DownloadButton(
                          label: downloadLabel,
                          onPressed: () => _openDownloadSheet(
                            detail: detail,
                            category: category,
                            episodesBySeason: episodesBySeason,
                            initialSeason: currentSeason,
                          ),
                          onLongPress: (widget.item.sourceId == 'tmdb:catalog' ||
                                  widget.item.sourceId.startsWith('tpdb:'))
                              ? () async {
                                  final picked = await _showProviderPickerSheet(detail, category: category);
                                  if (picked != null && mounted) {
                                    _openDownloadSheet(
                                      detail: picked.detail,
                                      category: category,
                                      episodesBySeason: {
                                        1: picked.detail.episodes,
                                      },
                                      initialSeason: 1,
                                    );
                                  }
                                }
                              : null,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),

        SliverToBoxAdapter(
          child: ValueListenableBuilder<double>(
            valueListenable: _heroStretch,
            builder: (context, overscroll, child) {
              return Transform.translate(
                offset: Offset(0, overscroll * 0.40),
                child: child,
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state.error == 'load_failed')
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 18, color: Colors.orangeAccent),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Could not load full details',
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ),
                          InkWell(
                            onTap: () => cubit.retry(),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Text(
                                'Retry',
                                style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                if ((detail.description ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                    child: _Description(
                      text: detail.description!,
                      onReadMore: () => _revealTab(showEpisodesTab ? 3 : 2),
                    ),
                  )
                else if (state.extrasLoading)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 12,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: AppColors.surface2,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 12,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: AppColors.surface2,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 12,
                          width: 200,
                          decoration: BoxDecoration(
                            color: AppColors.surface2,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (starring != null || creators != null || genresLine != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (starring != null)
                          _CreditLine(
                            label: 'Starring',
                            value: starring,
                            more: starringMore,
                            onMore: starringMore ? () => _revealTab(showEpisodesTab ? 1 : 0) : null,
                          ),
                        if (genresLine != null)
                          _CreditLine(label: 'Genres', value: genresLine),
                        if (creators != null)
                          _CreditLine(label: 'Creators', value: creators),
                      ],
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _IconAction(
                        icon: _inMyList ? CupertinoIcons.checkmark_alt : CupertinoIcons.plus,
                        active: _inMyList,
                        label: _status == null
                            ? 'My List'
                            : shortLabelFor(_status!, reading: isReading),
                        tooltip: _inMyList ? 'Change status' : 'Add to My List',
                        onTap: () => _openListSheet(detail),
                      ),
                      if (Platform.isAndroid)
                        _IconAction(
                          icon: _subscribed
                              ? CupertinoIcons.bell_fill
                              : CupertinoIcons.bell,
                          active: _subscribed,
                          label: 'Notify',
                          tooltip: _subscribed
                              ? 'Stop alerts'
                              : (isReading
                                    ? 'Notify on new chapters'
                                    : 'Notify on new episodes'),
                          onTap: () => _toggleSubscribe(detail),
                        ),
                      if (_trackingAvailable(detail))
                        _IconAction(
                          icon: _tracked
                              ? CupertinoIcons.arrow_2_circlepath_circle_fill
                              : CupertinoIcons.arrow_2_circlepath,
                          active: _tracked,
                          label: 'Tracking',
                          tooltip: _tracked
                              ? 'Tracked — edit status, score & progress'
                              : 'Sync status, score & progress',
                          onTap: () => _openTrackingSheet(detail),
                        ),
                      _IconAction(
                        icon: CupertinoIcons.share,
                        label: 'Share',
                        tooltip: 'Share',
                        onTap: () => _share(detail, sourceName),
                      ),
                      _IconAction(
                        icon: CupertinoIcons.globe,
                        label: 'Web',
                        tooltip: 'Open source site',
                        onTap: _openSourceSite,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        SliverPersistentHeader(
          pinned: true,
          delegate: _TabBarDelegate(
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: const EdgeInsets.only(left: 16),
              labelPadding: const EdgeInsets.only(right: 24),
              labelColor: AppColors.accent,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorSize: TabBarIndicatorSize.label,
              indicator: UnderlineTabIndicator(
                borderSide: BorderSide(color: AppColors.accent, width: 2.5),
                insets: EdgeInsets.only(left: 2, right: 2, bottom: 8),
              ),
              dividerColor: Colors.transparent,
              dividerHeight: 0,
              splashFactory: NoSplash.splashFactory,
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              labelStyle: AppText.headline.copyWith(fontSize: 15),
              unselectedLabelStyle: AppText.headline.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              tabs: [
                if (showEpisodesTab) Tab(text: isReading ? 'Chapters' : 'Episodes'),
                Tab(text: isReading ? 'Characters' : 'Cast'),
                const Tab(text: 'Relations'),
                const Tab(text: 'Details'),
              ],
            ),
          ),
        ),
      ],
      body: TabBarView(
        controller: _tabController,
        children: [
          if (showEpisodesTab) _EpisodesTab(
            eps: eps,
            seasonEps: seasonEps,
            fillerEps: _fillerEps,
            hasMultipleSeasons: hasMultipleSeasons,
            seasonSet: seasonSet,
            currentSeason: currentSeason,
            onSelectSeason: cubit.selectSeason,
            coverUrl: coverUrl,
            coverHeaders: coverHeaders,
            sourceId: item.sourceId,
            showId: item.id,
            showUrl: item.url,
            resumeIndex: _resumeIndex,
            hasAnyMark: hasAnyMark,
            trackerProgress: _trackerProgress,
            nextAiringEpisode: _nextAiringEpisode,
            nextAiringAt: _nextAiringAt,
            onOpen: (fullIndex) =>
                _openPlayer(eps, fullIndex, detail, category),
            onPickPlayer: isReading
                ? null
                : (fullIndex) =>
                      _pickPlayerFor(eps, fullIndex, detail, category),
            onRefresh: cubit.refresh,
            onDownload: (ep) => isReading
                ? _downloadChapter(ep, detail)
                : _downloadSingle(ep, detail, category),
            onDownloadMany: isReading
                ? (eps) => _downloadChapters(eps, detail)
                : null,
            isReading: isReading,
          ),
          (state.extrasLoading && state.cast.isEmpty && detail.cast.isEmpty)
              ? const _CastSkeletonTab()
              : _CastTab(
            cast: state.cast.isNotEmpty
                ? state.cast
                : [for (final n in detail.cast) CastMember(name: n)],
            onOpenPerson: (ref) => Navigator.of(
              context,
            ).push(PersonPage.route(ref, sourceId: widget.item.sourceId)),
          ),
          (state.extrasLoading && state.relations.isEmpty && detail.relations.isEmpty)
              ? const _RelationsSkeletonTab()
              : _RelationsTab(relations: state.relations.isNotEmpty ? state.relations : detail.relations, onOpen: _openRelation),
          _DetailsTab(
            sourceName: sourceName,
            statusStr: statusLabel(detail.status),
            reading: isReading,
            genres: detail.genres,
            studios: detail.studios,
            episodeCount: eps.length,
            year: detail.year,
            description: detail.description,
          ),
        ],
      ),
    ),
    );
  }
}

/// Checks if a movie is currently in theatrical/cinema release.
bool _isInCinema(MediaDetail? detail) {
  if (detail == null || detail.isSeries) return false;
  // Never infer cinema availability from a recent release date. TMDB's
  // release-type data is the source of truth: OTT/digital releases must not
  // continue to show the movie as being in cinemas.
  return detail.tmdbTheatricalRelease;
}

/// Checks if a title is unreleased ("Coming Soon").
/// - For movies: unreleased TMDB status (e.g. "Post Production", "Planned", "In Production") or future release date.
/// - For TV series: only "Coming Soon" if Episode 1 has not premiered yet (future first air date). Ongoing/released shows always show Play & Download.
/// - For non-TMDB items (TPDB, providers): always shows Play & Download.
bool _isFutureRelease(MediaDetail? detail) {
  if (detail == null) return false;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  if (detail.isSeries) {
    final tmdbStatus = detail.tmdbStatus?.trim().toLowerCase();
    if (tmdbStatus == 'returning series' || tmdbStatus == 'ended') return false;

    if (detail.episodes.isNotEmpty) {
      final firstEp = detail.episodes.first;
      final epDate = firstEp.date?.trim();
      if (epDate != null && epDate.isNotEmpty) {
        final parsed = DateTime.tryParse(epDate);
        if (parsed != null) {
          return parsed.isAfter(today);
        }
      }
      return false;
    }

    final firstAir = detail.releaseDate?.trim();
    if (firstAir != null && firstAir.isNotEmpty) {
      final parsed = DateTime.tryParse(firstAir);
      if (parsed != null) {
        return parsed.isAfter(today);
      }
    }
    return tmdbStatus == 'planned' || tmdbStatus == 'in production';
  }

  final tmdbStatus = detail.tmdbStatus?.trim().toLowerCase();
  if (tmdbStatus != null && tmdbStatus.isNotEmpty) {
    return tmdbStatus != 'released' && tmdbStatus != 'ended';
  }

  final fullDate = detail.releaseDate?.trim();
  if (fullDate != null && fullDate.isNotEmpty) {
    final parsed = DateTime.tryParse(fullDate);
    if (parsed != null) {
      return parsed.isAfter(today);
    }
  }

  return false;
}