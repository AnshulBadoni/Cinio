import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ui/jump_prompt.dart';
import '../../core/util/title_matcher.dart';
import '../../core/app_mode.dart';
import '../../core/cache/app_image_cache.dart';
import '../../core/di/injector.dart';
import '../../core/discord/discord_rpc.dart';
import '../../core/metadata/episode_metadata_service.dart';
import '../../core/metadata/tmdb_discover_service.dart';
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
  // Aniyomi sources (ani:<id>) resolve to their extension's display name;
  // otherwise the detail screen would show the raw "ani:4383278740…" id.
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
    // A disambiguated source's displayName already carries its repo tag, so
    // don't append the repo twice.
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

enum DetailTrailerContext { model, studio }

class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key, required this.item, this.trailerContext, this.catalogDetail});
  final MediaItem item;
  final DetailTrailerContext? trailerContext;
  final MediaDetail? catalogDetail;

  /// Opening transition: the page fades in while sliding up and scaling from
  /// 0.96 — a smooth "rise" into the detail rather than the platform push.
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
// four-tab layout (Episodes / Cast / Relations / Details). The scroll position
// and TabController are pure UI state and stay widget-level; everything
// data-related (detail / category / season / desc-expand) lives in DetailCubit
// and is consumed via BlocBuilder below.
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
  static const double _expandedHeight = 320;
  bool _showAppBarTitle = false;

  // The episode url we've already kicked a background source-prefetch for, so we
  // don't re-fire it on every rebuild (see _maybePrefetch).
  String? _prefetchedEpUrl;
  bool _prefetchedCatalog = false;
  bool _resolvingPlay = false;

  // Filler episode numbers (from Jikan by MAL id), for the "Filler" badge in the
  // episode list. Fetched once per malId; empty for non-anime / unlisted shows.
  Set<int> _fillerEps = const {};
  int? _fillerForMal;
  void _ensureFiller(int? malId) {
    if (malId == null || malId == _fillerForMal) return;
    _fillerForMal = malId;
    FillerService.instance.fillerEpisodes(malId).then((s) {
      if (mounted && s.isNotEmpty) setState(() => _fillerEps = s);
    });
  }

  // Outer scroll position (the hero/header viewport). We listen to THIS instead
  // of a NotificationListener: the listener also fires for the inner TabBarView
  // lists (whose pixels start at 0), which flipped the title back OFF as soon as
  // you scrolled deeper into the episode list. NestedScrollView.controller drives
  // the OUTER viewport only, so its offset stays past the threshold once the hero
  // has collapsed — the title stays visible no matter how far the body scrolls.
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

  // ── My List (status-organised library) ────────────────────────────────────
  final MyListStore _myList = sl<MyListStore>();
  final ListStatusStore _listStatus = sl<ListStatusStore>();
  late WatchStatus? _status = _listStatus.statusOf(widget.item);
  late bool _inMyList = _status != null || _myList.contains(widget.item);

  // ── Trailer (metadata-API lookup) ─────────────────────────────────────────
  // Resolved lazily once per detail load and cached so the hero player doesn't
  // refetch on every rebuild. Yields a YouTube id or null; once it resolves the
  // hero swaps its static cover backdrop for an autoplaying, muted, looping
  // player (Netflix-style).
  Future<TrailerSource?>? _trailerFuture;
  TrailerSource? _trailerSource;

  /// Kick off (once) the trailer lookup for the resolved detail. When it
  /// completes with a non-null source, store it in [_trailerSource] and rebuild so the
  /// hero can mount the trailer player.
  void _resolveTrailer(MediaDetail detail) {
    if (_trailerFuture != null) return;

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

    _trailerFuture = sl<TrailerService>().resolveTrailer(
      title: detail.title,
      englishTitle: detail.englishTitle,
      type: detail.type,
      year: detail.year,
      alternateContext: alternateContext,
      tpdbId: isTpdb ? widget.item.id : null,
    )..then((source) {
          if (!mounted) return;
          if (source != null && source != _trailerSource) {
            setState(() => _trailerSource = source);
          }
        });
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
    // Discord Rich Presence: "Looking at <title>" while this detail is open.
    if (sl.isRegistered<DiscordRpc>()) {
      sl<DiscordRpc>().setBrowsing(
        title: widget.item.title,
        posterUrl: widget.item.cover,
      );
    }
  }

  @override
  void dispose() {
    // Back to generic "Browsing" when leaving the detail.
    if (sl.isRegistered<DiscordRpc>()) sl<DiscordRpc>().setBrowsing();
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  /// Background-resolve [epUrl]'s sources once for this title, AFTER the current
  /// frame (so it never competes with rendering/scrolling), so the next Play
  /// reuses the work. Fire-and-forget; cancelled implicitly by leaving (the
  /// result just lands in the repo's prefetch cache, unused).
  void _maybePrefetch(String epUrl, String sourceId) {
    if (_prefetchedEpUrl == epUrl) return;
    _prefetchedEpUrl = epUrl;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      sl<SourceRepository>().prefetch(epUrl, sourceId: sourceId);
    });
  }

  /// Background-resolve catalog titles (TMDB/TPDB) to the best matching provider
  /// source and warm up the first/resume episode's stream links, so tapping Play
  /// starts instantly (0ms delay).
  void _maybePrefetchCatalog({String category = 'sub'}) {
    final catalog = widget.item;
    if (_prefetchedCatalog) return;
    if (catalog.sourceId != 'tmdb:catalog' && !catalog.sourceId.startsWith('tpdb:')) return;
    _prefetchedCatalog = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        final resolved = await sl<SourceRepository>().resolveCatalogTitle(
          catalog,
          category: category,
        );
        if (!mounted || resolved == null) return;
        final eps = resolved.detail.episodes;
        if (eps.isNotEmpty) {
          final resume = _resumeTarget(eps);
          final resumeIdx = resume.index.clamp(0, eps.length - 1);
          _maybePrefetch(eps[resumeIdx].url, resolved.item.sourceId);
        }
      } catch (_) {}
    });
  }

  // ── Scroll-driven app-bar title fade. PRESERVED EFFECT — reads the outer
  // NestedScrollView offset (Sozo Read's pattern). The title fades in as the
  // hero scrolls past and STAYS in while the body scrolls. ──────────────────
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final shouldShow =
        _scrollController.offset > (_expandedHeight - kToolbarHeight - 24);
    if (shouldShow != _showAppBarTitle) {
      setState(() => _showAppBarTitle = shouldShow);
    }
  }

  /// Switch to [index] AND collapse the header so the tab's content is actually
  /// in view — otherwise tapping "… more"/"Read more" silently changes a tab
  /// that's still below the fold (feels like nothing happened). Animates both
  /// for a smooth transition into the Cast / Details tab.
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

  // ── The 5-icon action row wiring ──────────────────────────────────────────

  /// Open the "Add to List" status sheet (Plan / Watching / Completed / Paused
  /// / Dropped / Remove). Works locally for any title; for anime with a MAL id
  /// and AniList connected, the choice is also pushed to AniList.
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

  // Tracker-driven episode grey-out: the connected tracker's watched-episode
  // count, fetched once after the detail loads (null until then / no match).
  int? _trackerProgress;

  /// Whether any connected tracker has this title on a list. Drives the
  /// Tracking action's icon — separate from [_trackerProgress] because a title
  /// can be tracked at episode 0 (Planning), which is still "tracked".
  bool _tracked = false;

  /// Next episode to air, from the tracker entry fetched for progress. Null
  /// for a finished show, a movie, or a title with no tracker match — the row
  /// hides rather than claiming it doesn't know.
  int? _nextAiringEpisode;
  DateTime? _nextAiringAt;
  bool _trackerFetchStarted = false;

  /// Fetch the connected tracker's episode progress once, so episodes already
  /// watched on AniList/MAL/Simkl grey out even if never played in-app.
  /// Best-effort and additive — a null result changes nothing on screen.
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
      // Same response the progress comes from — the airing fields were already
      // being fetched and thrown away, so showing them costs no extra request.
      // Both null for a finished show, a movie, or a title we couldn't match.
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

  /// Whether the Tracking button should show for [detail]. Only when a tracker
  /// is connected AND it can actually track this title: anime/manga/novel →
  /// always (AniList/MAL resolve by malId or title regardless); movies &
  /// live-action TV → only Simkl, and only with a tmdb/imdb id to key on.
  /// Keeps the button out of the way for everyone else.
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

  /// Open the tracker list — one row per connected tracker, showing what each
  /// one matched, with "Sync all at once" for the original write-to-everything
  /// editor. Anime resolves by MAL id or title; movies/TV via Simkl's
  /// tmdb/imdb id; manga/novel by malId or title (AniList/MAL manga lists).
  /// Returns the applied progress so grey-out can update immediately.
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
    // The sheet can add tracking or remove it, so the icon has to be re-read
    // rather than inferred from [applied] (a removal applies nothing).
    if (!mounted) return;
    _trackerFetchStarted = false;
    _maybeFetchTrackerProgress(detail);
  }

  /// Open a related title. Relations come from a metadata API (not tied to a
  /// provider URL), so we search the CURRENT source for the title and open the
  /// first match's detail. Falls back to a snackbar when nothing is found.
  Future<void> _openRelation(MediaRelation r) async {
    _snack('Opening “${r.title}”…');
    try {
      // Catalog relations are catalog-owned. Never search the active streaming
      // provider for a relation because that can silently open a different
      // title with a similar name.
      if (widget.item.sourceId == 'tmdb:catalog' && r.tmdbId != null) {
        final related = MediaItem(
          id: 'tmdb:${r.tmdbIsTv ? 'tv' : 'movie'}:${r.tmdbId}',
          title: r.title,
          cover: r.cover,
          url: 'tmdb://${r.tmdbIsTv ? 'tv' : 'movie'}/${r.tmdbId}',
          type: ProviderType.movie,
          sourceId: 'tmdb:catalog',
          tmdbId: r.tmdbId,
          tmdbIsTv: r.tmdbIsTv,
        );
        final catalogDetail = await sl<TmdbDiscoverService>().movieDetail(related);
        if (!mounted) return;
        Navigator.of(context).push(DetailScreen.route(related, catalogDetail: catalogDetail));
        return;
      }
      if (widget.item.sourceId == 'tpdb:catalog' && r.catalogId != null) {
        final related = MediaItem(
          id: 'tpdb:movie:${r.catalogId}',
          title: r.title,
          cover: r.cover,
          url: 'tpdb://movie/${r.catalogId}',
          type: ProviderType.movie,
          sourceId: 'tpdb:catalog',
        );
        if (!mounted) return;
        Navigator.of(context).push(DetailScreen.route(related));
        return;
      }

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
      if (match == null) {
        _snack('“${r.title}” isn’t on this source');
        return;
      }
      Navigator.of(context).push(DetailScreen.route(match));
    } catch (_) {
      if (mounted) _snack('Couldn’t open “${r.title}”');
    }
  }

  void _share(MediaDetail detail, String sourceName) {
    // Native OS share sheet with a Zangetsu deep link: on tap it opens the app
    // straight to this title (on its source) if installed, else the Zangetsu
    // site to download. The link carries the item, so sourceName is unused now.
    SharePlus.instance.share(
      ShareParams(text: ShareLink.shareText(widget.item)),
    );
  }

  /// Globe — open the source's web page in the system browser. Falls back to
  /// a snackbar when no usable URL can be derived.
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

  /// Best-effort web URL for the title. Absolute item URLs (CloudStream/JS)
  /// pass through; Aniyomi items store a relative path, so join it onto the
  /// source's base site (mirroring the native `baseUrl + anime.url`).
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

  /// Toggle new-episode (or new-chapter) alerts for this show. On subscribe we
  /// seed the baseline to the current count so only FUTURE ones alert.
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
      await NotificationService.instance.init(); // ask for permission now
      _snack('You’ll be notified of new $unit of “${item.title}”');
    }
    // Mirror CS subs to native so the background worker picks up the change.
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

  // ── Cross-source player launch — PRESERVED EXACTLY ────────────────────────

  /// Resolve every mirror for an episode, behind a blocking spinner.
  ///
  /// Deliberately not the fast path. Fast returns on the first usable link and
  /// leaves the rest resolving in the background, so a chooser built from it
  /// often shows one server out of several — you'd be picking from a list that
  /// isn't finished. Waiting costs a few seconds and shows the real choice.
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
      // A dead source shouldn't leave a spinner on screen; the caller reports
      // the empty result as "no sources found".
      return const [];
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  /// Push a manual watched mark out to whichever trackers are connected.
  ///
  /// Only whole episode numbers: tracker progress is an integer, so a "12.5"
  /// recap or special would either round into a real episode or be rejected.
  /// Same fan-out the player uses when you finish an episode normally.
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
      // Asked for by hand, so it goes out even with auto-tracking off.
      auto: false,
    );
  }

  /// Long-press an episode → choose where it plays, this once. Settings keeps
  /// owning the standing default, so trying VLC on one episode doesn't quietly
  /// rewire every later tap. Dismissing plays nothing — a long-press that
  /// started playback on its own would be a trap.
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
        // Drop the prefetch too, or the next fast resolve consumes it before
        // it ever looks at the resolved cache and hands back the same dead
        // links — the reload would look like it did nothing.
        sl<SourceRepository>().invalidateSources(
          ep.url,
          sourceId: widget.item.sourceId,
          includePrefetch: true,
        );
        // Deliberately no playback: you reload because the links died, and the
        // next thing you usually want is a different mirror. Auto-playing
        // takes that choice away and tends to fail again on the same source.
        // Re-primes in the background so the play you do make is still quick.
        sl<SourceRepository>().prefetch(
          ep.url,
          sourceId: widget.item.sourceId,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Links reloaded')));

      case EpisodeAction.playMirror:
        // Scraping takes seconds, unlike every other row here, so the wait is
        // shown rather than left as a dead long-press.
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
        // The pick applies to this episode and nothing else — no label saved.
        // Remembering it meant re-finding the mirror by label on the next
        // open, and when that list came back without it the language fallback
        // quietly started a different server: pick vidplay, get vidstream.
        // Choosing again per episode is the honest trade.
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
        // Only forward when marking. Trackers store a high-water mark, not a
        // set, so there's no "unwatch episode 12" to send — dropping progress
        // back would be a guess at what the user wanted their list to say.
        if (nowWatched) await _scrobbleUpTo(ep, detail);
        if (!mounted) return;
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nowWatched ? 'Marked as watched' : 'Marked unwatched'),
          ),
        );

      case EpisodeAction.markAboveWatched:
        // Everything up to and including the one held: you came back
        // mid-season and want the backlog cleared, and excluding the episode
        // you pressed would mean marking it separately every time.
        for (var i = 0; i <= index; i++) {
          await resume.setWatched(
            widget.item.sourceId,
            widget.item.url,
            episodes[i].id,
            watched: true,
          );
        }
        // One tracker write for the highest episode, not one per episode —
        // progress is a high-water mark, so the rest are implied and firing
        // twelve updates would just rate-limit the account.
        await _scrobbleUpTo(ep, detail);
        if (!mounted) return;
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Marked ${index + 1} episodes as watched')),
        );
    }
  }

  Future<({MediaItem item, MediaDetail detail})?> _showProviderPickerSheet(
    MediaDetail detail, {
    String category = 'sub',
  }) async {
    return showModalBottomSheet<({MediaItem item, MediaDetail detail})>(
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
    /// Set only by the long-press sheet: play this one episode in this player,
    /// ignoring the Settings default. Null keeps the existing behaviour.
    PlayerChoice? playerOverride,

    /// A mirror picked from the long-press menu, opened instead of the
    /// adaptive default. One-shot — the cubit clears it after this episode.
    VideoSource? initialSource,
  }) async {
    if (_resolvingPlay) return;
    final targetEp = (index >= 0 && index < episodes.length) ? episodes[index] : null;
    final inFlightPromotion = context.read<DetailCubit>().animePromotion;

    if (widget.item.sourceId == 'tmdb:catalog' || widget.item.sourceId.startsWith('tpdb:')) {
      setState(() => _resolvingPlay = true);
      try {
        var resolved = await _resolveCatalogPlayback(category: category);
        if (!mounted) return;
        if (resolved == null) {
          setState(() => _resolvingPlay = false);
          resolved = await _showProviderPickerSheet(detail, category: category);
          if (resolved == null) {
            if (mounted) _snack('No playable provider result found for ${widget.item.title}');
            return;
          }
        }
        detail = resolved.detail;
        episodes = detail.episodes;
        if (episodes.isEmpty) {
          if (!detail.isSeries) {
            episodes = [
              Episode(
                id: resolved.item.id,
                number: 1,
                title: detail.title.trim().isNotEmpty ? detail.title : widget.item.title,
                url: resolved.item.url,
              ),
            ];
          } else {
            _snack('No playable episodes found for ${widget.item.title}');
            return;
          }
        }

        if (targetEp != null && episodes.isNotEmpty) {
          final wantedSeason = seasonOf(targetEp);
          final wantedNumber = targetEp.number;
          var foundIndex = -1;
          for (var i = 0; i < episodes.length; i++) {
            final cand = episodes[i];
            if (cand.number == wantedNumber &&
                (wantedSeason == null || seasonOf(cand) == wantedSeason)) {
              foundIndex = i;
              break;
            }
          }
          if (foundIndex < 0 && wantedNumber != null) {
            for (var i = 0; i < episodes.length; i++) {
              if (episodes[i].number == wantedNumber) {
                foundIndex = i;
                break;
              }
            }
          }
          index = foundIndex >= 0 ? foundIndex : index.clamp(0, episodes.length - 1);
        } else {
          index = index.clamp(0, episodes.length - 1).toInt();
        }
      } finally {
        if (mounted) setState(() => _resolvingPlay = false);
      }
    }
    // Opening something other than where they left off? Offer to look at it
    // without moving their place. Asked here, before the reading/video split,
    // so all three kinds behave the same. Dismissing means "never mind" —
    // neither answer is assumed, and nothing opens.
    final reading =
        detail.type == ProviderType.novel ||
        detail.type == ProviderType.manga ||
        widget.item.type == ProviderType.novel ||
        widget.item.type == ProviderType.manga;
    final resume = reading
        ? _readResumeIndex(episodes)
        : (index: _resumeIndex(episodes), hasResume: _hasVideoResume(episodes));
    var peek = false;
    if (shouldAskBeforeJump(
      resumeIndex: resume.index,
      targetIndex: index,
      hasResume: resume.hasResume,
      askEnabled: jumpPromptEnabled,
    )) {
      final choice = await showJumpPrompt(context, reading: reading);
      if (choice == null || !mounted) return; // dismissed — open nothing
      peek = choice == JumpChoice.peek;
    }

    // Reading types never touch the player — route to the reader instead.
    // Both tap paths (Play button + episode-row onTap) call this same
    // function, so gating it here covers both in one place. Safety-critical:
    // a manga/novel title must never try to resolve video sources. Checks
    // BOTH the loaded detail's type and the search-result item's type —
    // provider JSON isn't normalized, so a source that disagrees between the
    // two still can't reach the player.
    final t = detail.type;
    final it = widget.item.type;
    if (t == ProviderType.novel ||
        t == ProviderType.manga ||
        it == ProviderType.novel ||
        it == ProviderType.manga) {
      // Same auto-add as the video path below — reading titles route out
      // through this early return, so without this they never got it.
      if (sl<PlaybackPrefs>().autoAddToMyList &&
          !IncognitoMode.on &&
          !_myList.contains(widget.item)) {
        _myList.add(widget.item);
        _listStatus.setStatus(widget.item, WatchStatus.watching);
      }
      _openReader(episodes, index, detail, peek: peek);
      return;
    }

    // Auto-add this title to My List (as Watching) on play, if the user opted
    // in — mirrors the tracker auto-scrobble. Skipped in incognito and when it's
    // already listed; fire-and-forget so it never delays playback.
    if (sl<PlaybackPrefs>().autoAddToMyList &&
        !IncognitoMode.on &&
        !_myList.contains(widget.item)) {
      _myList.add(widget.item);
      _listStatus.setStatus(widget.item, WatchStatus.watching);
    }

    // Available sub/dub categories from the detail — lets the PLAYER offer the
    // Sub/Dub switch (the Detail no longer does). Empty/single → treated as a
    // single-category source by the player (no Version section).
    final available = <String>[
      if ((detail.subCount ?? 0) > 0) 'sub',
      if ((detail.dubCount ?? 0) > 0) 'dub',
    ];
    final availableCategories = available.isEmpty ? [category] : available;

    // Fresh play: prefer a saved per-title sub/dub choice, else the global
    // default category, else fall back to the incoming category. Constrain to
    // what's actually offered so single-category titles are a harmless no-op.
    final preferred =
        sl<TitlePrefsStore>().category(detail.sourceId, detail.url) ??
        sl<PlaybackPrefs>().defaultCategory;
    final launchCategory = availableCategories.contains(preferred)
        ? preferred
        : category;

    // Scrobble ids. A movie-typed title from a movie source (e.g. MovieBox) may
    // actually be anime — resolve its MAL id here so AniList/MAL scrobble. We
    // check the detail's in-flight promotion without blocking.
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
        } catch (_) {/* leave as a movie */}
      }
    }
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          playerOverride: playerOverride?.package,
          initialSource: initialSource,
          sourceId: detail.sourceId,
          episodes: episodes,
          startIndex: index,
          resume: sl<ResumeStore>(),
          resolveSources: (u) => sl<SourceRepository>().sources(
            u,
            sourceId: detail.sourceId,
            fast: true,
          ),
          // The resolve above returns on the first usable link so playback
          // starts fast; the remaining mirrors keep resolving natively. This
          // lets the Sources sheet pick them up once they land.
          pollSources: (u) => sl<SourceRepository>().polledSources(
            u,
            sourceId: detail.sourceId,
          ),
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
  }

  /// Routes a reading-type title (manga/novel) to its reader instead of the
  /// player. [chapters] mirrors [_openPlayer]'s `episodes` list; [index] is
  /// the tapped/resume chapter. Prefers `detail.type`; falls back to
  /// `widget.item.type` for the disagreeing-provider-JSON case the guard
  /// above also covers, so a mismatch still lands on the right reader
  /// instead of silently doing nothing.
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
        return; // unreachable — _openPlayer only calls this for reading types
    }
  }

  /// Push the in-app trailer player for a resolved trailer source.
  void _openTrailer(TrailerSource source) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => TrailerScreen(source: source)));
  }

  /// Netflix-style download label for the FIRST episode of the current season,
  /// e.g. "Download S1:E1". Falls back to a plain "Download" when there are no
  /// episodes to reference. (No downloads yet — label only; the button snacks.)
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

  /// Whether video progress exists at all for this title — the jump prompt has
  /// nothing to protect on a title that's never been opened, and
  /// [_resumeIndex] alone can't say, since it returns 0 both for "start over"
  /// and for "you stopped in episode 1".
  bool _hasVideoResume(List<Episode> eps) {
    final store = sl<ResumeStore>();
    for (final e in eps) {
      if (store.get(widget.item.sourceId, widget.item.url, e.id) != null) {
        return true;
      }
    }
    return false;
  }

  /// Walk episodes and return the best resume target index. PRESERVED.
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

  /// Which episode Play opens, and whether that reads as "Continue". Local
  /// playback wins when present (unchanged behaviour); with NO local marks it
  /// falls back to the connected tracker's watched count — resume the first
  /// episode beyond it — so a title you've only progressed on AniList/MAL/Simkl
  /// still says "Continue". Single-season only, same limit as the grey-out.
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

  /// Reading counterpart of [_resumeTarget]: walks the chapters for the
  /// highest one carrying a saved reading position (per-chapter, from
  /// [ReadStore] — the reader's own scroll/page progress), advancing past it
  /// once it's finished — same rule [_resumeIndex] applies to video resume
  /// marks. Keyed the same way [NovelReaderScreen] saves them: showId is
  /// [MediaItem.id], not the show url (see `_openReader`).
  ///
  /// With NO local mark (e.g. this device never opened a chapter, or the
  /// reader's per-chapter position was never saved) it falls back to
  /// [ReadHistory] — the cloud-synced last-read chapter — the same way
  /// [_resumeTarget] falls back to the tracker's watched count for video.
  /// Only when both come up empty does this say "start over" (chapter 0).
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

  // ── Downloads ─────────────────────────────────────────────────────────────

  /// The main Download button. A single movie/episode goes straight to the
  /// server picker; a multi-episode title opens the batch sheet (season chips +
  /// tappable episode selection + quality).
  Future<void> _openDownloadSheet({
    required MediaDetail detail,
    required String category,
    required Map<int, List<Episode>> episodesBySeason,
    required int initialSeason,
  }) async {
    final isCatalog = widget.item.sourceId == 'tmdb:catalog' || widget.item.sourceId.startsWith('tpdb:');
    if (isCatalog) {
      var resolved = await _resolveCatalogPlayback(category: category);
      if (!mounted) return;
      if (resolved == null) {
        resolved = await _showProviderPickerSheet(detail, category: category);
        if (resolved == null) {
          if (mounted) _snack('No downloadable provider result found for ${widget.item.title}');
          return;
        }
      }
      detail = resolved.detail;
      episodesBySeason = <int, List<Episode>>{};
      for (final e in detail.episodes) { (episodesBySeason[seasonOf(e) ?? 1] ??= <Episode>[]).add(e); }
    }
    final total = episodesBySeason.values.fold<int>(0, (a, b) => a + b.length);
    if (total == 0) {
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
    // Sub/Dub the title actually offers; the sheet only shows the toggle when
    // there's more than one. Defaults to the page's current category (seeded
    // from the per-title remembered choice).
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
            // Phone-only Minimal wheel (Settings → Interface). TV stays on the
            // well-tested Classic grid regardless of the pref.
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
            resolve: (ep) => sl<SourceRepository>().sources(
              ep.url,
              sourceId: detail.sourceId,
            ),
            resolveEpisodes: _episodesByCategory,
          ),
        );
    if (res == null || !mounted) return;
    _startDownload(detail, res.category, res.quality, res.episodes);
  }

  /// Re-resolve a title's episodes for a given sub/dub [category] (without
  /// touching the detail page's own toggle), grouped by season.
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

  /// Per-episode / movie download → resolve sources, let the user pick a
  /// server/mirror, then download that exact url + headers.
  Future<void> _downloadSingle(
    Episode ep,
    MediaDetail detail,
    String category,
  ) => _pickSourceAndDownload(ep, detail, category);

  /// Manga/novel chapter → straight to the chapter downloader. No source
  /// picker here: a chapter has one url, not a list of mirrors to choose from.
  Future<void> _downloadChapter(Episode ep, MediaDetail detail) =>
      _downloadChapters([ep], detail);

  /// Same thing for a batch — one queue write for the lot rather than one per
  /// chapter, which is what a "download all" on a long series needs.
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

    final res = await showModalBottomSheet<SourcePickerResult>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SourcePickerSheet(
        title: ep.title.trim().isNotEmpty ? ep.title : detail.title,
        loadingMessage: isCatalog
            ? 'Searching providers for download sources…'
            : 'Resolving download options…',
        resolve: ([onProgress]) async {
          var targetItem = widget.item;
          var targetDetail = detail;
          var targetEp = ep;

          if (isCatalog) {
            var resolved = await _resolveCatalogPlayback(category: category);
            if (resolved == null) {
              resolved = await _showProviderPickerSheet(detail, category: category);
            }
            if (resolved == null) {
              return (
                sources: <VideoSource>[],
                resolvedItem: null,
                resolvedDetail: null,
                resolvedEpisode: null,
                error: 'No download sources found on installed providers',
              );
            }
            targetItem = resolved.item;
            targetDetail = resolved.detail;
            if (targetDetail.episodes.isNotEmpty) {
              Episode? byId;
              for (final candidate in targetDetail.episodes) {
                if (candidate.id == ep.id) { byId = candidate; break; }
              }
              if (byId != null) {
                targetEp = byId;
              } else {
                final wantedSeason = seasonOf(ep);
                final wantedNumber = ep.number;
                Episode? byNumber;
                for (final candidate in targetDetail.episodes) {
                  if (candidate.number == wantedNumber &&
                      (wantedSeason == null || seasonOf(candidate) == wantedSeason)) {
                    byNumber = candidate;
                    break;
                  }
                }
                targetEp = byNumber ?? targetDetail.episodes.first;
              }
            } else {
              targetEp = Episode(
                id: targetItem.id,
                number: 1,
                title: targetDetail.title.trim().isNotEmpty ? targetDetail.title : targetItem.title,
                url: targetItem.url,
              );
            }
          }

          // 1. Initial fast resolve: returns first available mirror(s) within ~1-2s
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

          // 2. Progressive background polling: gather slower mirrors without blocking
          // the user from picking an already-resolved server immediately.
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
            return const _DetailSkeleton(heroHeight: _expandedHeight);
          }
          if (state.detail == null && state.status == DetailStatus.error) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const EmptyState(
                    icon: Icons.error_outline,
                    message: 'Failed to load this title',
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => context.read<DetailCubit>().retry(),
                    icon: Icon(Icons.refresh_rounded, color: AppColors.accent),
                    label: Text('Tap to retry', style: TextStyle(color: AppColors.accent)),
                  ),
                ],
              ),
            );
          }
          if (state.detail == null) return const _DetailSkeleton(heroHeight: _expandedHeight);
          return _buildBody(context, state, state.detail!);
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    DetailState state,
    MediaDetail detail,
  ) {
    final item = widget.item;
    final cubit = context.read<DetailCubit>();
    final category = state.category;
    final selectedSeason = state.selectedSeason;
    final eps = detail.episodes;
    final store = sl<ResumeStore>();
    // Manga/novel: no player, no sub/dub, no video downloads — drives the
    // Play→Read relabel and hides the download affordances below.
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
    // Kick the (cached, once-per-malId) filler lookup for the "Filler" badge.
    _ensureFiller(detail.malId ?? item.malId);
    // Kick the (once-per-detail) tracker-progress lookup for grey-out.
    _maybeFetchTrackerProgress(detail);

    // Resume / play button logic. Local playback first; else fall back to the
    // tracker's watched count (see _resumeTarget). Local case is unchanged.
    // Reading titles use their OWN progress store instead — _resumeTarget's
    // ResumeStore never carries a mark for a chapter, so it would always
    // (harmlessly but wrongly) say "start over".
    final resume = _resumeTarget(eps);
    final readResume = isReading ? _readResumeIndex(eps) : null;
    final resumeIdx = isReading ? readResume!.index : resume.index;
    // Warm the stream for the episode Play will start, in the background, so
    // tapping Play is near-instant. Deferred to after this frame so it can't
    // affect the detail screen's rendering/scroll. Skipped for reading types
    // — prefetch resolves VIDEO sources, and merely opening a manga/novel
    // detail must never fire that against a chapter URL.
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
                : 'Play'));

    // Cover / backdrop.
    final coverUrl = detail.cover ?? item.cover ?? '';
    final coverHeaders = detail.coverHeaders ?? item.coverHeaders;
    final hasCover = coverUrl.isNotEmpty;

    // Kick off the trailer lookup (once). When it resolves, _trailerId is set
    // and the hero swaps its static backdrop for the autoplaying trailer.
    _resolveTrailer(detail);

    // Season data. PRESERVED.
    final seasonSet = seasonsOf(eps, detail.availableSeasons);
    final hasMultipleSeasons = seasonSet.length > 1;
    final currentSeason = hasMultipleSeasons
        ? (seasonSet.contains(selectedSeason)
              ? selectedSeason
              : seasonSet.first)
        : 1;
    final seasonEps = hasMultipleSeasons
        ? eps.where((e) => seasonOf(e) == currentSeason).toList()
        : eps;

    // Episodes grouped by season for the download sheet's season chips.
    final episodesBySeason = <int, List<Episode>>{};
    if (hasMultipleSeasons) {
      for (final e in eps) {
        (episodesBySeason[seasonOf(e) ?? 1] ??= <Episode>[]).add(e);
      }
    } else {
      episodesBySeason[1] = eps;
    }

    // ── Status label (used by the meta line and Details tab) ────────────────
    final statusStr = statusLabel(detail.status);

    // ── Netflix-style meta line: "2010 · 10 Seasons · Completed" ────────────
    // Join only what we actually HAVE with " · " (no faked rating/HD/CC).
    // Seasons when multi-season, else episode count.
    final metaParts = <String>[];
    if ((detail.year ?? '').isNotEmpty) metaParts.add(detail.year!);
    if (hasMultipleSeasons) {
      metaParts.add('${seasonSet.length} Seasons');
    } else if (eps.isNotEmpty && (isReading || detail.isSeries)) {
      // Manga/novel count chapters. Movies have a synthetic E1 internally
      // for playback, but that implementation detail must not appear in UI.
      final unit = isReading ? 'Chapter' : 'Episode';
      metaParts.add('${eps.length} $unit${eps.length == 1 ? '' : 's'}');
    }
    if (statusStr.isNotEmpty) metaParts.add(statusStr);
    final metaLine = metaParts.join('  ·  ');

    // ── Download button label: "Download S{season}:E{n}" when we can derive
    // the first episode of the current season, else a plain "Download". ──────
    final downloadLabel = _downloadLabel(
      detail,
      seasonEps,
      hasMultipleSeasons,
      currentSeason,
    );

    // ── Starring / Creators (Genres fallback) muted lines ───────────────────
    // Prefer enriched cast (AniList/TMDB) when available, else the provider's.
    final castNames = state.cast.isNotEmpty
        ? state.cast.map((c) => c.name).toList()
        : detail.cast;
    final starring = castNames.isNotEmpty ? castNames.take(3).join(', ') : null;
    final starringMore = castNames.length > 3;
    final creators = detail.studios.isNotEmpty
        ? detail.studios.join(', ')
        : null;
    // For anime (or anything without cast) surface Genres instead of an empty
    // Starring line — never show an empty label.
    final genresLine = (starring == null && detail.genres.isNotEmpty)
        ? detail.genres.take(4).join(', ')
        : null;

    // Friendly provider name + its origin repo, so the user can tell which repo
    // a source came from. JS providers live in the registry; CloudStream sources
    // live in the CS manager — without the CS lookup this fell back to the raw
    // sourceId ("cs:Provider@31@tag"), leaking the file-id suffix.
    final sourceName = _sourceLabel(item.sourceId);

    return NestedScrollView(
      controller: _scrollController,
      headerSliverBuilder: (context, _) => [
        // ── 1. Hero: backdrop + overlapping poster + status/total ──────────
        SliverAppBar(
          expandedHeight: _expandedHeight,
          pinned: true,
          backgroundColor: AppColors.bg,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          centerTitle: false,
          titleSpacing: 0,
          // PRESERVED EFFECT: title fades in once the hero scrolls past.
          title: AnimatedOpacity(
            opacity: _showAppBarTitle ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: Text(
              detail.title,
              style: AppText.headline,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          flexibleSpace: FlexibleSpaceBar(
            collapseMode: CollapseMode.parallax,
            background: RepaintBoundary(
              child: _Hero(
                coverUrl: coverUrl,
                coverHeaders: coverHeaders,
                hasCover: hasCover,
                trailer: _trailerSource,
                // Pause the trailer once the hero has scrolled past (reuses
                // the same signal that fades in the app-bar title).
                collapsed: _showAppBarTitle,
                onTapFullscreen: _trailerSource != null
                    ? () => _openTrailer(_trailerSource!)
                    : null,
              ),
            ),
          ),
        ),

        // ── 2. Title + meta line (Netflix header) ──────────────────────────
        SliverToBoxAdapter(
          child: RepaintBoundary(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tapping the title opens the full search pre-filled with it
                  // (current source + all sources, per Search's own scope toggle).
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            SearchScreen(initialQuery: detail.title),
                      ),
                    ),
                    child: Text(
                      detail.title,
                      style: AppText.largeTitle.copyWith(fontSize: 28),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (metaLine.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      metaLine,
                      style: AppText.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        if (state.error == 'load_failed')
          SliverToBoxAdapter(
            child: Padding(
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
          ),

        // ── 3. White Play + gray Download buttons (full-width, stacked) ─────
        // (The hero banner autoplays the trailer; tap it for fullscreen.)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: _isFutureRelease(detail)
                ? const _ComingSoonButton()
                : Column(
                    children: [
                      _PlayButton(
                        label: buttonLabel,
                        loading: _resolvingPlay,
                        icon: isReading
                            ? Icons.menu_book_rounded
                            : Icons.play_arrow_rounded,
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
                      // Reading downloads are out of scope for this plan.
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
                  ),
          ),
        ),

        // ── 4. Synopsis (clamped) + "Read more" → Details tab ───────────────
        if ((detail.description ?? '').isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: _Description(
                text: detail.description!,
                // "Read more" reveals the Details tab (full synopsis) rather
                // than expanding inline; the header stays clamped to 3 lines.
                onReadMore: () => _revealTab(showEpisodesTab ? 3 : 2),
              ),
            ),
          )
        else if (state.extrasLoading)
          SliverToBoxAdapter(
            child: Padding(
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
          ),

        // ── 5. Starring / Creators / Genres muted lines ─────────────────────
        if (starring != null || creators != null || genresLine != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (starring != null)
                    _CreditLine(
                      label: 'Starring',
                      value: starring,
                      more: starringMore,
                      // Tapping the line (or its "… more") reveals the Cast tab.
                      onMore: starringMore ? () => _revealTab(showEpisodesTab ? 1 : 0) : null,
                    ),
                  if (genresLine != null)
                    _CreditLine(label: 'Genres', value: genresLine),
                  if (creators != null)
                    _CreditLine(label: 'Creators', value: creators),
                ],
              ),
            ),
          ),

        // ── 6. Icon-over-label action row (My List / Trailer / Share / Web) ─
        // "Trailer" is a CloudStream-style result action (recloudstream's
        // result fragment exposes a Trailer button); it opens the fullscreen
        // TrailerScreen and only appears once a trailer id has resolved.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _IconAction(
                  icon: _inMyList ? Icons.check_rounded : Icons.add_rounded,
                  active: _inMyList,
                  // Reading-aware: a manga on your list is "Reading", not
                  // "Watching". Display only — the stored status is still
                  // WatchStatus.watching, so My List and the trackers are
                  // untouched, and reading:false returns the plain label
                  // unchanged for anime.
                  label: _status == null
                      ? 'My List'
                      : shortLabelFor(_status!, reading: isReading),
                  tooltip: _inMyList ? 'Change status' : 'Add to My List',
                  onTap: () => _openListSheet(detail),
                ),
                if (Platform.isAndroid)
                  _IconAction(
                    icon: _subscribed
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_none_rounded,
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
                        ? Icons.published_with_changes_rounded
                        : Icons.sync_rounded,
                    active: _tracked,
                    label: 'Tracking',
                    tooltip: _tracked
                        ? 'Tracked — edit status, score & progress'
                        : 'Sync status, score & progress',
                    onTap: () => _openTrackingSheet(detail),
                  ),
                _IconAction(
                  icon: Icons.ios_share_rounded,
                  label: 'Share',
                  tooltip: 'Share',
                  onTap: () => _share(detail, sourceName),
                ),
                _IconAction(
                  icon: Icons.public_rounded,
                  label: 'Web',
                  tooltip: 'Open source site',
                  onTap: _openSourceSite,
                ),
              ],
            ),
          ),
        ),

        // ── 7. Pinned tab bar ───────────────────────────────────────────────
        SliverPersistentHeader(
          pinned: true,
          delegate: _TabBarDelegate(
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              // Hug the left edge: the first tab starts flush with the 16px
              // content gutter (title/synopsis), and labelPadding(right: 24)
              // spaces the tabs apart while keeping them left-anchored —
              // never centered/spread (matches Sozo Read).
              padding: const EdgeInsets.only(left: 16),
              labelPadding: const EdgeInsets.only(right: 24),
              labelColor: AppColors.accent,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorSize: TabBarIndicatorSize.label,
              indicator: UnderlineTabIndicator(
                borderSide: BorderSide(color: AppColors.accent, width: 2.5),
                // Bottom inset lifts the line toward the label. A Tab is 46
                // high for 15px text, so the indicator otherwise draws at the
                // bottom of that box with a visible gap under the word.
                // Raising the line rather than shortening the tab keeps the
                // tap target at its full height.
                insets: EdgeInsets.only(left: 2, right: 2, bottom: 8),
              ),
              // Remove the full-width underline divider under the bar.
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
                // "Cast" means voice actors on an anime; on a manga the tab
                // holds its author, artist and characters, so it says so.
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
          // ── Episodes ──────────────────────────────────────────────────────
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
            // Reading types resolve to a reader, so there's no player to pick.
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
          // ── Cast ────────────────────────────────────────────────────────────
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
          // ── Relations ─────────────────────────────────────────────────────────
          (state.extrasLoading && state.relations.isEmpty && detail.relations.isEmpty)
              ? const _RelationsSkeletonTab()
              : _RelationsTab(relations: state.relations.isNotEmpty ? state.relations : detail.relations, onOpen: _openRelation),
          // ── Details ──────────────────────────────────────────────────────────
          _DetailsTab(
            sourceName: sourceName,
            statusStr: statusStr,
            reading: isReading,
            genres: detail.genres,
            studios: detail.studios,
            episodeCount: eps.length,
            year: detail.year,
            description: detail.description,
          ),
        ],
      ),
    );
  }
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

