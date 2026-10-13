import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import '../theme/app_text.dart';
import 'reveal_item.dart';

/// An edge-bleed horizontal content row with an optional header and "See All" link.
///
/// Content scrolls lazily via [ListView.builder] so items off-screen are never
/// built. Left/right padding is 16 px; items spill off the right edge to signal
/// "more" (no right-side padding on the list itself).
class ContentRow extends StatefulWidget {
  const ContentRow({
    super.key,
    required this.title,
    this.overline,
    required this.itemCount,
    required this.itemBuilder,
    this.itemWidth = 124,
    this.itemHeight = 210,
    this.onSeeAll,
    this.onLoadMore,
    this.isLoadingMore = false,
  });

  final String title;
  final String? overline;
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final double itemWidth;
  final double itemHeight;
  final VoidCallback? onSeeAll;
  final VoidCallback? onLoadMore;
  final bool isLoadingMore;

  @override
  State<ContentRow> createState() => _ContentRowState();
}

class _ContentRowState extends State<ContentRow> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant ContentRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.isLoadingMore && !widget.isLoadingMore) ||
        (oldWidget.itemCount != widget.itemCount)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onScroll();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (widget.onLoadMore == null || widget.isLoadingMore || !_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final current = _scrollController.position.pixels;
    if (max > 0 && current >= max - 350) {
      widget.onLoadMore!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final showLoadingCard = widget.isLoadingMore;
    final totalCount = widget.itemCount + (showLoadingCard ? 1 : 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Header(title: widget.title, overline: widget.overline, onSeeAll: widget.onSeeAll),
        SizedBox(
          height: widget.itemHeight,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.axis == Axis.horizontal) {
                if (widget.onLoadMore != null && !widget.isLoadingMore) {
                  final max = notification.metrics.maxScrollExtent;
                  final current = notification.metrics.pixels;
                  if (max > 0 && current >= max - 350) {
                    widget.onLoadMore!();
                  }
                }
              }
              return false;
            },
            child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              // With a screen reader on, build every item (not just the lazy
              // window) so TalkBack can focus each one and the row auto-scrolls to
              // it — otherwise horizontal swipe navigation stalls at the first few.
              // Sighted users keep the lazy 600px window unchanged.
              cacheExtent: MediaQuery.of(context).accessibleNavigation
                  ? double.infinity
                  : 600,
              itemCount: totalCount,
            itemBuilder: (context, index) {
              if (index >= widget.itemCount) {
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: widget.itemWidth,
                    height: widget.itemHeight,
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white38,
                        ),
                      ),
                    ),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: SizedBox(
                  width: widget.itemWidth,
                  child: RepaintBoundary(
                    child: RevealItem(
                      index: index,
                      child: widget.itemBuilder(context, index),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ],
  );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.overline, this.onSeeAll});

  final String title;
  final String? overline;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (overline != null) ...[
            Text(overline!, style: AppText.overline),
            const SizedBox(height: 2),
          ],
          if (onSeeAll != null)
            Row(
              children: [
                Expanded(child: Text(title, style: AppText.headline)),
                _GlassChevronButton(onTap: onSeeAll!),
              ],
            )
          else
            Text(title, style: AppText.headline),
        ],
      ),
    );
  }
}

class _GlassChevronButton extends StatefulWidget {
  const _GlassChevronButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_GlassChevronButton> createState() => _GlassChevronButtonState();
}

class _GlassChevronButtonState extends State<_GlassChevronButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: AnimatedScale(
          scale: _pressed ? 0.90 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x6618181E),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                    width: 0.65,
                  ),
                ),
                child: const Center(
                  child: Padding(
                    padding: EdgeInsets.only(left: 1.5),
                    child: Icon(
                      CupertinoIcons.chevron_right,
                      size: 13,
                      color: Color(0xDDFFFFFF),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
