// Episodes tab: list and grid rows, season sheet, range chips, jump dialog.
part of 'detail_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Episodes tab — season selector (multi-season) + rich episode rows. PRESERVES
// season filtering and _openPlayer. Sub/Dub selection now lives in the player.
// ─────────────────────────────────────────────────────────────────────────────

class _EpisodesTab extends StatefulWidget {
  const _EpisodesTab({
    required this.eps,
    required this.seasonEps,
    required this.fillerEps,
    required this.hasMultipleSeasons,
    required this.seasonSet,
    required this.currentSeason,
    required this.onSelectSeason,
    required this.coverUrl,
    required this.coverHeaders,
    required this.sourceId,
    required this.showId,
    required this.showUrl,
    required this.resumeIndex,
    required this.hasAnyMark,
    this.trackerProgress,
    this.nextAiringEpisode,
    this.nextAiringAt,
    required this.onOpen,
    this.onPickPlayer,
    this.onRefresh,
    required this.onDownload,
    this.onDownloadMany,
    this.isReading = false,
  });

  final List<Episode> eps;
  final List<Episode> seasonEps;
  final Set<int> fillerEps; // episode numbers that are filler
  final bool hasMultipleSeasons;
  final Set<int> seasonSet;
  final int currentSeason;
  final ValueChanged<int> onSelectSeason;
  final String coverUrl;
  final Map<String, String>? coverHeaders;
  final String sourceId;
  final String showId;
  final String showUrl;
  final int Function(List<Episode>) resumeIndex;
  final bool hasAnyMark;

  /// The connected tracker's watched-episode count, or null. Episodes at or
  /// below it render as watched (grey-out), merged with local playback marks.
  final int? trackerProgress;

  /// Next episode to air and when. Both null unless the title matched a
  /// tracker and is still airing, which is what keeps the row off finished
  /// shows and movies instead of showing an empty countdown.
  final int? nextAiringEpisode;
  final DateTime? nextAiringAt;
  final void Function(int fullIndex) onOpen;

  /// Long-press an episode → pick which player opens it, this once. Null on
  /// the reading path: a chapter opens the reader, so there's nothing to pick.
  final void Function(int fullIndex)? onPickPlayer;

  /// Force-refresh the list past the 10-min source cache (header ↻ button).
  /// Null hides the button.
  final Future<void> Function()? onRefresh;

  /// Per-row download icon → the download sheet for an episode, or a straight
  /// enqueue for a chapter.
  final void Function(Episode ep) onDownload;

  /// Queue a run of chapters in one go. Null for video, where downloading is
  /// per-episode through the source picker.
  final Future<void> Function(List<Episode> eps)? onDownloadMany;

  /// True for reading types — the section header reads "Chapters" instead
  /// of "Episodes" (single-season case only; multi-season keeps the season
  /// pill either way).
  final bool isReading;

  @override
  State<_EpisodesTab> createState() => _EpisodesTabState();
}

class _EpisodesTabState extends State<_EpisodesTab> {
  bool _grid = false;

  /// Selected scanlation group, or null for "All". Several groups release the
  /// same chapter number, so an unfiltered list legitimately reads 1, 1, 2, 2
  /// — picking a group is what makes it a single readable run.
  String? _scanlator;
  int _rangeIndex = 0;
  String? _highlightEpId; // outlines a grid tile right after a jump

  @override
  void initState() {
    super.initState();
    _rangeIndex = _initialRange();
  }

  @override
  void didUpdateWidget(covariant _EpisodesTab old) {
    super.didUpdateWidget(old);
    // Season switched, list updated, or episode instances replaced
    if (old.currentSeason != widget.currentSeason ||
        old.seasonEps.length != widget.seasonEps.length ||
        !identical(old.seasonEps, widget.seasonEps)) {
      if (_scanlator != null && !_scanlators.contains(_scanlator)) {
        _scanlator = null;
      }
      _rangeIndex = _initialRange();
      _highlightEpId = null;
    }
  }

  /// The chunk holding the resume episode, so the tab opens where the user left
  /// off instead of always at episode 1.
  int _initialRange() {
    if (!widget.hasAnyMark || widget.seasonEps.isEmpty || widget.eps.isEmpty) {
      return 0;
    }
    final index = widget.resumeIndex(widget.eps);
    if (index < 0 || index >= widget.eps.length) return 0;

    final resumeEp = widget.eps[index];
    // Against the FILTERED list — the range index addresses what's on screen,
    // and a scanlator filter makes that a different list to seasonEps.
    final local = _filteredEps.indexOf(resumeEp);
    if (local < 0) return 0;
    return episodeRangeIndex(local);
  }

  /// Scanlation groups on offer, first-seen order (O(N) with Set lookups).
  List<String> get _scanlators {
    final seen = <String>{};
    for (final e in widget.seasonEps) {
      final s = e.scanlator?.trim();
      if (s != null && s.isNotEmpty) seen.add(s);
    }
    return seen.toList();
  }

  /// The chapters actually shown. Identical to the source list when no group
  /// is picked, so nothing changes for the titles that have only one.
  List<Episode> get _filteredEps {
    final want = _scanlator;
    if (want == null) return widget.seasonEps;
    final list = [
      for (final e in widget.seasonEps)
        if (e.scanlator?.trim() == want) e,
    ];
    return list.isEmpty ? widget.seasonEps : list;
  }

  /// Reading progress lives in [ReadStore] (page index / scroll permille),
  /// keyed by showId.
  ({bool watched, bool inProgress, bool resume, double fraction}) _readStateFor(
    Episode ep,
  ) {
    final store = sl<ReadStore>();
    final mark = store.get(widget.sourceId, widget.showId, ep.id);
    final done = store.finished(widget.sourceId, widget.showId, ep.id);
    final inProgress = mark != null && !done && mark.total > 0;
    final watched = done ||
        (widget.trackerProgress != null &&
            ep.number != null &&
            ep.number! <= widget.trackerProgress!);
    return (
      watched: watched,
      inProgress: inProgress,
      resume: false,
      fraction: inProgress ? (mark.pos / mark.total).clamp(0.0, 1.0) : 0.0,
    );
  }

  ({bool watched, bool inProgress, bool resume, double fraction}) _stateFor(
    ResumeStore store,
    Episode ep,
    int fullIndex,
    int resumeIdx,
  ) {
    if (widget.isReading) return _readStateFor(ep);
    final mark = store.get(widget.sourceId, widget.showUrl, ep.id);
    final inProgress =
        mark != null && !mark.finished && mark.duration > Duration.zero;
    // Watched = finished locally, OR at/below the tracker's watched count.
    final epNum = ep.number?.toInt();
    final watched = (mark != null && mark.finished) ||
        (widget.trackerProgress != null &&
            !widget.hasMultipleSeasons &&
            epNum != null &&
            epNum <= widget.trackerProgress!);
    final resume =
        widget.hasAnyMark && resumeIdx >= 0 && fullIndex == resumeIdx;
    final fraction = inProgress
        ? (mark.position.inMilliseconds / mark.duration.inMilliseconds).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    return (
      watched: watched,
      inProgress: inProgress,
      resume: resume,
      fraction: fraction,
    );
  }

  Future<void> _jump() async {
    final n = await showDialog<int>(
      context: context,
      builder: (_) => const _JumpDialog(),
    );
    if (n == null || !mounted) return;
    // Match by episode number; fall back to a 1-based position.
    final eps = _filteredEps;
    var local = eps.indexWhere((e) => e.number?.toInt() == n);
    if (local < 0 && n >= 1 && n <= eps.length) local = n - 1;
    if (local < 0) return;
    setState(() {
      _rangeIndex = episodeRangeIndex(local);
      _grid = true; // the grid makes the jumped-to episode easy to spot
      _highlightEpId = eps[local].id;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.seasonEps.isEmpty) {
      return const EmptyState(
        icon: Icons.video_library_outlined,
        message: 'No episodes available from this source',
      );
    }
    final store = sl<ResumeStore>();
    final isTv = sl<AppMode>().isTv;

    final groups = _scanlators;
    if (_scanlator != null && !groups.contains(_scanlator)) {
      _scanlator = null;
    }

    final eps = _filteredEps;
    final total = eps.length;
    final rangeCount = episodeRangeCount(total);
    final maxRange = rangeCount == 0 ? 0 : rangeCount - 1;
    final rangeIndex = _rangeIndex.clamp(0, maxRange);
    final slice = episodeRangeSlice(rangeIndex, total);
    final visible = eps.sublist(slice.start, slice.end);
    final showRanges = rangeCount > 1;

    // Fast O(1) index map to replace repeated linear searches during list building
    final indexById = <String, int>{
      for (var i = 0; i < widget.eps.length; i++) widget.eps[i].id: i,
    };

    // Calculate resume index once per frame instead of per-item
    final resumeIdx = widget.hasAnyMark && widget.eps.isNotEmpty
        ? widget.resumeIndex(widget.eps)
        : -1;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _EpisodesHeader(
            hasMultipleSeasons: widget.hasMultipleSeasons,
            seasons: widget.seasonSet.toList()..sort(),
            currentSeason: widget.currentSeason,
            onSelectSeason: widget.onSelectSeason,
            onRefresh: widget.onRefresh,
            grid: _grid,
            onToggleView: () => setState(() => _grid = !_grid),
            onJump: showRanges ? _jump : null,
            isReading: widget.isReading,
            onBulkDownload: widget.onDownloadMany != null && !isTv
                ? () => _openBulkDownload(eps)
                : null,
          ),
        ),
        if (widget.nextAiringEpisode != null && widget.nextAiringAt != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: AppText.body.copyWith(color: AppColors.textSecondary),
                  children: [
                    TextSpan(text: 'Episode ${widget.nextAiringEpisode} '),
                    const TextSpan(text: 'airs in '),
                    TextSpan(
                      text: airsIn(widget.nextAiringAt!, long: true),
                      style: AppText.body.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (groups.length > 1)
          SliverToBoxAdapter(
            child: _RangeChips(
              count: groups.length + 1,
              selected: _scanlator == null ? 0 : groups.indexOf(_scanlator!) + 1,
              labelFor: (i) => i == 0 ? 'All' : groups[i - 1],
              onSelect: (i) => setState(() {
                _scanlator = i == 0 ? null : groups[i - 1];
                _rangeIndex = 0;
                _highlightEpId = null;
              }),
            ),
          ),
        if (showRanges)
          SliverToBoxAdapter(
            child: _RangeChips(
              count: rangeCount,
              selected: rangeIndex,
              labelFor: (i) => episodeRangeLabel(eps, i),
              onSelect: (i) => setState(() {
                _rangeIndex = i;
                _highlightEpId = null;
              }),
            ),
          ),
        if (_grid)
          _buildGrid(store, visible, slice.start, indexById, resumeIdx)
        else
          _buildList(store, visible, slice.start, indexById, resumeIdx, isTv),
        const SliverToBoxAdapter(child: SizedBox(height: 48)),
      ],
    );
  }

  void _openBulkDownload(List<Episode> eps) {
    final store = sl<ChapterDownloadStore>();
    final pending = eps
        .where((e) => !store.isDownloaded(widget.sourceId, e.url))
        .toList();

    if (pending.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Every chapter is already downloaded')),
        );
      return;
    }

    final counts = [10, 25, 50].where((n) => n < pending.length).toList();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiary.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Download chapters', style: AppText.headline),
                  ),
                  Text(
                    '${pending.length} not saved',
                    style: AppText.caption,
                  ),
                ],
              ),
            ),
            for (final n in counts)
              ListTile(
                leading: Icon(
                  Icons.file_download_outlined,
                  color: AppColors.accent,
                ),
                title: Text(
                  'Next $n',
                  style: AppText.body.copyWith(color: AppColors.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _enqueueAll(pending.take(n).toList());
                },
              ),
            ListTile(
              leading: Icon(
                Icons.download_for_offline_outlined,
                color: AppColors.accent,
              ),
              title: Text(
                'All ${pending.length}',
                style: AppText.body.copyWith(color: AppColors.textPrimary),
              ),
              subtitle: pending.length > 50
                  ? Text(
                      'This will take a while and use a lot of storage',
                      style: AppText.caption,
                    )
                  : null,
              onTap: () {
                Navigator.pop(sheetContext);
                _enqueueAll(pending);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enqueueAll(List<Episode> chapters) async {
    if (chapters.length > 50) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Download ${chapters.length} chapters?', style: AppText.headline),
          content: Text(
            'This runs one chapter at a time and can take a long while. '
            'You can stop it from Downloads.',
            style: AppText.body,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: Text(
                'Cancel',
                style: AppText.button.copyWith(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: Text(
                'Download',
                style: AppText.button.copyWith(color: AppColors.accent),
              ),
            ),
          ],
        ),
      );
      if (ok != true) return;
      if (!mounted) return;
    }
    await widget.onDownloadMany!(chapters);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Queued ${chapters.length} '
            '${chapters.length == 1 ? 'chapter' : 'chapters'}',
          ),
        ),
      );
  }

  Widget _buildList(
    ResumeStore store,
    List<Episode> visible,
    int offset,
    Map<String, int> indexById,
    int resumeIdx,
    bool isTv,
  ) {
    return SliverList.builder(
      itemCount: visible.length,
      itemBuilder: (context, i) {
        final ep = visible[i];
        final fullIndex = indexById[ep.id] ?? 0;
        final st = _stateFor(store, ep, fullIndex, resumeIdx);
        final epNum = ep.number?.toInt() ?? (offset + i + 1);
        final displayTitle = widget.hasMultipleSeasons
            ? cleanTitle(ep.title)
            : ep.title;
        if (widget.isReading) {
          return RepaintBoundary(
            child: _ChapterRow(
              ep: ep,
              number: epNum,
              displayTitle: displayTitle,
              coverUrl: widget.coverUrl,
              coverHeaders: widget.coverHeaders,
              isRead: st.watched,
              isInProgress: st.inProgress,
              fraction: st.fraction,
              onTap: () => widget.onOpen(fullIndex),
              onDownload: () => widget.onDownload(ep),
              sourceId: widget.sourceId,
              isTv: isTv,
            ),
          );
        }
        return RepaintBoundary(
          child: _EpisodeRow(
            ep: ep,
            epNum: epNum,
            displayTitle: displayTitle,
            filler: widget.fillerEps.contains(epNum),
            coverUrl: widget.coverUrl,
            coverHeaders: widget.coverHeaders,
            isWatched: st.watched,
            isInProgress: st.inProgress,
            isResume: st.resume,
            fraction: st.fraction,
            onTap: () => widget.onOpen(fullIndex),
            onLongPress: widget.onPickPlayer == null
                ? null
                : () => widget.onPickPlayer!(fullIndex),
            onDownload: () => widget.onDownload(ep),
            sourceId: widget.sourceId,
            showId: widget.showId,
            isTv: isTv,
          ),
        );
      },
    );
  }

  Widget _buildGrid(
    ResumeStore store,
    List<Episode> visible,
    int offset,
    Map<String, int> indexById,
    int resumeIdx,
  ) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.15,
        ),
        itemCount: visible.length,
        itemBuilder: (context, i) {
          final ep = visible[i];
          final fullIndex = indexById[ep.id] ?? 0;
          final st = _stateFor(store, ep, fullIndex, resumeIdx);
          final epNum = ep.number?.toInt() ?? (offset + i + 1);
          return _EpisodeGridTile(
            number: epNum,
            isWatched: st.watched,
            isInProgress: st.inProgress,
            isResume: st.resume,
            isFiller: ep.filler,
            highlight: _highlightEpId == ep.id,
            fraction: st.fraction,
            onTap: () => widget.onOpen(fullIndex),
            onLongPress: widget.onPickPlayer == null
                ? null
                : () => widget.onPickPlayer!(fullIndex),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Episodes header — Netflix-style season dropdown (multi-season) that opens a
// dark bottom sheet to pick a season, or a plain "Episodes" label otherwise.
// ─────────────────────────────────────────────────────────────────────────────

class _EpisodesHeader extends StatelessWidget {
  const _EpisodesHeader({
    required this.hasMultipleSeasons,
    required this.seasons,
    required this.currentSeason,
    required this.onSelectSeason,
    this.onRefresh,
    required this.grid,
    required this.onToggleView,
    this.onJump,
    this.isReading = false,
    this.onBulkDownload,
  });

  final bool hasMultipleSeasons;
  final List<int> seasons;
  final int currentSeason;
  final ValueChanged<int> onSelectSeason;
  final Future<void> Function()? onRefresh;
  final bool grid;
  final VoidCallback onToggleView;
  final VoidCallback? onJump;
  final bool isReading;
  final VoidCallback? onBulkDownload;

  Widget _circle(IconData icon, VoidCallback onTap, {String? semanticLabel}) =>
      Semantics(
        button: true,
        label: semanticLabel,
        child: Material(
          color: AppColors.surface2,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(icon, color: AppColors.textPrimary, size: 20),
            ),
          ),
        ),
      );

  Future<void> _openSheet(BuildContext context) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surface,
      barrierColor: Colors.black54,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) =>
          _SeasonSheet(seasons: seasons, currentSeason: currentSeason),
    );
    if (picked != null) onSelectSeason(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: hasMultipleSeasons
                  ? Material(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(10),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _openSheet(context),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Season $currentSeason',
                                style: AppText.headline,
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: AppColors.textPrimary,
                                size: 22,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : Text(
                      isReading ? 'Chapters' : 'Episodes',
                      style: AppText.headline,
                    ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onBulkDownload != null) ...[
                _circle(
                  Icons.download_rounded,
                  onBulkDownload!,
                  semanticLabel: 'Download chapters',
                ),
                const SizedBox(width: 8),
              ],
              if (onJump != null) ...[
                _circle(
                  Icons.search_rounded,
                  onJump!,
                  semanticLabel: 'Find episode',
                ),
                const SizedBox(width: 8),
              ],
              _circle(
                grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
                onToggleView,
                semanticLabel: grid ? 'List view' : 'Grid view',
              ),
              const SizedBox(width: 8),
              if (onRefresh != null) ...[
                _circle(
                  Icons.refresh_rounded,
                  () {
                    onRefresh!();
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(
                            isReading
                                ? 'Refreshing chapters…'
                                : 'Refreshing episodes…',
                          ),
                          duration: const Duration(milliseconds: 1200),
                        ),
                      );
                  },
                  semanticLabel: isReading
                      ? 'Refresh chapters'
                      : 'Refresh episodes',
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// Dark, rounded-top bottom sheet listing the available seasons.
class _SeasonSheet extends StatelessWidget {
  const _SeasonSheet({required this.seasons, required this.currentSeason});

  final List<int> seasons;
  final int currentSeason;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textTertiary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Seasons', style: AppText.title),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: seasons.length,
              itemBuilder: (context0, i) {
                final s = seasons[i];
                final selected = s == currentSeason;
                return InkWell(
                  onTap: () => Navigator.of(context0).pop(s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Season $s',
                            style: AppText.body.copyWith(
                              color: selected
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (selected)
                          Icon(
                            Icons.check_rounded,
                            color: AppColors.accent,
                            size: 22,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Range chips — horizontal "1–50 / 51–100 / …" selector for long seasons.
// ─────────────────────────────────────────────────────────────────────────────

class _RangeChips extends StatelessWidget {
  const _RangeChips({
    required this.count,
    required this.selected,
    required this.labelFor,
    required this.onSelect,
  });

  final int count;
  final int selected;
  final String Function(int) labelFor;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final sel = i == selected;
          return Material(
            color: sel ? AppColors.accent : AppColors.surface2,
            borderRadius: BorderRadius.circular(9),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onSelect(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Center(
                  child: Text(
                    labelFor(i),
                    style: AppText.caption.copyWith(
                      color: sel ? Colors.white : AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Compact episode-number tile for the grid view.
// ─────────────────────────────────────────────────────────────────────────────

class _EpisodeGridTile extends StatelessWidget {
  const _EpisodeGridTile({
    required this.number,
    required this.isWatched,
    required this.isInProgress,
    required this.isResume,
    required this.isFiller,
    required this.highlight,
    required this.fraction,
    required this.onTap,
    this.onLongPress,
  });

  final int number;
  final bool isWatched;
  final bool isInProgress;
  final bool isResume;
  final bool isFiller;
  final bool highlight;
  final double fraction;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final bg = isResume
        ? AppColors.accent
        : (isWatched ? AppColors.surface : AppColors.surface2);
    final fg = isResume
        ? Colors.white
        : (isWatched ? AppColors.textTertiary : AppColors.textPrimary);
    final side = highlight
        ? BorderSide(color: AppColors.accent, width: 2)
        : (isResume
              ? BorderSide.none
              : const BorderSide(color: AppColors.hairline, width: 0.5));

    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: side,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          children: [
            Center(
              child: Text(
                '$number',
                style: AppText.body.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (isWatched && !isResume)
              const Positioned(
                top: 4,
                right: 4,
                child: Icon(
                  Icons.check_rounded,
                  size: 13,
                  color: AppColors.textTertiary,
                ),
              ),
            if (isFiller)
              const Positioned(
                top: 6,
                left: 6,
                child: SizedBox(
                  width: 6,
                  height: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.textTertiary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            if (isInProgress)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _ThumbnailProgressBar(fraction: fraction),
              ),
          ],
        ),
      ),
    );
  }
}

// Small number-input dialog for "jump to episode".
class _JumpDialog extends StatefulWidget {
  const _JumpDialog();

  @override
  State<_JumpDialog> createState() => _JumpDialogState();
}

class _JumpDialogState extends State<_JumpDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(int.tryParse(_ctrl.text.trim()));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Go to episode', style: AppText.headline),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        style: AppText.body.copyWith(color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Episode number',
          hintStyle: AppText.body.copyWith(color: AppColors.textTertiary),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: AppText.body),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(
            'Go',
            style: AppText.body.copyWith(color: AppColors.accent),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reading (manga/novel) chapter row.
// ─────────────────────────────────────────────────────────────────────────────

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({
    required this.ep,
    required this.number,
    required this.displayTitle,
    required this.coverUrl,
    required this.coverHeaders,
    required this.isRead,
    required this.isInProgress,
    required this.fraction,
    required this.onTap,
    required this.onDownload,
    required this.sourceId,
    required this.isTv,
  });

  static const coverKey = Key('chapterCover');

  final Episode ep;
  final int number;
  final String displayTitle;
  final String coverUrl;
  final Map<String, String>? coverHeaders;
  final bool isRead;
  final bool isInProgress;
  final double fraction;
  final VoidCallback onTap;
  final VoidCallback onDownload;
  final String sourceId;
  final bool isTv;

  @override
  Widget build(BuildContext context) {
    final title = displayTitle.trim().isNotEmpty
        ? displayTitle.trim()
        : 'Chapter $number';
    final meta = chapterMetaLine(ep);
    final art = (ep.thumbnail != null && ep.thumbnail!.isNotEmpty)
        ? ep.thumbnail!
        : coverUrl;

    return InkWell(
      onTap: onTap,
      splashColor: AppColors.accentSoft,
      highlightColor: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            SizedBox(
              key: coverKey,
              width: 44,
              height: 62,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Opacity(
                  opacity: isRead ? 0.45 : 1,
                  child: art.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: art,
                          cacheManager: AppImageCache.cacheManagerOrDefault,
                          httpHeaders: coverHeaders,
                          fit: BoxFit.cover,
                          memCacheWidth: 140,
                          placeholder: (c, u) =>
                              ColoredBox(color: AppColors.surface2),
                          errorWidget: (c, u, e) =>
                              ColoredBox(color: AppColors.surface2),
                        )
                      : ColoredBox(color: AppColors.surface2),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppText.body.copyWith(
                      color: isRead
                          ? AppColors.textTertiary
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (meta != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      meta,
                      style: AppText.caption.copyWith(
                        color: isRead
                            ? AppColors.textTertiary
                            : AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (isInProgress && fraction > 0) ...[
                    const SizedBox(height: 6),
                    FractionallySizedBox(
                      widthFactor: fraction.clamp(0.0, 1.0),
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!isTv) ...[
              const SizedBox(width: 8),
              _ChapterDownloadIcon(
                sourceId: sourceId,
                chapterUrl: ep.url,
                onDownload: onDownload,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.ep,
    required this.epNum,
    required this.displayTitle,
    required this.coverUrl,
    required this.coverHeaders,
    required this.isWatched,
    required this.isInProgress,
    required this.isResume,
    required this.fraction,
    required this.onTap,
    this.onLongPress,
    required this.onDownload,
    required this.sourceId,
    required this.showId,
    required this.isTv,
    this.filler = false,
  });

  final Episode ep;
  final int epNum;
  final String displayTitle;
  final bool filler;
  final String coverUrl;
  final Map<String, String>? coverHeaders;
  final bool isWatched;
  final bool isInProgress;
  final bool isResume;
  final double fraction;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback onDownload;
  final String sourceId;
  final String showId;
  final bool isTv;

  @override
  Widget build(BuildContext context) {
    final titleColor = isResume
        ? AppColors.accent
        : (isWatched ? AppColors.textSecondary : AppColors.textPrimary);

    final thumbUrl = (ep.thumbnail != null && ep.thumbnail!.isNotEmpty)
        ? ep.thumbnail!
        : coverUrl;

    final desc = (ep.description != null && ep.description!.trim().isNotEmpty)
        ? ep.description!.trim()
        : null;

    final metaLine = [
      if (ep.runtimeMinutes != null) '${ep.runtimeMinutes} min',
      if (ep.date != null && ep.date!.trim().isNotEmpty) ep.date!.trim(),
    ].join('  ·  ');

    final srcTitle = displayTitle.trim();
    final titleText =
        episodeDisplayTitle(ep, sourceTitle: srcTitle, number: epNum) ?? '';
    final heading =
        titleText.isNotEmpty ? '$epNum. $titleText' : 'Episode $epNum';

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      splashColor: AppColors.accentSoft,
      highlightColor: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 116,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          thumbUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: thumbUrl,
                                  cacheManager:
                                      AppImageCache.cacheManagerOrDefault,
                                  httpHeaders: coverHeaders,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 232,
                                  placeholder: (c, u) =>
                                      ColoredBox(color: AppColors.surface2),
                                  errorWidget: (c, u, e) =>
                                      ColoredBox(color: AppColors.surface2),
                                )
                              : ColoredBox(color: AppColors.surface2),
                          if (isWatched)
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                color: Color(0x73000000),
                              ),
                              child: SizedBox.expand(),
                            ),
                          const Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Color(0x59000000),
                                shape: BoxShape.circle,
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(7),
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                          if (isWatched)
                            const Positioned(
                              top: 4,
                              right: 4,
                              child: Icon(
                                Icons.check_circle,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          if (ep.rating != null)
                            Positioned(
                              top: 4,
                              left: 4,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0xB3000000),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.star_rounded,
                                        color: Color(0xFFFFC107),
                                        size: 11,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        ep.rating!.toStringAsFixed(1),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          height: 1.1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          if (isInProgress)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: _ThumbnailProgressBar(fraction: fraction),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        heading,
                        style: AppText.body.copyWith(
                          color: titleColor,
                          fontWeight: isResume
                              ? FontWeight.w800
                              : FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (metaLine.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          metaLine,
                          style: AppText.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (isResume || filler) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (isResume) const TagBadge(text: 'CONTINUE'),
                            if (isResume && filler) const SizedBox(width: 6),
                            if (filler) const TagBadge(text: 'FILLER'),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (!isTv) ...[
                  const SizedBox(width: 8),
                  _EpisodeDownloadIcon(
                    sourceId: sourceId,
                    showId: showId,
                    episodeId: ep.id,
                    onTap: onDownload,
                  ),
                ],
              ],
            ),
            if (desc != null) ...[
              const SizedBox(height: 8),
              Text(
                desc,
                style: AppText.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}


class _ChapterDownloadIcon extends StatelessWidget {
  const _ChapterDownloadIcon({
    required this.sourceId,
    required this.chapterUrl,
    required this.onDownload,
  });

  final String sourceId;
  final String chapterUrl;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final downloader = sl<ChapterDownloader>();
    final store = sl<ChapterDownloadStore>();
    final id = ChapterDownload.idFor(sourceId, chapterUrl);
    return ListenableBuilder(
      listenable: Listenable.merge([downloader, store.listenable()]),
      builder: (context, _) {
        final live = downloader.inFlight[id];
        if (live != null) {
          return _button(
            tooltip: 'Cancel download',
            onPressed: () => unawaited(downloader.cancel(id)),
            icon: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                value: live.progress > 0 ? live.progress : null,
                strokeWidth: 2.4,
                color: AppColors.accent,
                backgroundColor: AppColors.surface2,
              ),
            ),
          );
        }
        if (store.isDownloaded(sourceId, chapterUrl)) {
          return _button(
            tooltip: 'Downloaded',
            onPressed: () => _offerDelete(context, store, id),
            icon: Icon(
              Icons.check_circle_rounded,
              color: AppColors.accent,
              size: 24,
            ),
          );
        }
        return _button(
          tooltip: 'Download chapter',
          onPressed: onDownload,
          icon: const Icon(
            Icons.file_download_outlined,
            color: AppColors.textPrimary,
            size: 24,
          ),
        );
      },
    );
  }

  Widget _button({
    required String tooltip,
    required VoidCallback onPressed,
    required Widget icon,
  }) =>
      IconButton(
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        splashRadius: 22,
        tooltip: tooltip,
        icon: icon,
      );

  void _offerDelete(
    BuildContext context,
    ChapterDownloadStore store,
    String id,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: AppColors.accent,
              ),
              title: Text(
                'Delete download',
                style: AppText.body.copyWith(color: AppColors.accent),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(store.remove(id));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeDownloadIcon extends StatelessWidget {
  const _EpisodeDownloadIcon({
    required this.sourceId,
    required this.showId,
    required this.episodeId,
    required this.onTap,
  });

  final String sourceId;
  final String showId;
  final String episodeId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final manager = sl<DownloadManager>();
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final rec = manager.recordFor(sourceId, showId, episodeId);
        final s = rec?.status;
        final inProgress = rec != null &&
            (s == DownloadStatus.downloading ||
                s == DownloadStatus.paused ||
                s == DownloadStatus.queued ||
                s == DownloadStatus.resolving);
        return _glyph(
          s,
          rec?.progress ?? 0,
          onPressed: inProgress
              ? () => _showDownloadMenu(context, manager, rec)
              : onTap,
        );
      },
    );
  }

  Widget _glyph(
    DownloadStatus? status,
    double progress, {
    required VoidCallback onPressed,
  }) {
    final child = switch (status) {
      DownloadStatus.done => Icon(
        Icons.download_done_rounded,
        color: AppColors.accent,
        size: 24,
      ),
      DownloadStatus.downloading || DownloadStatus.paused => SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          value: progress > 0 ? progress : null,
          strokeWidth: 2.4,
          color: AppColors.accent,
          backgroundColor: AppColors.surface2,
        ),
      ),
      DownloadStatus.queued || DownloadStatus.resolving => const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.textSecondary,
        ),
      ),
      DownloadStatus.unsupported => const Icon(
        Icons.cloud_off_outlined,
        color: AppColors.textTertiary,
        size: 22,
      ),
      DownloadStatus.failed => Icon(
        Icons.refresh_rounded,
        color: AppColors.accent,
        size: 24,
      ),
      _ => const Icon(
        Icons.file_download_outlined,
        color: AppColors.textPrimary,
        size: 24,
      ),
    };
    final label = switch (status) {
      DownloadStatus.done => 'Downloaded',
      DownloadStatus.downloading || DownloadStatus.paused => 'Downloading',
      DownloadStatus.queued || DownloadStatus.resolving => 'Downloading',
      DownloadStatus.unsupported => 'Download unsupported',
      DownloadStatus.failed => 'Retry download',
      _ => 'Download episode',
    };
    return IconButton(
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      splashRadius: 22,
      tooltip: label,
      icon: child,
    );
  }

  void _showDownloadMenu(
    BuildContext context,
    DownloadManager manager,
    DownloadRecord rec,
  ) {
    final paused = rec.status == DownloadStatus.paused;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                color: AppColors.textPrimary,
              ),
              title: Text(
                paused ? 'Resume download' : 'Pause download',
                style: AppText.body.copyWith(color: AppColors.textPrimary),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                if (paused) {
                  manager.resume(rec);
                } else {
                  manager.pause(rec);
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.close_rounded, color: AppColors.accent),
              title: Text(
                'Cancel download',
                style: AppText.body.copyWith(color: AppColors.accent),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                manager.cancel(rec);
              },
            ),
          ],
        ),
      ),
    );
  }
}