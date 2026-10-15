import 'package:flutter/material.dart';

import '../../core/app_mode.dart';
import '../../core/di/injector.dart';
import '../../core/models/media_item.dart';
import '../../core/models/watch_status.dart';
import '../../core/playback/list_status_store.dart';
import '../../core/playback/playback_prefs.dart';
import '../../core/playback/watch_history.dart';
import '../../core/reading/read_history.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/poster_card.dart';
import '../../core/ui/reveal_item.dart';
import 'see_all_screen_tv.dart';

/// Full-grid view of a single home row ("See All"). Reuses the home's tap /
/// long-press handlers so an item opens the same Detail / info card.
///
/// When [onLoadMore] is provided the grid paginates: scrolling near the bottom
/// fetches the next page and appends it (infinite scroll). When it's null the
/// grid is a fixed list over [items] — byte-for-byte the pre-pagination
/// behaviour, so search / JS / non-paginating callers are unchanged.
class SeeAllScreen extends StatefulWidget {
  const SeeAllScreen({
    super.key,
    required this.title,
    required this.items,
    required this.onTap,
    this.onLongPress,
    this.tagsFor,
    this.onLoadMore,
    this.initialPage = 1,
  });

  final String title;
  final List<MediaItem> items;
  final void Function(MediaItem) onTap;
  final void Function(MediaItem)? onLongPress;

  /// Optional per-item poster badges (e.g. SUB/DUB/MOVIE). When null no tags are
  /// drawn — keeps the home "See All" callers unchanged.
  final List<String> Function(MediaItem)? tagsFor;

  /// Optional next-page fetcher for infinite scroll. `page` is 1-based and the
  /// initial [items] ARE page 1, so the first call requests page 2. Returning an
  /// empty list (or only already-seen items) ends pagination. Null → fixed list.
  final Future<List<MediaItem>> Function(int page)? onLoadMore;

  final int initialPage;

  @override
  State<SeeAllScreen> createState() => _SeeAllScreenState();
}

class _SeeAllScreenState extends State<SeeAllScreen> {
  late final List<MediaItem> _items = [...widget.items];
  final Set<String> _seen = {};
  final ScrollController _controller = ScrollController();

  /// The last page already loaded — computed from initialPage or existing item count.
  late int _page = widget.initialPage > 1
      ? widget.initialPage
      : (_items.length / 16).ceil().clamp(1, 999);
  bool _loading = false;
  bool _end = false;

  @override
  void initState() {
    super.initState();
    for (final it in _items) {
      _seen.add(_keyOf(it));
    }
    if (widget.onLoadMore != null) {
      _controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Dedupe key — prefer the stable id, fall back to the url.
  String _keyOf(MediaItem m) => m.id.isNotEmpty ? m.id : m.url;

  bool _isItemCompleted(MediaItem item) {
    if (sl<ListStatusStore>().statusOf(item) == WatchStatus.completed) return true;
    final h = sl<WatchHistory>().get(item.sourceId, item.id) ??
        sl<WatchHistory>().get(item.sourceId, item.url);
    if (h != null && h.finished) return true;
    final r = sl<ReadHistory>().get(item.sourceId, item.id) ??
        sl<ReadHistory>().get(item.sourceId, item.url);
    if (r != null && r.finished) return true;
    return false;
  }

  void _onScroll() {
    if (_loading || _end || !_controller.hasClients) return;
    final pos = _controller.position;
    if (pos.pixels >= pos.maxScrollExtent - 400 || pos.pixels >= pos.maxScrollExtent * 0.8) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    final loader = widget.onLoadMore;
    if (loader == null || _loading || _end) return;
    setState(() => _loading = true);

    try {
      var curPage = _page;
      var foundFresh = false;

      // Check up to 3 pages in case an intermediate page returns duplicates of items
      // already present on initial screen load
      for (var attempt = 0; attempt < 3; attempt++) {
        curPage += 1;
        List<MediaItem> next = const [];
        try {
          next = await loader(curPage);
        } catch (_) {
          next = const [];
        }
        if (!mounted) return;

        if (next.isEmpty) {
          // Genuinely at the end of the remote catalog
          setState(() {
            _loading = false;
            _end = true;
          });
          return;
        }

        final fresh = <MediaItem>[];
        for (final it in next) {
          final k = _keyOf(it);
          if (_seen.add(k)) fresh.add(it);
        }

        if (fresh.isNotEmpty) {
          _page = curPage;
          foundFresh = true;
          setState(() {
            _loading = false;
            _items.addAll(fresh);
          });
          break;
        }

        // Entire page was duplicate, advance counter and check next page
        _page = curPage;
      }

      if (!foundFresh && mounted) {
        setState(() {
          _loading = false;
          _end = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (sl<AppMode>().isTv) {
      return SeeAllScreenTv(
        title: widget.title,
        items: widget.items,
        initialPage: widget.initialPage,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        tagsFor: widget.tagsFor,
        onLoadMore: widget.onLoadMore,
      );
    }
    final cellW = (MediaQuery.sizeOf(context).width - 32 - 20) / 3;
    final paginating = widget.onLoadMore != null;
    // A trailing spinner cell spanning the full row while a page is loading.
    final showSpinner = paginating && _loading;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(widget.title, style: AppText.headline),
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (paginating && notification.metrics.axis == Axis.vertical) {
            final pos = notification.metrics;
            if (pos.pixels >= pos.maxScrollExtent - 400 || pos.pixels >= pos.maxScrollExtent * 0.8) {
              if (!_loading && !_end) _loadMore();
            }
          }
          return false;
        },
        child: GridView.builder(
          controller: paginating ? _controller : null,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          cacheExtent: 800,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: sl<PlaybackPrefs>().hideTitles ? (2 / 3) : 0.56,
            crossAxisSpacing: 10,
            mainAxisSpacing: 14,
          ),
          itemCount: _items.length,
          itemBuilder: (context, i) {
            final item = _items[i];
            return RevealItem(
              index: i,
              child: PosterCard(
                title: item.title,
                imageUrl: item.cover,
                headers: item.coverHeaders,
                tags: widget.tagsFor?.call(item) ?? const [],
                qualityBadge: item.quality,
                dubBadge: item.dubBadge,
                cellWidth: cellW,
                completed: _isItemCompleted(item),
                onTap: () => widget.onTap(item),
                onLongPress: widget.onLongPress == null
                    ? null
                    : () => widget.onLongPress!(item),
              ),
            );
          },
        ),
      ),
      // Bottom loading indicator while the next page is in flight. Only rendered
      // in the paginating configuration, so non-paginating callers are unchanged.
      bottomNavigationBar: showSpinner
          ? const SizedBox(
              height: 48,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : null,
    );
  }
}
