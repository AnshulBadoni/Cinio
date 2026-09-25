part of 'detail_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DetailScreenTv — two-pane landscape Detail for Android TV / large screens.
//
// Left pane  (fixed 300 px): poster + title + meta + focusable action buttons.
// Right pane (Expanded):     D-pad-navigable tab bar + tab content.
//
// Rendered in place of [_DetailView] when [AppMode.isTv] is true (gated at the
// top of [_DetailViewState.build]). Reads [DetailCubit] from context — the same
// [BlocProvider] created by [DetailScreen.build] covers both paths; no second
// cubit is created.
//
// Focus architecture (mirrors root_shell_tv.dart):
//   [_leftScope]  — wraps the left action column.
//   [_rightScope] — wraps the right tabs + content area.
//   arrowRight from left  → hand focus to the last-focused right child (or first
//                           traversable right descendant on first entry).
//   arrowLeft  from right → try intra-right traversal first; only cross over to
//                           the left pane when already at the left edge.
// ─────────────────────────────────────────────────────────────────────────────

class DetailScreenTv extends StatefulWidget {
  const DetailScreenTv({super.key, required this.item});
  final MediaItem item;

  @override
  State<DetailScreenTv> createState() => _DetailScreenTvState();
}

class _DetailScreenTvState extends State<DetailScreenTv> {
  int _tab = 0;
  static const _seriesTabLabels = ['Episodes', 'Cast', 'Relations', 'Details'];
  static const _movieTabLabels = ['Cast', 'Relations', 'Details'];

  // Episode search. The query is typed in a DIALOG (opened from the left-pane
  // button) rather than an inline TextField: a focused TextField eats the
  // D-pad arrows for cursor movement, so an inline field TRAPS focus — the
  // tester literally needed a mouse to escape it. A dialog auto-opens the
  // leanback keyboard, applies on Done/submit, and hands focus back cleanly.
  String _epQuery = '';

  // Filler episode numbers (from Jikan by MAL id), for the "FILLER" badge —
  // mirrors phone [_DetailViewState._fillerEps].
  Set<int> _fillerEps = const {};
  int? _fillerForMal;
  void _ensureFiller(int? malId) {
    if (malId == null || malId == _fillerForMal) return;
    _fillerForMal = malId;
    FillerService.instance.fillerEpisodes(malId).then((s) {
      if (mounted && s.isNotEmpty) setState(() => _fillerEps = s);
    });
  }

  Future<void> _openEpisodeSearch() async {
    final ctrl = TextEditingController(text: _epQuery);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Search episodes'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: AppText.body,
          cursorColor: AppColors.accent,
          decoration: InputDecoration(
            hintText: 'Title or episode number',
            hintStyle: AppText.body.copyWith(color: AppColors.textSecondary),
          ),
          onSubmitted: (q) => Navigator.pop(ctx, q),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Clear')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: TextButton.styleFrom(foregroundColor: AppColors.accent),
            child: const Text('Search'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || !mounted) return; // dismissed — keep current query
    setState(() {
      _epQuery = result.trim();
      _tab = 0; // searching implies the Episodes tab
    });
  }

  // ── My List / status ──────────────────────────────────────────────────────
  final MyListStore _myList = sl<MyListStore>();
  final ListStatusStore _listStatus = sl<ListStatusStore>();
  late WatchStatus? _status;
  late bool _inMyList;

  // ── Left ↔ Right focus bridge ─────────────────────────────────────────────
  final FocusScopeNode _leftScope = FocusScopeNode(debugLabel: 'tv-detail-left');
  final FocusScopeNode _rightScope = FocusScopeNode(debugLabel: 'tv-detail-right');

  String? _prefetchedEpUrl;
  bool _actionInFlight = false;

  void _maybePrefetch(String epUrl, String sourceId) {
    if (_prefetchedEpUrl == epUrl) return;
    _prefetchedEpUrl = epUrl;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !sl.isRegistered<SourceRepository>()) return;
      sl<SourceRepository>().prefetch(epUrl, sourceId: sourceId);
    });
  }

  void _maybePrefetchCatalog({String category = 'sub'}) {
    // Background catalog prefetching is disabled to prevent UI freezing.
    // Provider resolution is performed on-demand when starting playback.
  }

  @override
  void initState() {
    super.initState();
    _status = _listStatus.statusOf(widget.item);
    _inMyList = _status != null || _myList.contains(widget.item);
    if (sl.isRegistered<DiscordRpc>()) {
      sl<DiscordRpc>().setBrowsing(title: widget.item.title, posterUrl: widget.item.cover);
    }
  }

  @override
  void dispose() {
    if (sl.isRegistered<DiscordRpc>()) sl<DiscordRpc>().setBrowsing();
    _leftScope.dispose();
    _rightScope.dispose();
    super.dispose();
  }

  // D-pad RIGHT from the left pane → move into the right pane.
  KeyEventResult _onLeftKey(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowRight) {
      final last = _rightScope.focusedChild;
      if (last != null) {
        last.requestFocus();
      } else {
        _rightScope.traversalDescendants.where((n) => n.canRequestFocus).firstOrNull?.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // D-pad LEFT from the right pane: try intra-pane traversal first; only
  // cross to the left pane when already at the left edge.
  KeyEventResult _onRightKey(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      final moved = FocusManager.instance.primaryFocus?.focusInDirection(TraversalDirection.left) ?? false;
      if (!moved) _leftScope.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Resume index (identical to _DetailViewState._resumeIndex) ─────────────
  int _resumeIndex(List<Episode> eps) {
    final store = sl<ResumeStore>();
    int? highestMarked;
    for (int j = 0; j < eps.length; j++) {
      final mark = store.get(widget.item.sourceId, widget.item.url, eps[j].id);
      if (mark != null) highestMarked = j;
    }
    if (highestMarked == null) return 0;
    final mark = store.get(widget.item.sourceId, widget.item.url, eps[highestMarked].id)!;
    if (!mark.finished) return highestMarked;
    if (highestMarked + 1 < eps.length) return highestMarked + 1;
    return highestMarked;
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

  /// Resume target for Play (mirrors _DetailViewState._resumeTarget): local
  /// playback first, else the connected tracker's watched count (single-season).
  ({int index, bool hasResume}) _resumeTarget(List<Episode> eps) {
    if (eps.isEmpty) return (index: 0, hasResume: false);
    final store = sl<ResumeStore>();
    final hasLocal = eps.any((e) => store.get(widget.item.sourceId, widget.item.url, e.id) != null);
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

  // ── Player launch (mirrors _DetailViewState._openPlayer exactly) ──────────
  Future<void> _openPlayer(List<Episode> episodes, int index, MediaDetail detail, String category) async {
    if (_actionInFlight) return;
    _actionInFlight = true;
    try {
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

      final available = <String>[if ((detail.subCount ?? 0) > 0) 'sub', if ((detail.dubCount ?? 0) > 0) 'dub'];
      final availableCategories = available.isEmpty ? [category] : available;
      final preferred =
          sl<TitlePrefsStore>().category(detail.sourceId, detail.url) ??
          sl<PlaybackPrefs>().defaultCategory;
      final launchCategory = availableCategories.contains(preferred)
          ? preferred
          : category;

      Future<({String url, String sourceId})> resolvePlaybackTarget(String u) async {
        if (widget.item.sourceId != 'tmdb:catalog' && !widget.item.sourceId.startsWith('tpdb:')) {
          return (url: u, sourceId: detail.sourceId);
        }
        final resolved = await sl<SourceRepository>().resolveCatalogTitle(
          widget.item,
          category: category,
        );
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

      await launchTvPlayback(
        context: context,
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
        showUrl: detail.url,
        showTitle: detail.title,
        cover: (detail.cover != null && detail.cover!.isNotEmpty) ? detail.cover : widget.item.cover,
        coverHeaders: detail.coverHeaders ?? widget.item.coverHeaders,
        category: launchCategory,
        availableCategories: availableCategories,
        malId: detail.malId ?? widget.item.malId,
        scrobbleTitle: detail.type == ProviderType.anime ? detail.title : null,
        tmdbId: detail.tmdbId ?? widget.item.tmdbId,
        tmdbIsTv: detail.tmdbIsTv,
        imdbId: detail.imdbId ?? widget.item.imdbId,
      );
    } finally {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _actionInFlight = false;
      });
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

  // Tracker-driven episode grey-out (mirrors the phone view).
  int? _trackerProgress;
  bool _trackerFetchStarted = false;

  /// Whether any connected tracker has this title on a list — drives the
  /// Tracking action's icon. Mirrors the phone view.
  bool _tracked = false;

  void _maybeFetchTrackerProgress(MediaDetail detail) {
    if (_trackerFetchStarted) return;
    _trackerFetchStarted = true;
    final hub = sl<TrackerHub>();
    if (!hub.anyConnected) return;
    final isAnime = detail.type == ProviderType.anime;
    final pins = sl<TrackerBindingStore>().get(TrackerBindingStore.keyOf(widget.item.sourceId, widget.item.url));
    hub
        .fetchEntry(
          malId: detail.malId ?? widget.item.malId,
          title: isAnime ? detail.title : null,
          tmdbId: detail.tmdbId ?? widget.item.tmdbId,
          tmdbIsTv: detail.tmdbIsTv,
          imdbId: detail.imdbId ?? widget.item.imdbId,
          pinnedIds: pins.isEmpty ? null : pins,
        )
        .then((e) {
          if (!mounted) return;
          final p = e?.progress;
          setState(() {
            _tracked = e?.onList ?? false;
            if (p != null && p > 0) _trackerProgress = p;
          });
        });
  }

  /// Whether the Tracking action should show — same rule as the phone view: a
  /// tracker is connected AND it can track this title (anime always; movies/TV
  /// only via Simkl with a tmdb/imdb id).
  bool _trackingAvailable(MediaDetail detail) {
    final hub = sl<TrackerHub>();
    if (!hub.anyConnected) return false;
    if (detail.type == ProviderType.anime) return true;
    final simklOn = hub.connected.any((t) => t.displayName == 'Simkl');
    final hasId =
        (detail.tmdbId ?? widget.item.tmdbId) != null || ((detail.imdbId ?? widget.item.imdbId)?.isNotEmpty ?? false);
    return simklOn && hasId;
  }

  /// Open the tracker sync sheet (status / score / episode progress) on TV.
  Future<void> _openTrackingSheet(MediaDetail detail) async {
    final applied = await showTrackerSyncSheet(
      context,
      title: detail.title,
      isAnime: detail.type == ProviderType.anime,
      malId: detail.malId ?? widget.item.malId,
      tmdbId: detail.tmdbId ?? widget.item.tmdbId,
      tmdbIsTv: detail.tmdbIsTv,
      imdbId: detail.imdbId ?? widget.item.imdbId,
      bindingKey: TrackerBindingStore.keyOf(widget.item.sourceId, widget.item.url),
    );
    if (applied != null && mounted && applied > (_trackerProgress ?? 0)) {
      setState(() => _trackerProgress = applied);
    }
    // Re-read: the sheet may have added or removed tracking, and a removal
    // applies nothing for [applied] to report.
    if (!mounted) return;
    _trackerFetchStarted = false;
    _maybeFetchTrackerProgress(detail);
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
        await _pickSourceAndDownload(ep, detail, category);
        return;
      }
      final availableCategories = <String>[if ((detail.subCount ?? 0) > 0) 'sub', if ((detail.dubCount ?? 0) > 0) 'dub'];
      final res = await showModalBottomSheet<({String quality, String category, List<Episode> episodes})>(
        context: context,
        backgroundColor: AppColors.surface,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => _DownloadSheet(
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
              final resolved = await sl<SourceRepository>().resolveCatalogTitle(widget.item, category: category);
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
            return sl<SourceRepository>().sources(epUrl, sourceId: sId);
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
    final isCatalog = widget.item.sourceId == 'tmdb:catalog' || widget.item.sourceId.startsWith('tpdb:');
    final MediaDetail d;
    if (isCatalog) {
      final resolved = await sl<SourceRepository>().resolveCatalogTitle(widget.item, category: category);
      if (resolved == null) return const {};
      d = resolved.detail;
    } else {
      d = await sl<SourceRepository>().detail(widget.item.url, category: category, sourceId: widget.item.sourceId);
    }
    final byS = <int, List<Episode>>{};
    for (final e in d.episodes) {
      (byS[seasonOf(e) ?? 1] ??= <Episode>[]).add(e);
    }
    if (byS.isEmpty) byS[1] = d.episodes;
    return byS;
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

  Future<void> _pickSourceAndDownload(Episode ep, MediaDetail detail, String category) async {
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
            final resolved = await sl<SourceRepository>().resolveCatalogTitle(widget.item, category: category);
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
    unawaited(
      sl<DownloadManager>().enqueueSource(
        sourceId: finalItem.sourceId,
        showId: finalItem.id,
        showTitle: finalDetail.title,
        cover: finalDetail.cover ?? finalItem.cover,
        coverHeaders: finalDetail.coverHeaders ?? finalItem.coverHeaders,
        showUrl: finalItem.url,
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

  void _startDownload(MediaDetail detail, String category, String quality, List<Episode> episodes) {
    final item = widget.item;
    unawaited(
      sl<DownloadManager>().enqueueEpisodes(
        sourceId: item.sourceId,
        showId: item.id,
        showTitle: detail.title,
        cover: detail.cover ?? item.cover,
        coverHeaders: detail.coverHeaders ?? item.coverHeaders,
        showUrl: item.url,
        category: category,
        quality: quality,
        episodes: episodes,
        nowMs: DateTime.now().millisecondsSinceEpoch,
        malId: detail.malId ?? item.malId,
      ),
    );
    _snack(episodes.length == 1 ? 'Added to downloads' : 'Downloading ${episodes.length} episodes');
  }

  Future<void> _openRelation(MediaRelation r) async {
    _snack('Finding "${r.title}"…');
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
        final results = await sl<SourceRepository>().search(r.title, sourceId: widget.item.sourceId);
        if (!mounted) return;
        if (results.isNotEmpty) {
          Navigator.of(context).push(DetailScreen.route(results.first));
          return;
        }
      }

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

      _snack('"${r.title}" isn\'t available');
    } catch (_) {
      if (mounted) _snack('Couldn\'t open "${r.title}"');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(msg, style: AppText.caption.copyWith(color: Colors.white)),
          backgroundColor: AppColors.surface2,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DetailCubit, DetailState>(
      builder: (context, state) {
        if (state.status == DetailStatus.loading) {
          return Scaffold(
            backgroundColor: AppColors.bg,
            body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
          );
        }
        if (state.status == DetailStatus.error || state.detail == null) {
          return Scaffold(
            backgroundColor: AppColors.bg,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const EmptyState(icon: Icons.error_outline, message: 'Failed to load this title'),
                  const SizedBox(height: 16),
                  TvFocusable(
                    autofocus: true,
                    onTap: () => context.read<DetailCubit>().retry(),
                    variant: TvFocusVariant.pill,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text('Retry', style: AppText.button.copyWith(color: AppColors.accent)),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return _buildTwoPane(context, state, state.detail!);
      },
    );
  }

  Widget _buildTwoPane(BuildContext context, DetailState state, MediaDetail detail) {
    final item = widget.item;
    final category = state.category;
    final eps = detail.episodes;
    final showEpisodesTab = detail.isSeries || eps.length > 1;
    final tabLabels = showEpisodesTab ? _seriesTabLabels : _movieTabLabels;
    if (_tab >= tabLabels.length) _tab = tabLabels.length - 1;
    final store = sl<ResumeStore>();
    // Kick the (cached, once-per-malId) filler lookup for the FILLER badge.
    _ensureFiller(detail.malId ?? item.malId);
    // Once-per-detail tracker-progress lookup for episode grey-out.
    _maybeFetchTrackerProgress(detail);

    // Resume / play label (mirrors _DetailViewState._buildBody).
    final resume = _resumeTarget(eps);
    final resumeIdx = resume.index;

    // Warm stream / catalog match in background
    if (eps.isNotEmpty &&
        !(item.sourceId == 'tmdb:catalog' || item.sourceId.startsWith('tpdb:'))) {
      _maybePrefetch(eps[resumeIdx].url, item.sourceId);
    } else if (item.sourceId == 'tmdb:catalog' || item.sourceId.startsWith('tpdb:')) {
      _maybePrefetchCatalog(category: category);
    }

    final hasAnyMark = eps.any((e) => store.get(item.sourceId, item.url, e.id) != null);
    final episodeNum = eps.isNotEmpty ? (eps[resumeIdx].number?.toInt() ?? resumeIdx + 1) : 1;
    final resumePercent = detail.isSeries ? null : _resumePercent(eps, resumeIdx);
    final buttonLabel = detail.isSeries
        ? (resume.hasResume ? 'Continue E$episodeNum' : 'Play E$episodeNum')
        : (resume.hasResume
            ? (resumePercent != null ? 'Continue $resumePercent%' : 'Continue')
            : 'Play');

    // Cover.
    final coverUrl = detail.cover ?? item.cover ?? '';
    final coverHeaders = detail.coverHeaders ?? item.coverHeaders;

    // Season data (mirrors _DetailViewState._buildBody).
    final seasonSet = seasonsOf(eps, detail.availableSeasons);
    final hasMultipleSeasons = seasonSet.length > 1;
    final currentSeason = hasMultipleSeasons
        ? (seasonSet.contains(state.selectedSeason) ? state.selectedSeason : seasonSet.first)
        : 1;
    final seasonEps = hasMultipleSeasons ? eps.where((e) => seasonOf(e) == currentSeason).toList() : eps;

    final episodesBySeason = <int, List<Episode>>{};
    if (hasMultipleSeasons) {
      for (final e in eps) {
        (episodesBySeason[seasonOf(e) ?? 1] ??= <Episode>[]).add(e);
      }
    } else {
      episodesBySeason[1] = eps;
    }

    final sourceName = _sourceLabel(item.sourceId);
    final statusStr = statusLabel(detail.status);

    // Meta line (mirrors _DetailViewState._buildBody).
    final metaParts = <String>[];
    if ((detail.year ?? '').isNotEmpty) metaParts.add(detail.year!);
    if (hasMultipleSeasons) {
      metaParts.add('${seasonSet.length} Seasons');
    } else if (eps.isNotEmpty && detail.isSeries) {
      metaParts.add('${eps.length} Episode${eps.length == 1 ? '' : 's'}');
    }
    if (statusStr.isNotEmpty) metaParts.add(statusStr);
    final metaLine = metaParts.join('  ·  ');

    return Scaffold(
      backgroundColor: AppColors.bg,
      // Stack overlays a D-pad-focusable TvBackButton at the top-left so the
      // user can go back with OK in addition to the remote Back key.  autofocus
      // is intentionally false so the Play button keeps its initial autofocus.
      body: Stack(
        children: [
          SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── LEFT pane: poster + title + meta + action buttons ─────────
                Focus(
                  focusNode: _leftScope,
                  onKeyEvent: _onLeftKey,
                  child: SizedBox(
                    width: 300,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Poster (2:3 aspect, fills available space)
                        Expanded(
                          flex: 5,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: coverUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: coverUrl,
                                      cacheManager: AppImageCache.cacheManagerOrDefault,
                                      httpHeaders: coverHeaders,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      memCacheWidth: 400,
                                      placeholder: (_, _) => ColoredBox(color: AppColors.surface2),
                                      errorWidget: (_, _, _) => ColoredBox(color: AppColors.surface2),
                                    )
                                  : ColoredBox(color: AppColors.surface2),
                            ),
                          ),
                        ),
                        // Title + meta + action buttons
                        Expanded(
                          flex: 4,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(20, 14, 12, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  detail.title,
                                  style: AppText.headline.copyWith(fontSize: 18),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (metaLine.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    metaLine,
                                    style: AppText.caption.copyWith(color: AppColors.textSecondary),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                const SizedBox(height: 16),
                                if (state.error == 'load_failed') ...[
                                  TvFocusable(
                                    onTap: () => context.read<DetailCubit>().retry(),
                                    variant: TvFocusVariant.pill,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: AppColors.surface2,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.refresh_rounded, size: 16, color: AppColors.accent),
                                          const SizedBox(width: 8),
                                          Text('Retry loading details', style: AppText.caption.copyWith(color: AppColors.accent)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                // Play button — autofocus: always the first focused
                                // element when the detail screen opens on TV.
                                if (_isFutureRelease(detail)) ...[
                                  TvFocusable(
                                    key: const ValueKey('tv-detail-coming-soon'),
                                    autofocus: true,
                                    variant: TvFocusVariant.pill,
                                    onTap: () {},
                                    semanticLabel: 'Coming Soon',
                                    child: const ExcludeSemantics(
                                      child: _ComingSoonButton(),
                                    ),
                                  ),
                                ] else ...[
                                  // Play button
                                  TvFocusable(
                                    key: const ValueKey('tv-detail-play'),
                                    autofocus: true,
                                    variant: TvFocusVariant.pill,
                                    onTap: (eps.isNotEmpty ||
                                            widget.item.sourceId == 'tmdb:catalog' ||
                                            widget.item.sourceId.startsWith('tpdb:'))
                                        ? () => _openPlayer(eps, resumeIdx, detail, category)
                                        : () {},
                                    semanticLabel: buttonLabel,
                                    // _PlayButton is shared with the phone view —
                                    // exclude its own label Text here instead of
                                    // touching the widget, so semanticLabel above
                                    // is the only thing TalkBack hears.
                                    child: ExcludeSemantics(
                                      child: _PlayButton(
                                        label: buttonLabel,
                                        onPressed: (eps.isNotEmpty ||
                                                widget.item.sourceId == 'tmdb:catalog' ||
                                                widget.item.sourceId.startsWith('tpdb:'))
                                            ? () => _openPlayer(eps, resumeIdx, detail, category)
                                            : null,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  // Download button
                                  TvFocusable(
                                    key: const ValueKey('tv-detail-download'),
                                    variant: TvFocusVariant.pill,
                                    onTap: () => _openDownloadSheet(
                                      detail: detail,
                                      category: category,
                                      episodesBySeason: episodesBySeason,
                                      initialSeason: currentSeason,
                                    ),
                                    semanticLabel: 'Download',
                                    // _DownloadButton is shared with the phone
                                    // view — exclude its Text, same as Play above.
                                    child: ExcludeSemantics(
                                      child: _DownloadButton(
                                        label: 'Download',
                                        onPressed: () => _openDownloadSheet(
                                          detail: detail,
                                          category: category,
                                          episodesBySeason: episodesBySeason,
                                          initialSeason: currentSeason,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                // Episode search is only meaningful for episodic titles.
                                if (showEpisodesTab) TvFocusable(
                                  key: const ValueKey('tv-detail-ep-search'),
                                  variant: TvFocusVariant.pill,
                                  onTap: _openEpisodeSearch,
                                  semanticLabel: _epQuery.isEmpty ? 'Search episodes' : 'Search: $_epQuery',
                                  // _IconAction is shared with the phone view —
                                  // exclude its own label, same as Play above.
                                  child: ExcludeSemantics(
                                    child: _IconAction(
                                      icon: _epQuery.isEmpty ? Icons.search_rounded : Icons.filter_alt_rounded,
                                      active: _epQuery.isNotEmpty,
                                      label: _epQuery.isEmpty ? 'Search episodes' : 'Search: $_epQuery',
                                      tooltip: 'Search episodes',
                                      onTap: _openEpisodeSearch,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                // My List button (same icon-over-label as phone)
                                TvFocusable(
                                  key: const ValueKey('tv-detail-mylist'),
                                  variant: TvFocusVariant.pill,
                                  onTap: () => _openListSheet(detail),
                                  semanticLabel: _status?.shortLabel ?? 'My List',
                                  // _IconAction is shared with the phone view —
                                  // exclude its own label, same as Play above.
                                  child: ExcludeSemantics(
                                    child: _IconAction(
                                      icon: _inMyList ? Icons.check_rounded : Icons.add_rounded,
                                      active: _inMyList,
                                      label: _status?.shortLabel ?? 'My List',
                                      tooltip: _inMyList ? 'Change status' : 'Add to My List',
                                      onTap: () => _openListSheet(detail),
                                    ),
                                  ),
                                ),
                                if (_trackingAvailable(detail)) ...[
                                  const SizedBox(height: 10),
                                  // Tracker sync — status / score / progress
                                  // pushed to every connected tracker.
                                  TvFocusable(
                                    key: const ValueKey('tv-detail-tracking'),
                                    variant: TvFocusVariant.pill,
                                    onTap: () => _openTrackingSheet(detail),
                                    semanticLabel: 'Tracking',
                                    child: ExcludeSemantics(
                                      child: _IconAction(
                                        icon: _tracked ? Icons.published_with_changes_rounded : Icons.sync_rounded,
                                        active: _tracked,
                                        label: 'Tracking',
                                        tooltip: _tracked
                                            ? 'Tracked — edit status, score '
                                                  '& progress'
                                            : 'Sync status, score & progress',
                                        onTap: () => _openTrackingSheet(detail),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1, color: AppColors.hairline),
                // ── RIGHT pane: focusable tab bar + content ────────────────────
                Expanded(
                  child: Focus(
                    focusNode: _rightScope,
                    onKeyEvent: _onRightKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Tab bar — each label is a TvFocusable. Wrapped in a
                        // horizontal scroll so it never overflows on narrow screens.
                        SizedBox(
                          height: 56,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                            child: Row(
                              children: [
                                for (int i = 0; i < tabLabels.length; i++)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: TvFocusable(
                                      key: ValueKey('tv-detail-tab-$i'),
                                      variant: TvFocusVariant.pill,
                                      onTap: () => setState(() => _tab = i),
                                      semanticLabel: tabLabels[i],
                                      builder: (focused) => Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        // Excluded — semanticLabel above
                                        // already announces the tab name.
                                        child: ExcludeSemantics(
                                          child: Text(
                                            tabLabels[i],
                                            style: AppText.headline.copyWith(
                                              fontSize: 15,
                                              // Active tab reads from bright
                                              // white + bold, not a red tint.
                                              color: focused
                                                  ? Colors.black
                                                  : (_tab == i ? AppColors.textPrimary : AppColors.textSecondary),
                                              fontWeight: _tab == i ? FontWeight.w700 : FontWeight.w500,
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
                        const Divider(height: 1, color: AppColors.hairline),
                        // Tab content
                        Expanded(
                          child: IndexedStack(
                            index: _tab,
                            children: [
                              // ── Episodes ──────────────────────────────────────
                              if (showEpisodesTab) _TvEpisodeList(
                                key: const ValueKey('tv-detail-episodes'),
                                eps: eps,
                                seasonEps: seasonEps,
                                fillerEps: _fillerEps,
                                query: _epQuery,
                                hasMultipleSeasons: hasMultipleSeasons,
                                seasonSet: seasonSet,
                                currentSeason: currentSeason,
                                onSelectSeason: context.read<DetailCubit>().selectSeason,
                                sourceId: item.sourceId,
                                showId: item.id,
                                showUrl: item.url,
                                coverUrl: coverUrl,
                                coverHeaders: coverHeaders,
                                hasAnyMark: hasAnyMark,
                                resumeIndex: _resumeIndex,
                                trackerProgress: _trackerProgress,
                                onOpen: (i) => _openPlayer(eps, i, detail, category),
                                onDownload: (ep) => _pickSourceAndDownload(ep, detail, category),
                              ),
                              // ── Cast ─────────────────────────────────────────
                              (state.extrasLoading && state.cast.isEmpty && detail.cast.isEmpty)
                                  ? const _CastSkeletonTab()
                                  : _CastTab(
                                cast: state.cast.isNotEmpty
                                    ? state.cast
                                    : [for (final n in detail.cast) CastMember(name: n)],
                              ),
                              // ── Relations ──────────────────────────────────
                              (state.extrasLoading && state.relations.isEmpty && detail.relations.isEmpty)
                                  ? const _RelationsSkeletonTab()
                                  : _RelationsTab(relations: state.relations.isNotEmpty ? state.relations : detail.relations, onOpen: _openRelation, tvFocus: true),
                              // ── Details ────────────────────────────────────
                              _DetailsTab(
                                sourceName: sourceName,
                                statusStr: statusStr,
                                genres: detail.genres,
                                studios: detail.studios,
                                episodeCount: eps.length,
                                showEpisodeCount: showEpisodesTab,
                                year: detail.year,
                                description: detail.description,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ), // SafeArea
          const Positioned(top: 8, left: 8, child: SafeArea(child: TvBackButton())),
        ], // Stack children
      ), // Stack (body)
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TV episode list — each row is a [TvFocusable]-wrapped [_EpisodeRow] so
// D-pad up/down + OK navigates and plays. Long seasons use the same 50-episode
// range chips as mobile [_EpisodesTab]. Uses the SAME [_EpisodeRow] widget the
// phone Detail uses, so the visual design is byte-for-byte identical.
// ─────────────────────────────────────────────────────────────────────────────

class _TvEpisodeList extends StatefulWidget {
  const _TvEpisodeList({
    super.key,
    required this.eps,
    required this.seasonEps,
    required this.fillerEps,
    required this.hasMultipleSeasons,
    required this.seasonSet,
    required this.currentSeason,
    required this.onSelectSeason,
    required this.sourceId,
    required this.showId,
    required this.showUrl,
    required this.coverUrl,
    required this.coverHeaders,
    required this.hasAnyMark,
    required this.resumeIndex,
    required this.onOpen,
    required this.onDownload,
    this.trackerProgress,
    this.query = '',
  });

  final List<Episode> eps;
  final List<Episode> seasonEps;
  final Set<int> fillerEps;
  final bool hasMultipleSeasons;
  final Set<int> seasonSet;
  final int currentSeason;
  final ValueChanged<int> onSelectSeason;
  final String sourceId;
  final String showId;
  final String showUrl;
  final String coverUrl;
  final Map<String, String>? coverHeaders;
  final bool hasAnyMark;
  final int Function(List<Episode>) resumeIndex;

  /// Connected tracker's watched-episode count (grey-out); null when none.
  final int? trackerProgress;
  final void Function(int fullIndex) onOpen;
  final void Function(Episode ep) onDownload;

  /// Episode search query (typed in the left pane's dialog). Same matcher as
  /// the phone: title substring or episode number.
  final String query;

  @override
  State<_TvEpisodeList> createState() => _TvEpisodeListState();
}

class _TvEpisodeListState extends State<_TvEpisodeList> {
  int _rangeIndex = 0;

  List<Episode> get _filteredEps => filterEpisodes(widget.seasonEps, widget.query);

  int _initialRange() {
    if (!widget.hasAnyMark || widget.seasonEps.isEmpty) return 0;
    final resumeEp = widget.eps[widget.resumeIndex(widget.eps)];
    final local = _filteredEps.indexOf(resumeEp);
    return episodeRangeIndex(local);
  }

  @override
  void initState() {
    super.initState();
    _rangeIndex = _initialRange();
  }

  @override
  void didUpdateWidget(covariant _TvEpisodeList old) {
    super.didUpdateWidget(old);
    if (old.currentSeason != widget.currentSeason ||
        old.query != widget.query ||
        old.seasonEps.length != widget.seasonEps.length) {
      _rangeIndex = _initialRange();
    } else {
      final maxRange = episodeRangeCount(_filteredEps.length);
      if (maxRange > 0 && _rangeIndex > maxRange - 1) {
        _rangeIndex = maxRange - 1;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final eps = widget.eps;
    final filtered = _filteredEps;
    if (widget.seasonEps.isEmpty) {
      return const EmptyState(icon: Icons.video_library_outlined, message: 'No episodes available from this source');
    }
    final store = sl<ResumeStore>();
    final total = filtered.length;
    final rangeCount = episodeRangeCount(total);
    final showRanges = rangeCount > 1;
    final maxRange = rangeCount == 0 ? 0 : rangeCount - 1;
    final rangeIndex = _rangeIndex.clamp(0, maxRange);
    final slice = episodeRangeSlice(rangeIndex, total);
    final visible = total == 0 ? filtered : filtered.sublist(slice.start, slice.end);

    final Widget listView;
    if (filtered.isEmpty) {
      listView = const EmptyState(icon: Icons.search_off_rounded, message: 'No episodes match your search');
    } else {
      listView = ListView.builder(
        padding: const EdgeInsets.only(bottom: 32),
        itemCount: visible.length,
        itemBuilder: (context, i) {
          final ep = visible[i];
          final fullIndex = eps.indexOf(ep);
          final mark = store.get(widget.sourceId, widget.showUrl, ep.id);
          final inProgress = mark != null && !mark.finished && mark.duration > Duration.zero;
          final watched =
              (mark != null && mark.finished) ||
              (widget.trackerProgress != null &&
                  !widget.hasMultipleSeasons &&
                  ep.number != null &&
                  ep.number!.toInt() <= widget.trackerProgress!);
          final resume = widget.hasAnyMark && fullIndex == widget.resumeIndex(eps);
          final fraction = inProgress
              ? (mark.position.inMilliseconds / mark.duration.inMilliseconds).clamp(0.0, 1.0)
              : 0.0;
          final epNum = ep.number?.toInt() ?? (fullIndex + 1);
          final displayTitle = widget.hasMultipleSeasons ? cleanTitle(ep.title) : ep.title;
          final heading = displayTitle.isNotEmpty ? '$epNum. $displayTitle' : 'Episode $epNum';
          return TvListFocusable(
            key: ValueKey('tv-ep-$fullIndex'),
            onTap: () => widget.onOpen(fullIndex),
            semanticLabel: heading,
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: _EpisodeRow(
                  ep: ep,
                  epNum: epNum,
                  displayTitle: displayTitle,
                  filler: widget.fillerEps.contains(epNum),
                  coverUrl: widget.coverUrl,
                  coverHeaders: widget.coverHeaders,
                  isWatched: watched,
                  isInProgress: inProgress,
                  isResume: resume,
                  fraction: fraction,
                  onTap: () => widget.onOpen(fullIndex),
                  onDownload: () => widget.onDownload(ep),
                  sourceId: widget.sourceId,
                  showId: widget.showId,
                  isTv: true,
                ),
              ),
            ),
          );
        },
      );
    }

    final chips = <Widget>[];
    if (widget.hasMultipleSeasons) {
      chips.add(
        _TvSeasonChips(
          seasons: widget.seasonSet.toList()..sort(),
          currentSeason: widget.currentSeason,
          onSelect: widget.onSelectSeason,
        ),
      );
    }
    if (showRanges) {
      chips.add(
        TvEpisodeRangeChips(
          count: rangeCount,
          selected: rangeIndex,
          labelFor: (i) => episodeRangeLabel(filtered, i),
          onSelect: (i) => setState(() => _rangeIndex = i),
        ),
      );
    }

    if (chips.isEmpty) return listView;

    return Column(
      children: [
        const SizedBox(height: 16),
        ...chips,
        const SizedBox(height: 16),
        Expanded(child: listView),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TV season chip row — a horizontal scrollable row of [TvFocusable] season
// pills.  Shown above the episode list when a title has multiple seasons.
// ─────────────────────────────────────────────────────────────────────────────

class _TvSeasonChips extends StatelessWidget {
  const _TvSeasonChips({required this.seasons, required this.currentSeason, required this.onSelect});

  final List<int> seasons;
  final int currentSeason;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: seasons.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final s = seasons[i];
          final selected = s == currentSeason;
          return TvFocusable(
            key: ValueKey('tv-season-$s'),
            variant: TvFocusVariant.pill,
            onTap: () => onSelect(s),
            semanticLabel: 'Season $s',
            builder: (focused) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                // Current season = solid white chip (black text); focus adds the
                // pill scale-up on top. No red.
                color: focused ? null : (selected ? Colors.white : AppColors.surface2),
                borderRadius: BorderRadius.circular(20),
              ),
              // Excluded — semanticLabel above already announces the season.
              child: ExcludeSemantics(
                child: Text(
                  'Season $s',
                  style: AppText.caption.copyWith(
                    color: focused ? Colors.black : (selected ? Colors.black : AppColors.textPrimary),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
