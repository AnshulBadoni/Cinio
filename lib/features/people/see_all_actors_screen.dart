import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/models/person.dart';
import '../../core/playback/playback_prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/settings_widgets.dart';
import 'person_page.dart';

/// Screen displaying all actors / performers in a paginated grid.
class SeeAllActorsScreen extends StatefulWidget {
  const SeeAllActorsScreen({
    super.key,
    required this.title,
    required this.initialActors,
    this.onLoadMore,
  });

  final String title;
  final List<PersonRef> initialActors;
  final Future<List<PersonRef>> Function(int page)? onLoadMore;

  @override
  State<SeeAllActorsScreen> createState() => _SeeAllActorsScreenState();
}

class _SeeAllActorsScreenState extends State<SeeAllActorsScreen> {
  late final List<PersonRef> _actors = [...widget.initialActors];
  final Set<String> _seen = {};
  final ScrollController _scrollController = ScrollController();

  int _page = 1;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    for (final a in _actors) {
      _seen.add(_actorKey(a));
    }
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _actorKey(PersonRef p) {
    if (p.id != 0) return 'id:${p.id}';
    if (p.externalId != null && p.externalId!.isNotEmpty) return 'ext:${p.externalId}';
    return 'name:${p.name}';
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoadingMore || !_hasMore) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll - currentScroll <= 400) {
      _fetchMore();
    }
  }

  Future<void> _fetchMore() async {
    if (widget.onLoadMore == null || _isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    final nextPage = _page + 1;
    try {
      final more = await widget.onLoadMore!(nextPage);
      if (!mounted) return;
      if (more.isEmpty) {
        setState(() {
          _hasMore = false;
          _isLoadingMore = false;
        });
        return;
      }
      var added = 0;
      for (final a in more) {
        if (_seen.add(_actorKey(a))) {
          _actors.add(a);
          added++;
        }
      }
      setState(() {
        _page = nextPage;
        _isLoadingMore = false;
        if (added == 0) _hasMore = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final square = sl.isRegistered<PlaybackPrefs>() &&
        sl<PlaybackPrefs>().peopleCardStyle == 'square';
    final width = MediaQuery.sizeOf(context).width;
    final cols = width >= 900 ? 6 : (width >= 600 ? 5 : (square ? 3 : 4));
    final aspectRatio = square ? 0.72 : 0.68;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: settingsAppBar(widget.title),
      body: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                childAspectRatio: aspectRatio,
                crossAxisSpacing: 14,
                mainAxisSpacing: 18,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final actor = _actors[index];
                  return _GridActorCard(
                    actor: actor,
                    square: square,
                    onTap: () => Navigator.of(context).push(
                      PersonPage.route(actor),
                    ),
                  );
                },
                childCount: _actors.length,
              ),
            ),
          ),
          if (_isLoadingMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: MediaQuery.paddingOf(context).bottom + 24,
            ),
          ),
        ],
      ),
    );
  }
}

class _GridActorCard extends StatefulWidget {
  const _GridActorCard({
    required this.actor,
    required this.square,
    required this.onTap,
  });

  final PersonRef actor;
  final bool square;
  final VoidCallback onTap;

  @override
  State<_GridActorCard> createState() => _GridActorCardState();
}

class _GridActorCardState extends State<_GridActorCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final photo = widget.actor.photo;

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: Column(
          children: [
            Expanded(
              child: widget.square
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        color: AppColors.surface2,
                        width: double.infinity,
                        height: double.infinity,
                        child: photo != null && photo.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: photo,
                                fit: BoxFit.cover,
                                memCacheWidth: 400,
                                errorWidget: (_, _, _) => const Icon(
                                  Icons.person_rounded,
                                  color: AppColors.textTertiary,
                                  size: 36,
                                ),
                              )
                            : const Icon(
                                Icons.person_rounded,
                                color: AppColors.textTertiary,
                                size: 36,
                              ),
                      ),
                    )
                  : AspectRatio(
                      aspectRatio: 1,
                      child: ClipOval(
                        child: Container(
                          color: AppColors.surface2,
                          child: photo != null && photo.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: photo,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 400,
                                  errorWidget: (_, _, _) => const Icon(
                                    Icons.person_rounded,
                                    color: AppColors.textTertiary,
                                    size: 36,
                                  ),
                                )
                              : const Icon(
                                  Icons.person_rounded,
                                  color: AppColors.textTertiary,
                                  size: 36,
                                ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.actor.name,
              maxLines: widget.square ? 1 : 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
