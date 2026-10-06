import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/models/media_item.dart';
import '../../core/models/watch_status.dart';
import '../../core/playback/list_status_store.dart';
import '../../core/playback/my_list.dart';
import '../../core/repository/source_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/native_cover_provider.dart';
import '../../core/ui/poster_quick_actions.dart';
import '../detail/detail_screen.dart';

/// Screen displaying video results from providers for a person,
/// featuring dynamic provider filter chips and a sheet to add or hide providers.
class ProviderVideosScreen extends StatefulWidget {
  const ProviderVideosScreen({
    super.key,
    required this.title,
    required this.personName,
    required this.initialItems,
    required this.isTpdb,
  });

  final String title;
  final String personName;
  final List<MediaItem> initialItems;
  final bool isTpdb;

  static Route<void> route({
    required String title,
    required String personName,
    required List<MediaItem> initialItems,
    required bool isTpdb,
  }) {
    return MaterialPageRoute<void>(
      builder: (_) => ProviderVideosScreen(
        title: title,
        personName: personName,
        initialItems: initialItems,
        isTpdb: isTpdb,
      ),
    );
  }

  @override
  State<ProviderVideosScreen> createState() => _ProviderVideosScreenState();
}

class _ProviderVideosScreenState extends State<ProviderVideosScreen> {
  late final List<MediaItem> _allItems = [...widget.initialItems];
  final Set<String> _hiddenSources = {};
  final Set<String> _searchedSources = {};
  String? _selectedSourceId;
  bool _searchingMore = false;

  @override
  void initState() {
    super.initState();
    // Track which sources provided the initial items
    for (final it in widget.initialItems) {
      if (it.sourceId.isNotEmpty) {
        _searchedSources.add(it.sourceId);
      }
    }
  }

  List<({String id, String name})> get _candidateSources {
    final repo = sl<SourceRepository>();
    return widget.isTpdb ? repo.adultSources : repo.loadedSources;
  }

  String _sourceDisplayName(String sourceId) {
    final match = _candidateSources.where((s) => s.id == sourceId);
    if (match.isNotEmpty) return match.first.name;
    return sourceId;
  }

  List<MediaItem> get _visibleItems {
    return _allItems.where((item) {
      if (_hiddenSources.contains(item.sourceId)) return false;
      if (_selectedSourceId != null && item.sourceId != _selectedSourceId) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Map of sourceId -> count of items from that source
  Map<String, int> get _sourceCounts {
    final counts = <String, int>{};
    for (final item in _allItems) {
      if (!_hiddenSources.contains(item.sourceId)) {
        counts[item.sourceId] = (counts[item.sourceId] ?? 0) + 1;
      }
    }
    return counts;
  }

  Future<void> _searchAdditionalSource(String sourceId) async {
    if (_searchingMore) return;
    setState(() => _searchingMore = true);
    try {
      final results = await sl<SourceRepository>()
          .search(widget.personName, sourceId: sourceId);
      if (!mounted) return;
      setState(() {
        _searchedSources.add(sourceId);
        _hiddenSources.remove(sourceId);
        final existingKeys = {for (final it in _allItems) it.id.isNotEmpty ? it.id : it.url};
        for (final r in results) {
          final k = r.id.isNotEmpty ? r.id : r.url;
          if (existingKeys.add(k)) {
            _allItems.add(r);
          }
        }
        _searchingMore = false;
      });
      if (results.isEmpty) {
        _snack('No results from ${_sourceDisplayName(sourceId)}');
      } else {
        _snack('Added ${results.length} results from ${_sourceDisplayName(sourceId)}');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _searchingMore = false);
        _snack('Failed to search ${_sourceDisplayName(sourceId)}');
      }
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showManageProvidersSheet() async {
    final candidateList = _candidateSources;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Manage Providers',
                          style: AppText.headline.copyWith(fontSize: 18),
                        ),
                        if (_hiddenSources.isNotEmpty)
                          TextButton(
                            onPressed: () {
                              setSheetState(() => _hiddenSources.clear());
                              setState(() {});
                            },
                            child: Text('Show All', style: TextStyle(color: AppColors.accent)),
                          ),
                      ],
                    ),
                    Text(
                      'Toggle sources to show/hide, or search more providers for "${widget.personName}"',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.55,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: candidateList.length,
                        separatorBuilder: (_, _) => const Divider(color: Colors.white10, height: 1),
                        itemBuilder: (context, idx) {
                          final src = candidateList[idx];
                          final hasSearched = _searchedSources.contains(src.id);
                          final isHidden = _hiddenSources.contains(src.id);
                          final count = _allItems.where((i) => i.sourceId == src.id).length;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        src.name,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        hasSearched
                                            ? '$count items found'
                                            : 'Not searched yet',
                                        style: TextStyle(
                                          color: hasSearched
                                              ? (count > 0 ? Colors.greenAccent : Colors.white38)
                                              : Colors.white38,
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (hasSearched) ...[
                                  // Toggle visibility button
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      foregroundColor: isHidden ? Colors.white38 : AppColors.accent,
                                    ),
                                    onPressed: () {
                                      setSheetState(() {
                                        if (isHidden) {
                                          _hiddenSources.remove(src.id);
                                        } else {
                                          _hiddenSources.add(src.id);
                                        }
                                      });
                                      setState(() {});
                                    },
                                    icon: Icon(
                                      isHidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                      size: 18,
                                    ),
                                    label: Text(isHidden ? 'Hidden' : 'Visible'),
                                  ),
                                ] else ...[
                                  // Search provider button
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: const BorderSide(color: Colors.white24),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    ),
                                    onPressed: () async {
                                      Navigator.of(ctx).pop();
                                      await _searchAdditionalSource(src.id);
                                    },
                                    icon: const Icon(Icons.search, size: 16),
                                    label: const Text('Search'),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showMediaItemQuickActions(MediaItem item, String heroTag) async {
    final myList = sl<MyListStore>();
    final listStatus = sl<ListStatusStore>();
    final inLibrary = myList.contains(item) || listStatus.statusOf(item) != null;
    final watched = listStatus.statusOf(item) == WatchStatus.completed;

    await showPosterQuickActions(
      context,
      item: item,
      heroTag: heroTag,
      inLibrary: inLibrary,
      watched: watched,
      onPlay: () => Navigator.of(context).push(DetailScreen.route(item, heroTag: heroTag)),
      onInfo: () => Navigator.of(context).push(DetailScreen.route(item, heroTag: heroTag)),
      onMarkWatched: () async {
        if (!myList.contains(item)) await myList.add(item);
        await listStatus.setStatus(item, WatchStatus.completed);
        await myList.pushStatus(item);
        if (mounted) setState(() {});
      },
      onToggleLibrary: () async {
        await myList.toggle(item);
        if (!myList.contains(item)) {
          await listStatus.remove(item);
        }
        if (mounted) setState(() {});
        return myList.contains(item);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleItems;
    final sourceCounts = _sourceCounts;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: Text(widget.title, style: AppText.headline),
        actions: [
          IconButton(
            tooltip: 'Filter Providers',
            icon: const Icon(Icons.tune_rounded, color: Colors.white),
            onPressed: _showManageProvidersSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Horizontal Provider Filter Chips ──────────────────────────────
          if (sourceCounts.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                children: [
                  // "All" chip
                  _buildFilterChip(
                    label: 'All (${_allItems.where((i) => !_hiddenSources.contains(i.sourceId)).length})',
                    isSelected: _selectedSourceId == null,
                    onTap: () => setState(() => _selectedSourceId = null),
                  ),
                  const SizedBox(width: 8),

                  // Individual provider chips
                  for (final entry in sourceCounts.entries) ...[
                    _buildFilterChip(
                      label: '${_sourceDisplayName(entry.key)} (${entry.value})',
                      isSelected: _selectedSourceId == entry.key,
                      onTap: () => setState(() {
                        if (_selectedSourceId == entry.key) {
                          _selectedSourceId = null;
                        } else {
                          _selectedSourceId = entry.key;
                        }
                      }),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // Quick "+ More" action chip
                  ActionChip(
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                    label: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 14, color: Colors.white70),
                        SizedBox(width: 4),
                        Text(
                          'More',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    onPressed: _showManageProvidersSheet,
                  ),
                ],
              ),
            ),

          if (_searchingMore)
            LinearProgressIndicator(
              backgroundColor: Colors.transparent,
              color: AppColors.accent,
            ),

          // ── Grid of 16:9 Provider Videos ─────────────────────────────────
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.filter_list_off, size: 48, color: Colors.white38),
                          const SizedBox(height: 12),
                          Text(
                            _hiddenSources.isNotEmpty
                                ? 'No videos matching the active filters'
                                : 'No videos found from providers',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.accent,
                              side: BorderSide(color: AppColors.accent),
                            ),
                            icon: const Icon(Icons.tune_rounded, size: 16),
                            label: const Text('Manage Providers'),
                            onPressed: _showManageProvidersSheet,
                          ),
                        ],
                      ),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 1.18,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 14,
                    ),
                    itemCount: visible.length,
                    itemBuilder: (context, idx) {
                      final item = visible[idx];
                      final heroTag = 'seeall-provider-video:${item.id}:$idx';
                      final imgUrl = item.cover;

                      return GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          DetailScreen.route(item, heroTag: heroTag),
                        ),
                        onLongPress: () => _showMediaItemQuickActions(item, heroTag),
                        behavior: HitTestBehavior.opaque,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Hero(
                                  tag: heroTag,
                                  createRectTween: (begin, end) =>
                                      MaterialRectArcTween(begin: begin, end: end),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Container(color: AppColors.surface2),
                                      if (imgUrl != null && imgUrl.isNotEmpty)
                                        Image(
                                          image: nativeCoverProvider(imgUrl, null),
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) =>
                                              Container(color: AppColors.surface2),
                                        ),
                                      // Dark subtle bottom gradient
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.transparent,
                                              Colors.black.withValues(alpha: 0.70),
                                            ],
                                          ),
                                        ),
                                      ),
                                      // Center Play Icon watermark
                                      Center(
                                        child: Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.black.withValues(alpha: 0.60),
                                            border: Border.all(
                                              color: Colors.white.withValues(alpha: 0.3),
                                              width: 1.2,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.play_arrow_rounded,
                                            color: Colors.white,
                                            size: 22,
                                          ),
                                        ),
                                      ),
                                      // Provider Badge
                                      if (item.sourceId.isNotEmpty)
                                        Positioned(
                                          bottom: 6,
                                          left: 6,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(alpha: 0.75),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              _sourceDisplayName(item.sourceId),
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.accent : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
