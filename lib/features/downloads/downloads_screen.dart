import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/ui/settings_widgets.dart';

import '../../core/app_mode.dart';
import '../../core/di/injector.dart';
import '../../core/download/download_manager.dart';
import '../../core/download/download_prefs.dart';
import '../../core/download/download_record.dart';
import '../../core/mode/content_mode.dart';
import '../../core/models/episode.dart';
import '../../core/models/video_source.dart';
import '../../core/playback/resume_store.dart';
import '../../core/torrent/torrent_download_service.dart';
import '../../core/playback/watch_history.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/states.dart';
import '../settings/download_location_screen.dart';
import '../player/player_screen.dart';
import '../player/tv_playback_launch.dart';
import '../../core/ui/native_cover_provider.dart';
import 'chapter_downloads_screen.dart';
import 'downloads_screen_tv.dart';

/// Offline library — downloads grouped by show, with per-episode progress and
/// actions (play / pause / resume / cancel / delete). Shows collapse by default
/// into a scannable list; a search box filters by show or episode title, and a
/// summary strip shows the total downloaded count + storage used.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key, this.showBack = true});

  /// False when shown as a dock tab — see [settingsAppBar].
  final bool showBack;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen>
    with WidgetsBindingObserver {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  /// Show ids the user has expanded. Empty = all collapsed (the default).
  final Set<String> _expanded = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _prune();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from a file manager (where a file may have been deleted) →
    // reconcile the list with disk. This is the case initState alone missed.
    if (state == AppLifecycleState.resumed) _prune();
  }

  /// Drop downloads whose file was deleted outside the app. Non-blocking.
  void _prune() => unawaited(sl<DownloadManager>().pruneMissing());

  void _toggle(String showId) => setState(() {
    if (!_expanded.remove(showId)) _expanded.add(showId);
  });


  /// Bottom sheet with the CloudStream-style download concurrency sliders.
  /// Applies to the NEXT downloads started (running HLS jobs aren't retimed).
  void _openDownloadSettings() {
    final prefs = sl<DownloadPrefs>();
    // Hold the live drag value in local state so the sliders move smoothly —
    // each tick isn't an async Hive write/read round-trip. Persist + apply on
    // release (onCommit).
    int parallel = prefs.parallelDownloads;
    int connections = prefs.connectionsPerDownload;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Widget slider({
            required String title,
            required String subtitle,
            required int value,
            required int min,
            required int max,
            required ValueChanged<int> onChanged,
            ValueChanged<int>? onCommit,
          }) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Row(
                    children: [
                      Expanded(child: Text(title, style: AppText.headline)),
                      Text('$value', style: AppText.headline.copyWith(
                        color: AppColors.accent,
                      )),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Text(subtitle, style: AppText.caption),
                ),
                Slider(
                  value: value.toDouble(),
                  min: min.toDouble(),
                  max: max.toDouble(),
                  divisions: max - min,
                  activeColor: AppColors.accent,
                  label: '$value',
                  onChanged: (v) => setSheet(() => onChanged(v.round())),
                  onChangeEnd: onCommit == null
                      ? null
                      : (v) => onCommit(v.round()),
                ),
              ],
            );
          }

          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textTertiary.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Download settings', style: AppText.title),
                  ),
                ),
                slider(
                  title: 'Parallel downloads',
                  subtitle: 'How many episodes download at the same time. '
                      'Chapters always download one at a time.',
                  value: parallel,
                  min: DownloadPrefs.parallelMin,
                  max: DownloadPrefs.parallelMax,
                  onChanged: (n) => parallel = n,
                  // On release: persist + apply live to both paths (MP4 queue +
                  // HLS service). Raising it starts queued episodes immediately;
                  // lowering it just stops new ones spawning.
                  onCommit: (n) {
                    prefs.setParallelDownloads(n);
                    sl<DownloadManager>().setParallel(n);
                  },
                ),
                const SizedBox(height: 8),
                slider(
                  title: 'Connections per download',
                  subtitle: 'Segment connections an episode uses, and pages '
                      'fetched at once in a chapter. Higher = faster, more '
                      'data at once.',
                  value: connections,
                  min: DownloadPrefs.connectionsMin,
                  max: DownloadPrefs.connectionsMax,
                  onChanged: (n) => connections = n,
                  onCommit: (n) => prefs.setConnectionsPerDownload(n),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('Download directory'),
                  subtitle: Text(prefs.locationLabel ?? 'Default Downloads folder'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    await Navigator.of(ctx).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const DownloadLocationScreen(),
                      ),
                    );
                    setSheet(() {});
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openPresentationPicker() async {
    final prefs = sl<DownloadPrefs>();
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (ctx) {
        final current = prefs.presentation;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Downloads view', style: AppText.headline),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.view_list_rounded),
                  title: const Text('List'),
                  subtitle: const Text('Group episodes by show.'),
                  trailing: current == 'list'
                      ? Icon(Icons.check_rounded, color: AppColors.accent)
                      : null,
                  onTap: () => Navigator.pop(ctx, 'list'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.grid_view_rounded),
                  title: const Text('Cards'),
                  subtitle: const Text('Show downloaded episodes as cards.'),
                  trailing: current == 'cards'
                      ? Icon(Icons.check_rounded, color: AppColors.accent)
                      : null,
                  onTap: () => Navigator.pop(ctx, 'cards'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) {
      await prefs.setPresentation(picked);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (sl<AppMode>().isTv) return const DownloadsScreenTv();
    final manager = sl<DownloadManager>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: settingsAppBar(
        showBack: widget.showBack,
        'Downloads',
        actions: [
          IconButton(
            tooltip: sl<DownloadPrefs>().presentation == 'cards'
                ? 'Use list view'
                : 'Use card view',
            icon: Icon(
              sl<DownloadPrefs>().presentation == 'cards'
                  ? Icons.view_list_rounded
                  : Icons.grid_view_rounded,
            ),
            onPressed: _openPresentationPicker,
          ),
          IconButton(
            tooltip: 'Download settings',
            icon: const Icon(Icons.tune_rounded),
            onPressed: _openDownloadSettings,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: manager,
        builder: (context, _) {
          final groups = manager.byShow;
          return Column(
            children: [
              Expanded(
                child: PageView(
                  children: [
                    if (groups.isEmpty)
                      const EmptyState(
                        icon: Icons.download_outlined,
                        message: 'Episodes you download appear here',
                      )
                    else
                      Column(
                        children: [
                          _searchField(),
                          Expanded(child: _list(groups, manager)),
                        ],
                      ),
                    ChapterDownloadsScreen(
                      mode: ContentMode.manga,
                      embedded: true,
                    ),
                    ChapterDownloadsScreen(
                      mode: ContentMode.novel,
                      embedded: true,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        style: AppText.body.copyWith(color: AppColors.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search downloads',
          hintStyle: AppText.body.copyWith(color: AppColors.textTertiary),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppColors.textTertiary,
          ),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.textTertiary,
                  ),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                ),
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _list(
    Map<String, List<DownloadRecord>> groups,
    DownloadManager manager,
  ) {
    final q = _query.trim().toLowerCase();
    final all = manager.all;
    final done = all.where((r) => r.status == DownloadStatus.done).toList();
    final totalBytes = done.fold<int>(0, (s, r) => s + r.bytesTotal);

    final showIds = groups.keys.toList();
    final rows = <Widget>[];
    final cardRecords = <DownloadRecord>[];
    for (final id in showIds) {
      final recs = [...groups[id]!]
        ..sort((a, b) => (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0));
      final head = recs.first;

      List<DownloadRecord> episodes = recs;
      var forceExpand = false;
      if (q.isNotEmpty) {
        final showMatch = head.showTitle.toLowerCase().contains(q);
        if (!showMatch) {
          episodes = recs
              .where((r) => _episodeSearchText(r).contains(q))
              .toList();
          if (episodes.isEmpty) continue;
        }
        forceExpand = true;
      }

      if (sl<DownloadPrefs>().presentation == 'cards') {
        // Card mode is show-oriented, matching Home/Search poster cards. Keep
        // the whole group together so tapping a show reveals all of its
        // downloaded episodes instead of opening one arbitrary episode.
        cardRecords.add(head);
      } else {
        rows.add(
          _ShowGroup(
            records: recs,
            episodes: episodes,
            manager: manager,
            expanded: forceExpand || _expanded.contains(id),
            onToggle: () => _toggle(id),
          ),
        );
      }
    }

    if (sl<DownloadPrefs>().presentation == 'cards') {
      if (cardRecords.isEmpty) {
        return const EmptyState(
          icon: Icons.search_off_rounded,
          message: 'No downloads match your search',
        );
      }
      return ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
              _summaryStrip(
                count: done.length,
                bytes: totalBytes,
                anyExpanded: false,
                onToggleAll: () {},
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const columns = 3;
                    const gap = 12.0;
                    final cardWidth =
                        (constraints.maxWidth - gap * (columns - 1)) / columns;
                    final cardHeight = cardWidth / 0.68;
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: cardRecords.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.68,
                      ),
                      itemBuilder: (context, i) {
                        final showId = cardRecords[i].showId;
                        final records = [...groups[showId]!]
                          ..sort((a, b) => (a.episodeNumber ?? 0)
                              .compareTo(b.episodeNumber ?? 0));
                        return Center(
                          child: SizedBox(
                            width: cardWidth,
                            height: cardHeight,
                            child: _DownloadShowCard(records: records, manager: manager),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
        ],
      );
    }
    if (rows.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off_rounded,
        message: 'No downloads match your search',
      );
    }

    final anyExpanded = showIds.any(_expanded.contains);
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _summaryStrip(
          count: done.length,
          bytes: totalBytes,
          anyExpanded: anyExpanded,
          onToggleAll: () => setState(() {
            if (anyExpanded) {
              _expanded.clear();
            } else {
              _expanded.addAll(showIds);
            }
          }),
        ),
        ...rows,
      ],
    );
  }

  Widget _summaryStrip({
    required int count,
    required int bytes,
    required bool anyExpanded,
    required VoidCallback onToggleAll,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 2),
      child: Row(
        children: [
          const Icon(
            Icons.folder_outlined,
            size: 15,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: 6),
          Text(
            '$count downloaded · ${fmtDownloadSize(bytes)}',
            style: AppText.caption,
          ),
          const Spacer(),
          TextButton(
            onPressed: onToggleAll,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              anyExpanded ? 'Collapse all' : 'Expand all',
              style: AppText.caption.copyWith(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lowercased text a download is matched against when searching.
String _episodeSearchText(DownloadRecord r) {
  final n = r.episodeNumber?.toInt();
  return 'e${n ?? ''} ${r.episodeTitle}'.toLowerCase();
}

class _DownloadShowCard extends StatelessWidget {
  const _DownloadShowCard({required this.records, required this.manager});

  final List<DownloadRecord> records;
  final DownloadManager manager;

  Future<void> _openEpisodes(BuildContext context) async {
    final title = records.first.showTitle;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bg,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.82,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: AppText.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete all episodes',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: sheetContext,
                          builder: (dctx) => AlertDialog(
                            backgroundColor: AppColors.surface,
                            title: Text(
                              'Delete all downloads?',
                              style: AppText.headline,
                            ),
                            content: Text(
                              'Remove all ${records.length} '
                              '${records.length == 1 ? 'episode' : 'episodes'} '
                              'of “$title” from this device?',
                              style: AppText.body,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dctx, false),
                                child: Text(
                                  'Cancel',
                                  style: AppText.button.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(dctx, true),
                                child: Text(
                                  'Delete all',
                                  style: AppText.button.copyWith(
                                    color: AppColors.accent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await manager.deleteAll(records);
                          if (sheetContext.mounted) {
                            Navigator.of(sheetContext).pop();
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text(
                  '${records.where((r) => r.status == DownloadStatus.done).length} '
                  'of ${records.length} downloaded',
                  style: AppText.caption,
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: records.length,
                  itemBuilder: (_, i) => DownloadTile(
                    record: records[i],
                    manager: manager,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return const SizedBox.shrink();
    final head = records.first;
    final done = records.where((r) => r.status == DownloadStatus.done).length;
    final active = records.where((r) => r.isActive).toList();
    final hasActive = active.isNotEmpty;
    final aggregate = records.isEmpty
        ? 0.0
        : ((done + (hasActive ? active.first.progress : 0.0)) /
                records.length)
            .clamp(0.0, 1.0);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 520 ? 3 : 2;
    final gap = 12.0;
    final cellWidth = (width - 32 - gap * (columns - 1)) / columns;
    final memW = (cellWidth * dpr).round();

    return GestureDetector(
      onTap: () => _openEpisodes(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (head.cover != null && head.cover!.isNotEmpty)
                    Image(
                      image: ResizeImage(
                        nativeCoverProvider(
                          head.cover!,
                          head.coverHeaders,
                          showUrl: head.showUrl,
                          sourceId: head.sourceId,
                        ),
                        width: memW,
                      ),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          ColoredBox(color: AppColors.surface2),
                      loadingBuilder: (_, child, progress) =>
                          progress == null ? child : ColoredBox(color: AppColors.surface2),
                    )
                  else
                    ColoredBox(color: AppColors.surface2),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Color(0x700B0B0F),
                          Color(0x000B0B0F),
                        ],
                        stops: [0.0, 0.35],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: hasActive
                          ? CircularProgressIndicator(
                              value: aggregate > 0 ? aggregate : null,
                              strokeWidth: 2.8,
                              color: AppColors.accent,
                              backgroundColor: AppColors.surface2,
                            )
                          : done == records.length
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.accent,
                                  size: 32,
                                )
                              : CircularProgressIndicator(
                                  value: aggregate,
                                  strokeWidth: 2.8,
                                  color: AppColors.accent,
                                  backgroundColor: AppColors.surface2,
                                ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            head.showTitle,
            style: AppText.body.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ShowGroup extends StatelessWidget {
  const _ShowGroup({
    required this.records,
    required this.episodes,
    required this.manager,
    required this.expanded,
    required this.onToggle,
  });

  /// The full group — drives the "done of total" count and the group size.
  final List<DownloadRecord> records;

  /// The episodes to render when expanded (a filtered subset while searching).
  final List<DownloadRecord> episodes;

  final DownloadManager manager;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final head = records.first;
    final doneRecs =
        records.where((r) => r.status == DownloadStatus.done).toList();
    final groupBytes = doneRecs.fold<int>(0, (s, r) => s + r.bytesTotal);
    final sizeSuffix = groupBytes > 0 ? ' · ${fmtDownloadSize(groupBytes)}' : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 44,
                    height: 62,
                    child: (head.cover != null && head.cover!.isNotEmpty)
                        ? Image(
                            image: nativeCoverProvider(
                              head.cover!,
                              head.coverHeaders,
                              showUrl: head.showUrl,
                              sourceId: head.sourceId,
                            ),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                ColoredBox(color: AppColors.surface2),
                            loadingBuilder: (_, child, progress) =>
                                progress == null ? child : ColoredBox(color: AppColors.surface2),
                          )
                        : ColoredBox(color: AppColors.surface2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        head.showTitle,
                        style: AppText.headline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${doneRecs.length} of ${records.length}$sizeSuffix',
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.textTertiary,
                    size: 22,
                  ),
                  tooltip: 'Delete all episodes',
                  onPressed: () => _confirmDeleteAll(context),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          for (final r in episodes) DownloadTile(record: r, manager: manager),
        const SizedBox(height: 6),
      ],
    );
  }

  /// Confirm, then wipe every episode of this show in one go.
  Future<void> _confirmDeleteAll(BuildContext context) async {
    final n = records.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete all downloads?', style: AppText.headline),
        content: Text(
          'Remove all $n ${n == 1 ? 'episode' : 'episodes'} of '
          '“${records.first.showTitle}” from this device?',
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
              'Delete all',
              style: AppText.button.copyWith(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
    if (ok == true) await manager.deleteAll(records);
  }
}

/// Launches playback of a completed [DownloadRecord].
/// Called by both [DownloadTile] (phone touch path) and [DownloadsScreenTv]
/// (TV D-pad OK path) so the play logic lives in one place.
///
/// Phone plays through [PlayerScreen] (media_kit); TV routes to the same two
/// ExoPlayer paths streaming already uses, so nothing on TV touches media_kit.
Future<void> launchDownloadedEpisode(
  BuildContext context,
  DownloadRecord record,
) async {
  final path = record.filePath;
  if (path == null) return;
  final ep = Episode(
    id: record.episodeId,
    title: record.episodeTitle,
    number: record.episodeNumber,
    url: record.episodeUrl,
  );
  // The file is already on disk, so "resolving" is just handing back a source
  // pointing at it — same shape both players expect from a network resolve.
  Future<List<VideoSource>> resolveSources(String _) async => [
    VideoSource(
      url: path,
      container: SourceContainer.mp4,
      // Soft subs saved next to the video (e.g. HiAnime) → load from disk.
      subtitles: [
        for (final s in record.subtitles)
          Subtitle(
            url: s.path,
            lang: s.lang,
            label: s.label,
            isDefault: s.isDefault,
          ),
      ],
    ),
  ];
  final scrobbleTitle = record.malId != null ? record.showTitle : null;

  if (sl<AppMode>().isTv) {
    await launchTvPlayback(
      context: context,
      sourceId: record.sourceId,
      episodes: [ep],
      startIndex: 0,
      resume: sl<ResumeStore>(),
      resolveSources: resolveSources,
      showUrl: record.showUrl,
      showTitle: record.showTitle,
      cover: record.cover,
      coverHeaders: record.coverHeaders,
      category: record.category,
      malId: record.malId,
      scrobbleTitle: scrobbleTitle,
    );
    return;
  }

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PlayerScreen(
        sourceId: record.sourceId,
        episodes: [ep],
        startIndex: 0,
        resume: sl<ResumeStore>(),
        resolveSources: resolveSources,
        history: sl<WatchHistory>(),
        showTitle: record.showTitle,
        cover: record.cover,
        coverHeaders: record.coverHeaders,
        showUrl: record.showUrl,
        category: record.category,
        malId: record.malId,
        scrobbleTitle: scrobbleTitle,
      ),
    ),
  );
}

String _downloadSubtitleFor(DownloadRecord record, DownloadManager manager) {
  if (record.isTorrent &&
      manager.torrentProgress[record.id]?.status == 'copying') {
    return 'Saving to your folder…';
  }
  return switch (record.status) {
    DownloadStatus.done =>
      record.bytesTotal > 0 ? fmtDownloadSize(record.bytesTotal) : 'Downloaded',
    DownloadStatus.downloading =>
      '${(record.progress * 100).round()}%'
          '${record.bytesTotal > 0 ? ' of ${fmtDownloadSize(record.bytesTotal)}' : ''}'
          '${_torrentSuffixFor(record, manager)}',
    DownloadStatus.paused => 'Paused · ${(record.progress * 100).round()}%',
    DownloadStatus.queued => 'Queued',
    DownloadStatus.resolving => 'Preparing…',
    DownloadStatus.unsupported => record.error ?? 'Not available offline yet',
    DownloadStatus.failed => record.error ?? 'Failed',
    DownloadStatus.canceled => 'Canceled',
  };
}

String _torrentSuffixFor(DownloadRecord record, DownloadManager manager) {
  if (!record.isTorrent) return '';
  final TorrentDownloadProgress? p = manager.torrentProgress[record.id];
  if (p == null) return '';
  final parts = <String>[];
  if (p.peers > 0) parts.add('${p.peers} peers');
  if (p.downSpeedBps > 0) {
    final mb = p.downSpeedBps / (1024 * 1024);
    parts.add(mb >= 1
        ? '${mb.toStringAsFixed(1)} MB/s'
        : '${(p.downSpeedBps / 1024).round()} KB/s');
  }
  return parts.isEmpty ? '' : ' · ${parts.join(' · ')}';
}

class DownloadTile extends StatelessWidget {
  const DownloadTile({super.key, required this.record, required this.manager});
  final DownloadRecord record;
  final DownloadManager manager;

  String get _epLabel {
    final n = record.episodeNumber?.toInt();
    final base = n != null ? 'E$n' : 'Episode';
    final t = record.episodeTitle.trim();
    return (t.isEmpty || t == base) ? base : '$base · $t';
  }

  String get _subtitle => _downloadSubtitleFor(record, manager);

  Future<void> _play(BuildContext context) =>
      launchDownloadedEpisode(context, record);

  @override
  Widget build(BuildContext context) {
    final isDone = record.status == DownloadStatus.done;
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      onTap: isDone ? () => _play(context) : null,
      leading: _StatusGlyph(record: record),
      title: Text(
        _epLabel,
        style: AppText.body.copyWith(color: AppColors.textPrimary),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_subtitle, style: AppText.caption),
          if (record.status == DownloadStatus.downloading ||
              record.status == DownloadStatus.paused) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: record.progress > 0 ? record.progress : null,
                minHeight: 3,
                color: AppColors.accent,
                backgroundColor: AppColors.surface2,
              ),
            ),
          ],
        ],
      ),
      trailing: _TileMenu(record: record, manager: manager),
    );
  }
}

class _StatusGlyph extends StatelessWidget {
  const _StatusGlyph({required this.record});
  final DownloadRecord record;

  @override
  Widget build(BuildContext context) {
    return switch (record.status) {
      DownloadStatus.done => Icon(
        Icons.play_circle_fill_rounded,
        color: AppColors.accent,
        size: 32,
      ),
      DownloadStatus.downloading => SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(
          value: record.progress > 0 ? record.progress : null,
          strokeWidth: 2.4,
          color: AppColors.accent,
          backgroundColor: AppColors.surface2,
        ),
      ),
      DownloadStatus.paused => const Icon(
        Icons.pause_circle_outline_rounded,
        color: AppColors.textSecondary,
        size: 30,
      ),
      DownloadStatus.unsupported => const Icon(
        Icons.cloud_off_outlined,
        color: AppColors.textTertiary,
        size: 26,
      ),
      DownloadStatus.failed => Icon(
        Icons.error_outline_rounded,
        color: AppColors.accent,
        size: 28,
      ),
      DownloadStatus.canceled => const Icon(
        Icons.cancel_outlined,
        color: AppColors.textTertiary,
        size: 26,
      ),
      // queued / resolving — genuinely loading.
      _ => const SizedBox(
        width: 26,
        height: 26,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    };
  }
}

class _TileMenu extends StatelessWidget {
  const _TileMenu({required this.record, required this.manager});
  final DownloadRecord record;
  final DownloadManager manager;

  @override
  Widget build(BuildContext context) {
    final r = record;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
      color: AppColors.surface2,
      onSelected: (v) {
        switch (v) {
          case 'pause':
            unawaited(manager.pause(r));
          case 'resume':
            unawaited(manager.resume(r));
          case 'retry':
            unawaited(manager.retry(r));
          // Cancel an in-flight download = stop it AND remove it from the list
          // (delete cancels the task, drops the record, and clears fallbacks).
          case 'cancel':
          case 'delete':
            unawaited(manager.delete(r));
        }
      },
      itemBuilder: (context) => [
        if (r.status == DownloadStatus.downloading)
          _item('pause', Icons.pause_rounded, 'Pause'),
        if (r.status == DownloadStatus.paused)
          _item('resume', Icons.play_arrow_rounded, 'Resume'),
        if (r.status == DownloadStatus.failed && !r.isTorrent)
          _item('retry', Icons.refresh_rounded, 'Retry'),
        if (r.isActive) _item('cancel', Icons.close_rounded, 'Cancel'),
        _item('delete', Icons.delete_outline_rounded, 'Delete'),
      ],
    );
  }

  PopupMenuItem<String> _item(String value, IconData icon, String label) =>
      PopupMenuItem<String>(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.textPrimary),
            const SizedBox(width: 12),
            Text(label, style: AppText.body.copyWith(color: AppColors.textPrimary)),
          ],
        ),
      );
}
