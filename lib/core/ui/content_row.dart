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
  });

  final String title;
  final String? overline;
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final double itemWidth;
  final double itemHeight;
  final VoidCallback? onSeeAll;
  final VoidCallback? onLoadMore;

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
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (widget.onLoadMore == null || !_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      widget.onLoadMore!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Header(title: widget.title, overline: widget.overline, onSeeAll: widget.onSeeAll),
        SizedBox(
          height: widget.itemHeight,
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // With a screen reader on, build every item (not just the lazy
            // window) so TalkBack can focus each one and the row auto-scrolls to
            // it — otherwise horizontal swipe navigation stalls at the first few.
            // Sighted users keep the lazy 600px window unchanged.
            cacheExtent: MediaQuery.of(context).accessibleNavigation
                ? double.infinity
                : 600,
            itemCount: widget.itemCount,
            itemBuilder: (context, index) => Padding(
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
