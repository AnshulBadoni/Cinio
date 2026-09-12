import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../cache/app_image_cache.dart';
import '../models/media_item.dart';
import 'content_row.dart';
import 'poster_card.dart';
import '../di/injector.dart';
import '../playback/playback_prefs.dart';

/// Home browse row that can use poster or landscape cards. In adaptive mode it
/// samples the first few artworks and picks the dominant aspect ratio.
class AdaptiveContentRow extends StatefulWidget {
  const AdaptiveContentRow({
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
  State<AdaptiveContentRow> createState() => _AdaptiveContentRowState();
}

class _AdaptiveContentRowState extends State<AdaptiveContentRow> {
  bool _landscape = false;

  @override
  void initState() {
    super.initState();
    _resolveAdaptive();
  }

  @override
  void didUpdateWidget(covariant AdaptiveContentRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items || oldWidget.title != widget.title) {
      _landscape = false;
      _resolveAdaptive();
    }
  }

  Future<void> _resolveAdaptive() async {
    final samples = widget.items.where((e) => e.cover != null && e.cover!.isNotEmpty).take(6).toList();
    if (samples.isEmpty) return;

    var portrait = 0;
    var landscape = 0;
    for (final item in samples) {
      final ratio = await _aspect(item);
      if (ratio == null) continue;
      if (ratio >= 1.15) {
        landscape++;
      } else if (ratio <= 0.9) {
        portrait++;
      }
    }

    if (!mounted) return;
    // Require a clear majority. Ambiguous rows stay poster-shaped.
    final next = landscape > portrait && landscape >= 2;
    if (next != _landscape) setState(() => _landscape = next);
  }

  Future<double?> _aspect(MediaItem item) async {
    try {
      final provider = CachedNetworkImageProvider(
        item.cover!,
        headers: item.coverHeaders,
        cacheManager: AppImageCache.manager,
      );
      final config = createLocalImageConfiguration(context);
      final stream = provider.resolve(config);
      final completer = Completer<double?>();
      late ImageStreamListener listener;
      listener = ImageStreamListener((info, _) {
        if (!completer.isCompleted) {
          final image = info.image;
          completer.complete(image.height == 0 ? null : image.width / image.height);
        }
        stream.removeListener(listener);
      }, onError: (_, __) {
        if (!completer.isCompleted) completer.complete(null);
        stream.removeListener(listener);
      });
      stream.addListener(listener);
      return completer.future.timeout(const Duration(seconds: 4), onTimeout: () => null);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final landscape = _landscape;
    final scale = switch (sl<PlaybackPrefs>().posterSize) {
      'small' => 0.86,
      'large' => 1.14,
      'extra_large' => 1.30,
      _ => 1.0,
    };
    final width = landscape ? 210.0 : 140.0 * scale;
    final height = landscape ? 150.0 : 236.0 * scale;
    return ContentRow(
      title: widget.title,
      itemWidth: width,
      itemHeight: height,
      itemCount: widget.items.length,
      onSeeAll: widget.onSeeAll,
      itemBuilder: (context, index) {
        final item = widget.items[index];
        return PosterCard(
          title: item.title,
          imageUrl: item.cover,
          headers: item.coverHeaders,
          cellWidth: width,
          qualityBadge: item.quality,
          dubBadge: item.dubBadge,
          onTap: () => widget.onTap(item),
          onLongPress: () => widget.onLongPress(item),
        );
      },
    );
  }
}
