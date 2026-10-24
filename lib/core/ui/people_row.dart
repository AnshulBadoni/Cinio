import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../cache/app_image_cache.dart';
import '../di/injector.dart';
import '../models/media_item.dart';
import '../playback/playback_prefs.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'content_row.dart';
import 'poster_card.dart';

class PeopleRow extends StatelessWidget {
  const PeopleRow({
    super.key,
    required this.title,
    required this.items,
    required this.onTap,
    required this.onLongPress,
    this.heroTagBuilder,
    this.onSeeAll,
    this.onLoadMore,
    this.isLoadingMore = false,
  });

  final String title;
  final List<MediaItem> items;
  final void Function(MediaItem) onTap;
  final void Function(MediaItem) onLongPress;
  final String Function(MediaItem, int)? heroTagBuilder;
  final VoidCallback? onSeeAll;
  final VoidCallback? onLoadMore;
  final bool isLoadingMore;

  @override
  Widget build(BuildContext context) {
    final square = sl<PlaybackPrefs>().peopleCardStyle == 'square';
    final width = square ? 136.0 : 124.0;
    final height = square ? 196.0 : 172.0;
    return ContentRow(
      title: title,
      itemWidth: width,
      itemHeight: height,
      itemCount: items.length,
      onSeeAll: onSeeAll,
      onLoadMore: onLoadMore,
      isLoadingMore: isLoadingMore,
      itemBuilder: (context, index) {
        final item = items[index];
        final heroTag = heroTagBuilder?.call(item, index) ??
            'people:${item.sourceId}:${item.id}:$index';
        return _PersonCard(
          item: item,
          square: square,
          heroTag: heroTag,
          onTap: onTap,
          onLongPress: onLongPress,
        );
      },
    );
  }
}

class _PersonCard extends StatefulWidget {
  const _PersonCard({
    required this.item,
    required this.square,
    required this.heroTag,
    required this.onTap,
    required this.onLongPress,
  });

  final MediaItem item;
  final bool square;
  final String heroTag;
  final void Function(MediaItem) onTap;
  final void Function(MediaItem) onLongPress;

  @override
  State<_PersonCard> createState() => _PersonCardState();
}

class _PersonCardState extends State<_PersonCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final effectiveCover = widget.item.cover;
    return RepaintBoundary(
      child: GestureDetector(
        onTap: () => widget.onTap(widget.item),
        onLongPress: () => widget.onLongPress(widget.item),
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: widget.square ? 136 : 124,
                height: widget.square ? 136 : 124,
                child: Hero(
                  tag: widget.heroTag,
                  createRectTween: (begin, end) =>
                      MaterialRectArcTween(begin: begin, end: end),
                  flightShuttleBuilder: posterHeroFlightShuttle,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(widget.square ? 12 : 999),
                    child: effectiveCover == null
                        ? ColoredBox(color: AppColors.surface2)
                        : CachedNetworkImage(
                            imageUrl: effectiveCover,
                            cacheManager: AppImageCache.manager,
                            httpHeaders: widget.item.coverHeaders,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => ColoredBox(color: AppColors.surface2),
                            errorWidget: (context, url, error) => ColoredBox(color: AppColors.surface2),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.item.title,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(color: AppColors.textPrimary),
              ),
              if (widget.item.rating != null && widget.item.rating! > 0) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.star_rounded, size: 12, color: Color(0xFFFFB800)),
                    const SizedBox(width: 3),
                    Text(
                      widget.item.rating!.toStringAsFixed(1),
                      style: AppText.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
