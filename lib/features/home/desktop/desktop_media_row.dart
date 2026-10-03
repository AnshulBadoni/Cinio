import 'package:flutter/material.dart';

import '../../../core/models/media_item.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import 'desktop_media_card.dart';

/// Desktop content row with smooth hover-activated left and right arrow
/// buttons for quick pagination without mouse dragging (Netflix style).
class DesktopMediaRow extends StatefulWidget {
  const DesktopMediaRow({
    super.key,
    required this.title,
    required this.items,
    required this.onTap,
    this.onSeeAll,
  });

  final String title;
  final List<MediaItem> items;
  final void Function(MediaItem item) onTap;
  final VoidCallback? onSeeAll;

  @override
  State<DesktopMediaRow> createState() => _DesktopMediaRowState();
}

class _DesktopMediaRowState extends State<DesktopMediaRow> {
  final ScrollController _scrollController = ScrollController();
  bool _hovered = false;
  bool _canScrollLeft = false;
  bool _canScrollRight = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollButtons);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollButtons);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollButtons() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final current = _scrollController.offset;
    final canLeft = current > 20;
    final canRight = current < max - 20;
    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  void _scroll(double delta) {
    if (!_scrollController.hasClients) return;
    final target = (_scrollController.offset + delta).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    const double cardWidth = 175;
    const double cardHeight = 260;
    const double rowHeight = cardHeight + 20; // Extra room for 1.05x hover scale

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header (Title + See all) ──────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Row(
              children: [
                Text(
                  widget.title,
                  style: AppText.title.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                if (widget.onSeeAll != null)
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: widget.onSeeAll,
                      child: Row(
                        children: [
                          Text(
                            'Explore all',
                            style: AppText.caption.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accent,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: AppColors.accent,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ── Carousel with Hover Arrows ───────────────────
          MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: SizedBox(
              height: rowHeight,
              child: Stack(
                children: [
                  // Horizontal List
                  ListView.separated(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 8),
                    itemCount: widget.items.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (context, index) {
                      final item = widget.items[index];
                      return DesktopMediaCard(
                        item: item,
                        width: cardWidth,
                        height: cardHeight,
                        onTap: () => widget.onTap(item),
                      );
                    },
                  ),

                  // Left Floating Arrow
                  if (_hovered && _canScrollLeft)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: _scrollArrow(
                        icon: Icons.chevron_left_rounded,
                        onTap: () => _scroll(-750),
                        isLeft: true,
                      ),
                    ),

                  // Right Floating Arrow
                  if (_hovered && _canScrollRight)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: _scrollArrow(
                        icon: Icons.chevron_right_rounded,
                        onTap: () => _scroll(750),
                        isLeft: false,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scrollArrow({
    required IconData icon,
    required VoidCallback onTap,
    required bool isLeft,
  }) {
    return Container(
      width: 44,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
          end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.transparent,
          ],
        ),
      ),
      child: Center(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.9),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
