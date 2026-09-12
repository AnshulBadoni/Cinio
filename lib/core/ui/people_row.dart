import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../cache/app_image_cache.dart';
import '../di/injector.dart';
import '../models/media_item.dart';
import '../playback/playback_prefs.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'content_row.dart';
import 'reveal_item.dart';

class PeopleRow extends StatelessWidget {
  const PeopleRow({
    super.key,
    required this.title,
    required this.items,
    required this.onTap,
    required this.onLongPress,
    this.onSeeAll,
  });

  final String title;
  final List<MediaItem> items;
  final void Function(MediaItem) onTap;
  final void Function(MediaItem) onLongPress;
  final VoidCallback? onSeeAll;

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
      itemBuilder: (context, index) {
        final item = items[index];
        return _PersonCard(
          item: item,
          square: square,
          onTap: () => onTap(item),
          onLongPress: () => onLongPress(item),
        );
      },
    );
  }
}

class _PersonCard extends StatefulWidget {
  const _PersonCard({
    required this.item,
    required this.square,
    required this.onTap,
    required this.onLongPress,
  });

  final MediaItem item;
  final bool square;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_PersonCard> createState() => _PersonCardState();
}

class _PersonCardState extends State<_PersonCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.square ? 12 : 999),
                  child: widget.item.cover == null
                      ? ColoredBox(color: AppColors.surface2)
                      : CachedNetworkImage(
                          imageUrl: widget.item.cover!,
                          cacheManager: AppImageCache.manager,
                          httpHeaders: widget.item.coverHeaders,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => ColoredBox(color: AppColors.surface2),
                          errorWidget: (_, __, ___) => ColoredBox(color: AppColors.surface2),
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
            ],
          ),
        ),
      ),
    );
  }
}
