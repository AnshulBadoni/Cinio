import 'dart:async';
import 'dart:io';

import 'package:palette_generator/palette_generator.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart' show CupertinoPicker, CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:dio/dio.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/metadata/tmdb.dart';

import '../../core/ui/native_cover_provider.dart';
import '../../core/ui/jump_prompt.dart';
import '../../core/ui/poster_card.dart';
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
import '../downloads/downloads_screen.dart';
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
import '../../core/metadata/metadata_enrichment.dart';
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
import '../../core/state/active_source_cubit.dart';
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
part 'detail_screen_desktop.dart';

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
  if (targetDetail.sourceId.startsWith('stremio:')) {
    final addonId = targetDetail.sourceId.substring('stremio:'.length);
    final imdbId = targetDetail.imdbId ?? targetItem.imdbId;
    if (imdbId != null && imdbId.isNotEmpty) {
      final s = seasonOf(origEp) ?? 1;
      final epNum = origEp.number?.toInt() ?? 1;
      final isTv = targetDetail.isSeries || targetItem.tmdbIsTv || origEp.season != null;
      final url = isTv
          ? 'stremio://$addonId/stream/series/$imdbId:$s:$epNum'
          : 'stremio://$addonId/stream/movie/$imdbId';
      return Episode(
        id: isTv ? '$imdbId:$s:$epNum' : imdbId,
        number: origEp.number,
        title: origEp.title.trim().isNotEmpty ? origEp.title : targetDetail.title,
        url: url,
        season: origEp.season,
      );
    }
  }
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
  const DetailScreen({
    super.key,
    required this.item,
    this.trailerContext,
    this.catalogDetail,
    this.heroTag,
  });
  final MediaItem item;
  final DetailTrailerContext? trailerContext;
  final MediaDetail? catalogDetail;
  final String? heroTag;

  static Route<void> route(
    MediaItem item, {
    DetailTrailerContext? trailerContext,
    MediaDetail? catalogDetail,
    String? heroTag,
  }) {
    final effectiveHeroTag = sl<AppMode>().isTv ? null : heroTag;
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 350),
      reverseTransitionDuration: const Duration(milliseconds: 270),
      pageBuilder: (_, _, _) => DetailScreen(
        item: item,
        trailerContext: trailerContext,
        catalogDetail: catalogDetail,
        heroTag: effectiveHeroTag,
      ),
      transitionsBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        if (effectiveHeroTag != null && effectiveHeroTag.isNotEmpty) {
          // When a Hero is flying into the top banner, keep the route unscaled
          // so the Hero lands with sub-pixel precision while content fades in.
          return FadeTransition(
            opacity: curved,
            child: child,
          );
        }
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
  }

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
        heroTag: heroTag,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DetailView — StatefulWidget for the scroll-driven app-bar title fade and the
// four-tab layout (Episodes / Cast / Relations / Details).
// ─────────────────────────────────────────────────────────────────────────────

class _DetailView extends StatefulWidget {
  const _DetailView({
    required this.item,
    this.trailerContext,
    this.catalogDetail,
    this.heroTag,
  });
  final MediaItem item;
  final DetailTrailerContext? trailerContext;
  final MediaDetail? catalogDetail;
  final String? heroTag;

  @override
  State<_DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<_DetailView>
    with TickerProviderStateMixin {
  double _expandedHeightFor({required bool isReading, required bool hasDownload}) {
    if (isReading) return 510.0;
    return 570.0;
  }

  bool _showAppBarTitle = false;
  final ValueNotifier<double> _heroStretch = ValueNotifier<double>(0.0);
  late final AnimationController _entranceController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _entranceAnimation = CurvedAnimation(
    parent: _entranceController,
    curve: Curves.easeOutCubic,
  );
  bool _hasStartedContentEntrance = false;

  void _triggerContentEntrance() {
    if (_hasStartedContentEntrance) return;
    final route = ModalRoute.of(context);
    final routeAnimation = route?.animation;

    if (routeAnimation != null && !routeAnimation.isCompleted) {
      void onRouteStatus(AnimationStatus status) {
        if (status == AnimationStatus.completed) {
          routeAnimation.removeStatusListener(onRouteStatus);
          if (mounted && !_hasStartedContentEntrance) {
            _hasStartedContentEntrance = true;
            _entranceController.forward(from: 0.0);
          }
        }
      }

      routeAnimation.addStatusListener(onRouteStatus);
    } else {
      _hasStartedContentEntrance = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _entranceController.forward(from: 0.0);
        }
      });
    }
  }

  String? _titleLogoUrl;
  String? _titleLogoKey;
  Color? _titleAccent;
  String? _titleAccentKey;
  static final Map<String, Color> _paletteCache = {};

  String? _prefetchedEpUrl;
  bool _actionInFlight = false;
  List<TrailerInfo> _trailers = const [];
  bool _descExpanded = false;

  Set<int> _fillerEps = const {};
  int? _fillerForMal;
  void _ensureFiller(MediaDetail detail, MediaItem item) {
    final malId = detail.malId ?? item.malId;
    if (malId != null) {
      if (malId == _fillerForMal) return;
      _fillerForMal = malId;
      FillerService.instance.fillerEpisodes(malId).then((s) {
        if (mounted && s.isNotEmpty) setState(() => _fillerEps = s);
      });
      return;
    }

    if (detail.type == ProviderType.anime || item.type == ProviderType.anime) {
      sl<MetadataEnrichment>().resolveMalId(detail).then((resolved) {
        if (resolved != null && mounted) {
          if (resolved == _fillerForMal) return;
          _fillerForMal = resolved;
          FillerService.instance.fillerEpisodes(resolved).then((s) {
            if (mounted && s.isNotEmpty) setState(() => _fillerEps = s);
          });
        }
      });
    }
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

        final trailers = await sl<TrailerService>()
            .fetchAllTrailers(
              title: detail.title,
              englishTitle: detail.englishTitle,
              type: detail.type,
              year: detail.year,
              tmdbId: detail.tmdbId ?? widget.item.tmdbId,
              isTv: detail.tmdbIsTv || widget.item.tmdbIsTv,
            );
        if (mounted && trailers.isNotEmpty) {
          setState(() {
            _trailers = trailers;
            if (_trailerSource == null) {
              _trailerSource = trailers.first.toSource();
            }
          });
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
    _entranceController.dispose();
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
    final isCatalog = widget.item.sourceId == 'tmdb:catalog' || widget.item.sourceId.startsWith('tpdb:');
    if (!isCatalog) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      sl<SourceRepository>().resolveCatalogTitle(widget.item, category: category);
    });
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

  String? _seasonPosterUrl;
  String? _seasonPosterKey;

  void _loadSeasonPoster(MediaDetail detail, int seasonNumber) {
    final tmdbId = detail.tmdbId ?? widget.item.tmdbId;
    if (tmdbId == null) return;
    final isTv = detail.tmdbIsTv || widget.item.tmdbIsTv || detail.isSeries;
    if (!isTv) return;
    final key = '$tmdbId:$seasonNumber';
    if (_seasonPosterKey == key) return;
    _seasonPosterKey = key;
    final cached = sl<TmdbDiscoverService>().getCachedSeasonPoster(tmdbId, seasonNumber);
    if (cached != null && cached.isNotEmpty && _seasonPosterUrl != cached) {
      setState(() => _seasonPosterUrl = cached);
      return;
    }
    sl<TmdbDiscoverService>().seasonPoster(tmdbId, seasonNumber).then((url) {
      if (!mounted || _seasonPosterKey != key) return;
      if (url != null && url.isNotEmpty) {
        setState(() => _seasonPosterUrl = url);
      }
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
    try {
      return await sl<SourceRepository>().resolveCatalogTitle(
        catalog,
        category: category,
      ).timeout(const Duration(seconds: 10), onTimeout: () => null);
    } catch (_) {
      return null;
    }
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

      ({MediaItem item, MediaDetail detail})? cachedResolved;
      Future<({String url, String sourceId})> resolvePlaybackTarget(String u) async {
        if (widget.item.sourceId != 'tmdb:catalog' && !widget.item.sourceId.startsWith('tpdb:')) {
          return (url: u, sourceId: detail.sourceId);
        }
        final resolved = cachedResolved ??= await _resolveCatalogPlayback(category: category);
        if (resolved == null) {
          return (url: u, sourceId: detail.sourceId);
        }
        final targetSourceId = resolved.item.sourceId;

        if (targetSourceId.startsWith('stremio:')) {
          final addonId = targetSourceId.substring('stremio:'.length);
          final imdbId = resolved.item.imdbId ?? detail.imdbId ?? widget.item.imdbId;
          if (imdbId != null && imdbId.isNotEmpty) {
            Episode? origEp;
            for (final e in eps) {
              if (e.url == u || e.id == u) {
                origEp = e;
                break;
              }
            }
            final isTv = detail.isSeries || widget.item.tmdbIsTv || (origEp != null && origEp.season != null);
            if (isTv) {
              final s = (origEp != null ? seasonOf(origEp) : null) ?? 1;
              final epNum = origEp?.number?.toInt() ?? 1;
              return (url: 'stremio://$addonId/stream/series/$imdbId:$s:$epNum', sourceId: targetSourceId);
            } else {
              return (url: 'stremio://$addonId/stream/movie/$imdbId', sourceId: targetSourceId);
            }
          }
        }

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

  DownloadRecord? _downloadedRecordFor(Episode? ep, MediaDetail detail) {
    if (!sl.isRegistered<DownloadManager>()) return null;
    final all = sl<DownloadManager>().all;
    final itemTitle = widget.item.title.trim().toLowerCase();
    final detailTitle = detail.title.trim().toLowerCase();
    if (detail.isSeries && ep != null) {
      for (final r in all) {
        final rTitle = r.showTitle.trim().toLowerCase();
        final matchShow = r.showId == widget.item.id ||
            rTitle == itemTitle ||
            rTitle == detailTitle;
        final matchEp = r.episodeId == ep.id ||
            (r.episodeNumber != null && ep.number != null && r.episodeNumber == ep.number);
        if (matchShow && matchEp && r.status == DownloadStatus.done && r.filePath != null) {
          return r;
        }
      }
      return null;
    }
    // Movie / single
    for (final r in all) {
      final rTitle = r.showTitle.trim().toLowerCase();
      final matchShow = r.showId == widget.item.id ||
          rTitle == itemTitle ||
          rTitle == detailTitle;
      if (matchShow && r.status == DownloadStatus.done && r.filePath != null) {
        return r;
      }
    }
    return null;
  }

  String _downloadLabel(
    MediaDetail detail,
    List<Episode> seasonEps,
    bool hasMultipleSeasons,
    int currentSeason, {
    bool isDownloaded = false,
  }) {
    if (isDownloaded) return 'Downloaded';
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
      d = resolved.detail.episodes.isNotEmpty
          ? resolved.detail
          : await sl<SourceRepository>().detail(resolved.item.url, category: category, sourceId: resolved.item.sourceId);
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

          final isCloudStream = targetDetail.sourceId.startsWith('cs:') || targetDetail.sourceId.startsWith('cloudstream:');
          if (isCloudStream) {
            var done = false;
            var pollTries = 0;
            final knownUrls = s.map((e) => e.url).toSet();

            while (!done && pollTries < 4) {
              await Future.delayed(const Duration(milliseconds: 700));
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
    if (sl<AppMode>().isDesktop) return DetailScreenDesktop(item: widget.item);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: BlocBuilder<DetailCubit, DetailState>(
        builder: (context, state) {
          if (state.status == DetailStatus.loading) {
            final isReading = widget.item.type == ProviderType.manga ||
                widget.item.type == ProviderType.novel;
            return _DetailSkeleton(
              heroHeight: _expandedHeightFor(
                isReading: isReading,
                hasDownload: !isReading,
              ),
              coverUrl: widget.item.heroImage ?? widget.item.cover,
              coverHeaders: widget.item.coverHeaders,
              heroTag: widget.heroTag,
              entranceAnimation: kAlwaysCompleteAnimation,
            );
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
          if (state.detail == null) {
            return _DetailSkeleton(
              heroHeight: 450,
              entranceAnimation: kAlwaysCompleteAnimation,
            );
          }
          return _buildBody(context, state, state.detail!);
        },
      ),
    );
  }


  Widget _titleHeader(MediaDetail detail, {bool compact = false}) {
    final logo = _titleLogoUrl;
    final maxW = compact ? 200.0 : 310.0;
    if (logo != null && logo.isNotEmpty) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxW,
          maxHeight: compact ? 32 : 80,
        ),
        child: CachedNetworkImage(
          imageUrl: logo,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          fadeInDuration: const Duration(milliseconds: 220),
          placeholder: (_, _) => _styledFallbackTitle(
            detail,
            fontSize: compact ? 16 : 26.6,
            maxLines: compact ? 1 : 3,
          ),
          errorWidget: (_, _, _) => _styledFallbackTitle(
            detail,
            fontSize: compact ? 16 : 26.6,
            maxLines: compact ? 1 : 3,
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW),
      child: _styledFallbackTitle(
        detail,
        fontSize: compact ? 16 : 26.6,
        maxLines: compact ? 1 : 3,
      ),
    );
  }

  Widget _styledFallbackTitle(
    MediaDetail detail, {
    double fontSize = 24.7,
    int maxLines = 3,
  }) {
    final seed = detail.tmdbId ?? widget.item.tmdbId ?? detail.title;
    final accent = _titleAccent ?? AppColors.textPrimary;
    return cinioFallbackTitle(
      title: detail.title,
      seed: seed,
      accent: accent,
      genres: detail.genres,
      fontSize: fontSize,
      maxLines: maxLines,
    );
  }

  Widget _buildBody(
    BuildContext context,
    DetailState state,
    MediaDetail detail,
  ) {
    _triggerContentEntrance();
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
    final seasonEps = filteredBySeason;

    final detailKey = '${detail.sourceId}:${detail.id}:$currentSeason:${detail.malId}';
    if (_postFrameForDetailKey != detailKey) {
      _postFrameForDetailKey = detailKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureFiller(detail, item);
        _maybeFetchTrackerProgress(detail);
        _loadTitleAccent(detail);
        _loadSeasonPoster(detail, currentSeason);
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

    final coverUrl = _seasonPosterUrl ?? detail.cover ?? item.cover ?? '';
    final heroCoverUrl = _seasonPosterUrl ?? item.heroImage ?? coverUrl;
    final coverHeaders = detail.coverHeaders ?? item.coverHeaders;
    final hasCover = heroCoverUrl.isNotEmpty;

    final episodesBySeason = <int, List<Episode>>{};
    if (hasMultipleSeasons) {
      for (final e in eps) {
        (episodesBySeason[seasonOf(e) ?? 1] ??= <Episode>[]).add(e);
      }
    } else {
      episodesBySeason[1] = eps;
    }

    final currentEp = eps.isNotEmpty ? eps[resumeIdx] : null;
    final downloadedRec = _downloadedRecordFor(currentEp, detail);
    final isDownloaded = downloadedRec != null;

    final downloadLabel = _downloadLabel(
      detail,
      seasonEps,
      hasMultipleSeasons,
      currentSeason,
      isDownloaded: isDownloaded,
    );


    final sourceName = _sourceLabel(item.sourceId);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis == Axis.vertical) {
          if (notification.metrics.pixels < 0) {
            _heroStretch.value = (-notification.metrics.pixels).clamp(0.0, 320.0);
          } else if (_heroStretch.value > 0) {
            _heroStretch.value = 0.0;
          }
        }
        return false;
      },
      child: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
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
            clipBehavior: Clip.none,
            leadingWidth: 68,
            leading: _HeroContentEntrance(
              animation: _entranceAnimation,
              fadeOnly: true,
              child: Padding(
                padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
                child: Center(
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _showAppBarTitle
                          ? Colors.transparent
                          : Colors.black.withValues(alpha: 0.55),
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(CupertinoIcons.chevron_back, color: Colors.white, size: 21),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
              ),
            ),
            title: AnimatedOpacity(
              opacity: _showAppBarTitle ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 220),
              child: _titleHeader(detail, compact: true),
            ),
            centerTitle: true,
            actions: const [],
            flexibleSpace: _Hero(
              heroTag: widget.heroTag,
              coverUrl: heroCoverUrl,
              coverHeaders: coverHeaders,
              hasCover: hasCover,
              trailer: _trailerSource,
              collapsed: _showAppBarTitle,
              stretch: _heroStretch,
              entranceAnimation: _entranceAnimation,
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
                      constraints: const BoxConstraints(maxWidth: 300, maxHeight: 78),
                      child: _titleHeader(detail),
                    ),
                  ),
                  if (detail.genres.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      detail.genres.take(3).join(' • '),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (_isFutureRelease(detail))
                    const _ComingSoonButton()
                  else
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(24),
                                onTap: (eps.isNotEmpty ||
                                        widget.item.sourceId == 'tmdb:catalog' ||
                                        widget.item.sourceId.startsWith('tpdb:'))
                                    ? () {
                                        if (downloadedRec != null) {
                                          launchDownloadedEpisode(context, downloadedRec);
                                        } else {
                                          _openPlayer(eps, resumeIdx, detail, category);
                                        }
                                      }
                                    : null,
                                onLongPress: () async {
                                  if (downloadedRec != null) {
                                    _openPlayer(eps, resumeIdx, detail, category);
                                  } else if (widget.item.sourceId == 'tmdb:catalog' ||
                                      widget.item.sourceId.startsWith('tpdb:')) {
                                    final picked = await _showProviderPickerSheet(detail, category: category);
                                    if (picked != null && mounted) {
                                      _openPlayer(picked.detail.episodes, 0, picked.detail, category);
                                    }
                                  }
                                },
                                child: Center(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        isReading
                                            ? CupertinoIcons.book_fill
                                            : CupertinoIcons.play_arrow_solid,
                                        color: Colors.black,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        buttonLabel,
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.16),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.more_horiz, color: Colors.white, size: 24),
                            onPressed: () => _openMoreActionsSheet(
                              detail,
                              category: category,
                              eps: eps,
                              episodesBySeason: episodesBySeason,
                              currentSeason: currentSeason,
                              downloadLabel: downloadLabel,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: ValueListenableBuilder<double>(
              valueListenable: _heroStretch,
              builder: (context, overscroll, child) => Transform.translate(
                offset: Offset(0, overscroll),
                child: child,
              ),
              child: _HeroContentEntrance(
                animation: _entranceAnimation,
                offsetY: 32.0,
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
                    _buildMetadataRow(detail),
                    _buildCreditsSection(detail),
                    _buildSynopsisSection(detail),
                    _buildCastSection(state.cast.isNotEmpty ? state.cast : [for (final n in detail.cast) CastMember(name: n)]),
                    _buildTrailersSection(),
                    if (!isReading && (detail.isSeries || hasMultipleSeasons || eps.length > 1))
                      _buildSeasonsAndEpisodesSection(
                        detail: detail,
                        eps: eps,
                        seasonEps: seasonEps,
                        seasonSet: seasonSet,
                        currentSeason: currentSeason,
                        hasMultipleSeasons: hasMultipleSeasons,
                        heroCoverUrl: heroCoverUrl,
                        coverHeaders: coverHeaders,
                        cubit: cubit,
                        category: category,
                        resumeIdx: resumeIdx,
                        hasAnyMark: hasAnyMark,
                      )
                    else if (isReading)
                      _buildReadingChaptersSection(
                        detail: detail,
                        eps: eps,
                        seasonEps: seasonEps,
                        currentSeason: currentSeason,
                        cubit: cubit,
                        resumeIdx: resumeIdx,
                      ),
                    _buildDetailsTable(detail, sourceName),
                    _buildRelationsSection(state.relations.isNotEmpty ? state.relations : detail.relations),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openMoreActionsSheet(
    MediaDetail detail, {
    required String category,
    required List<Episode> eps,
    required Map<int, List<Episode>> episodesBySeason,
    required int currentSeason,
    required String downloadLabel,
  }) {
    final isReading = detail.type == ProviderType.manga || detail.type == ProviderType.novel;
    final sourceName = _sourceLabel(widget.item.sourceId);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(
                _inMyList ? CupertinoIcons.checkmark_alt : CupertinoIcons.plus,
                color: _inMyList ? AppColors.accent : Colors.white,
              ),
              title: Text(
                _inMyList
                    ? 'In My List (${_status == null ? "Added" : shortLabelFor(_status!, reading: isReading)})'
                    : 'Add to My List',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _openListSheet(detail);
              },
            ),
            if (!isReading)
              ListTile(
                leading: const Icon(Icons.download_rounded, color: Colors.white),
                title: Text(downloadLabel, style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _openDownloadSheet(
                    detail: detail,
                    category: category,
                    episodesBySeason: episodesBySeason,
                    initialSeason: currentSeason,
                  );
                },
              ),
            if (Platform.isAndroid)
              ListTile(
                leading: Icon(
                  _subscribed ? CupertinoIcons.bell_fill : CupertinoIcons.bell,
                  color: _subscribed ? AppColors.accent : Colors.white,
                ),
                title: Text(
                  _subscribed ? 'Notifications Enabled' : 'Notify on Releases',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _toggleSubscribe(detail);
                },
              ),
            if (_trackingAvailable(detail))
              ListTile(
                leading: Icon(
                  _tracked ? CupertinoIcons.arrow_2_circlepath_circle_fill : CupertinoIcons.arrow_2_circlepath,
                  color: _tracked ? AppColors.accent : Colors.white,
                ),
                title: const Text('Tracking & Sync', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _openTrackingSheet(detail);
                },
              ),
            if (widget.item.sourceId == 'tmdb:catalog' || widget.item.sourceId.startsWith('tpdb:'))
              ListTile(
                leading: const Icon(Icons.source_rounded, color: Colors.white),
                title: const Text('Change Provider', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final picked = await _showProviderPickerSheet(detail, category: category);
                  if (picked != null && mounted) {
                    _openPlayer(picked.detail.episodes, 0, picked.detail, category);
                  }
                },
              ),
            ListTile(
              leading: const Icon(CupertinoIcons.share, color: Colors.white),
              title: const Text('Share', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _share(detail, sourceName);
              },
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.globe, color: Colors.white),
              title: const Text('Open Source Webpage', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _openSourceSite();
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataRow(MediaDetail detail) {
    final year = detail.year ??
        (detail.releaseDate != null && detail.releaseDate!.length >= 4
            ? detail.releaseDate!.substring(0, 4)
            : null);
    final runtime = detail.runtime;
    final runtimeStr = runtime != null && runtime > 0
        ? '${runtime ~/ 60}h ${runtime % 60}m'
        : null;
    final cert = detail.certification;
    final rating = detail.rating;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (year != null && year.isNotEmpty) ...[
            Text(
              detail.isSeries ? '$year-' : year,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 14),
          ],
          if (runtimeStr != null) ...[
            Text(
              runtimeStr,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 14),
          ],
          if (cert != null && cert.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.28),
                  width: 1,
                ),
              ),
              child: Text(
                cert,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(width: 14),
          ],
          if (rating != null && rating > 0)
            _buildImdbBadge(rating, fontSize: 13, badgeFontSize: 10),
        ],
      ),
    );
  }

  Widget _buildCreditsSection(MediaDetail detail) {
    final director = detail.director;
    final writer = detail.writer;
    if ((director == null || director.isEmpty) && (writer == null || writer.isEmpty)) {
      if (detail.studios.isNotEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Studio: ', style: TextStyle(color: Colors.white60, fontSize: 13)),
                TextSpan(
                  text: detail.studios.join(', '),
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (director != null && director.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Director: ', style: TextStyle(color: Colors.white60, fontSize: 13)),
                    TextSpan(
                      text: director,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          if (writer != null && writer.isNotEmpty)
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Writer: ', style: TextStyle(color: Colors.white60, fontSize: 13)),
                  TextSpan(
                    text: writer,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSynopsisSection(MediaDetail detail) {
    final desc = (detail.description ?? '').trim();
    if (desc.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedCrossFade(
            firstChild: Text(
              desc,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                height: 1.48,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            secondChild: Text(
              desc,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                height: 1.48,
              ),
            ),
            crossFadeState: _descExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => setState(() => _descExpanded = !_descExpanded),
            behavior: HitTestBehavior.opaque,
            child: Text(
              _descExpanded ? 'Show Less' : 'Show More',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCastSection(List<CastMember> cast) {
    if (cast.isEmpty) return const SizedBox.shrink();
    final square = sl<PlaybackPrefs>().peopleCardStyle == 'square';
    final cardW = square ? 84.0 : 76.0;
    final avatarSize = square ? 72.0 : 64.0;
    final listHeight = square ? 138.0 : 128.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Text(
            'Cast',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        SizedBox(
          height: listHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: cast.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              final m = cast[i];
              return GestureDetector(
                onTap: () {
                  final ref = m.person;
                  if (ref != null) {
                    Navigator.of(context).push(
                      PersonPage.route(ref, sourceId: widget.item.sourceId),
                    );
                  }
                },
                child: SizedBox(
                  width: cardW,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(square ? 12 : 999),
                        child: SizedBox(
                          width: avatarSize,
                          height: avatarSize,
                          child: (m.photo != null && m.photo!.isNotEmpty)
                              ? CachedNetworkImage(
                                  imageUrl: m.photo!,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 150,
                                  placeholder: (_, _) => Container(color: AppColors.surface2),
                                  errorWidget: (_, _, _) => const _AvatarFallback(),
                                )
                              : const _AvatarFallback(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        m.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (m.role != null && m.role!.isNotEmpty)
                        Text(
                          m.role!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTrailersSection() {
    if (_trailers.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Text(
            'Trailers',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        SizedBox(
          height: 136,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _trailers.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final t = _trailers[i];
              return GestureDetector(
                onTap: () => _openTrailer(t.toSource()),
                child: SizedBox(
                  width: 172,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CachedNetworkImage(
                                imageUrl: t.thumbnailUrl,
                                fit: BoxFit.cover,
                                placeholder: (_, _) => Container(color: AppColors.surface2),
                                errorWidget: (_, _, _) => Container(color: AppColors.surface2),
                              ),
                              Center(
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black.withValues(alpha: 0.65),
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t.type.isNotEmpty ? t.type : 'Trailer',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  ({bool watched, bool inProgress, bool resume, double fraction}) _computeEpState(
    Episode ep,
    int fullIndex,
    int resumeIdx,
    MediaDetail detail,
    bool hasAnyMark,
  ) {
    final store = sl<ResumeStore>();
    final mark = store.get(detail.sourceId, detail.url, ep.id);
    final inProgress = mark != null && !mark.finished && mark.duration > Duration.zero;
    final epNum = ep.number?.toInt();
    final watched = (mark != null && mark.finished) ||
        (_trackerProgress != null && !detail.isSeries && epNum != null && epNum <= _trackerProgress!);
    final isResume = hasAnyMark && resumeIdx >= 0 && fullIndex == resumeIdx;
    final fraction = inProgress
        ? (mark.position.inMilliseconds / mark.duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    return (
      watched: watched,
      inProgress: inProgress,
      resume: isResume,
      fraction: fraction,
    );
  }

  Widget _buildSeasonsAndEpisodesSection({
    required MediaDetail detail,
    required List<Episode> eps,
    required List<Episode> seasonEps,
    required Set<int> seasonSet,
    required int currentSeason,
    required bool hasMultipleSeasons,
    required String heroCoverUrl,
    required Map<String, String>? coverHeaders,
    required DetailCubit cubit,
    required String category,
    required int resumeIdx,
    required bool hasAnyMark,
  }) {
    final visible = seasonEps.isNotEmpty ? seasonEps : eps;
    final indexById = {for (var i = 0; i < eps.length; i++) eps[i].id: i};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Seasons',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C26),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Posters',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (hasMultipleSeasons)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SeasonPosterRow(
              seasons: seasonSet.toList()..sort(),
              currentSeason: currentSeason,
              onSelectSeason: cubit.selectSeason,
              tmdbId: detail.tmdbId ?? widget.item.tmdbId,
              defaultCoverUrl: heroCoverUrl,
              coverHeaders: coverHeaders,
            ),
          ),
        _WideEpisodeCarousel(
          visible: visible,
          offset: 0,
          indexById: indexById,
          resumeIdx: resumeIdx,
          stateFor: (ep, fullIdx) => _computeEpState(ep, fullIdx, resumeIdx, detail, hasAnyMark),
          currentSeason: currentSeason,
          hasMultipleSeasons: hasMultipleSeasons,
          defaultCoverUrl: heroCoverUrl,
          coverHeaders: coverHeaders,
          onOpen: (idx) => _openPlayer(eps, idx, detail, category),
          onPickPlayer: (idx) => _pickPlayerFor(eps, idx, detail, category),
          onDownload: (ep) => _downloadSingle(ep, detail, category),
          fillerEps: _fillerEps,
          sourceId: detail.sourceId,
          showId: detail.id,
          isTv: detail.isSeries || detail.tmdbIsTv,
        ),
      ],
    );
  }

  Widget _buildReadingChaptersSection({
    required MediaDetail detail,
    required List<Episode> eps,
    required List<Episode> seasonEps,
    required int currentSeason,
    required DetailCubit cubit,
    required int resumeIdx,
  }) {
    if (eps.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Text(
            'Chapters (${eps.length})',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: eps.length.clamp(0, 40),
          separatorBuilder: (_, _) => Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
          itemBuilder: (context, i) {
            final ep = eps[i];
            final titleText = ep.title.isNotEmpty ? ep.title : 'Chapter ${ep.number?.toInt() ?? (i + 1)}';
            final isResume = i == resumeIdx;

            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                titleText,
                style: TextStyle(
                  color: isResume ? AppColors.accent : Colors.white,
                  fontSize: 14,
                  fontWeight: isResume ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              subtitle: ep.date != null && ep.date!.isNotEmpty
                  ? Text(
                      ep.date!,
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    )
                  : null,
              trailing: IconButton(
                icon: const Icon(Icons.download_rounded, color: Colors.white60, size: 20),
                onPressed: () => _downloadChapter(ep, detail),
              ),
              onTap: () => _openPlayer(eps, i, detail, 'sub'),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDetailsTable(MediaDetail detail, String sourceName) {
    final isSeries = detail.isSeries || detail.tmdbIsTv;
    final status = detail.tmdbStatus ?? (detail.status != MediaStatus.unknown ? detail.status.name : 'Released');
    final year = detail.year ?? (detail.releaseDate ?? '');
    final runtime = detail.runtime;
    final runtimeStr = runtime != null && runtime > 0
        ? '${runtime ~/ 60}h ${runtime % 60}m'
        : null;
    final cert = detail.certification ?? (isSeries ? 'TV-MA' : 'PG-13');
    final country = detail.originCountry ?? 'US';
    final language = detail.originalLanguage ?? 'EN';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
          child: Text(
            isSeries ? 'Show Details' : 'Movie Details',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        _detailTableRow('Status', status),
        if (year.isNotEmpty) _detailTableRow('Release Info', isSeries ? '$year-' : year),
        if (runtimeStr != null) _detailTableRow('Runtime', runtimeStr),
        if (cert.isNotEmpty) _detailTableRow('Certification', cert),
        if (country.isNotEmpty) _detailTableRow('Origin Country', country),
        if (language.isNotEmpty) _detailTableRow('Original Language', language),
        if (detail.studios.isNotEmpty) _detailTableRow('Studio', detail.studios.join(', ')),
        if (sourceName.isNotEmpty) _detailTableRow('Source', sourceName),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _detailTableRow(String label, String value) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Divider(
          color: Colors.white.withValues(alpha: 0.08),
          height: 1,
          thickness: 0.6,
        ),
      ],
    );
  }

  Widget _buildRelationsSection(List<MediaRelation> relations) {
    if (relations.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Text(
            'More Like This',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: relations.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final r = relations[i];
              return GestureDetector(
                onTap: () => _openRelation(r),
                child: SizedBox(
                  width: 105,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: (r.cover != null && r.cover!.isNotEmpty)
                              ? CachedNetworkImage(
                                  imageUrl: r.cover!,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 220,
                                  placeholder: (_, _) => Container(color: AppColors.surface2),
                                  errorWidget: (_, _, _) => Container(color: AppColors.surface2),
                                )
                              : Container(color: AppColors.surface2),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        r.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
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