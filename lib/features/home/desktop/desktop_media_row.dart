import 'package:flutter/material.dart';

import '../../../core/models/media_item.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import 'desktop_media_card.dart';

/// Desktop-only landscape content rail, intentionally closer to modern
/// streaming-service desktop layouts than a poster grid.
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollButtons());
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

    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth = (screenWidth * 0.19).clamp(245.0, 315.0).toDouble();
    final cardHeight = cardWidth * 9 / 16;
    final rowHeight = cardHeight + 24;

    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 56),
            child: Row(
              children: [
                Text(
                  widget.title,
                  style: AppText.title.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
                if (widget.onSeeAll != null)
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: widget.onSeeAll,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Explore all',
                            style: AppText.caption.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 17,
                            color: AppColors.textTertiary,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: SizedBox(
              height: rowHeight,
              child: Stack(
                children: [
                  ListView.separated(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 56,
                      vertical: 5,
                    ),
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
                  if (_hovered && _canScrollLeft)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: _scrollArrow(
                        icon: Icons.chevron_left_rounded,
                        onTap: () => _scroll(-cardWidth * 2.3),
                        isLeft: true,
                      ),
                    ),
                  if (_hovered && _canScrollRight)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: _scrollArrow(
                        icon: Icons.chevron_right_rounded,
                        onTap: () => _scroll(cardWidth * 2.3),
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
    return SizedBox(
      width: 62,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
            end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
            colors: [
              Colors.black.withValues(alpha: 0.72),
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
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.58),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
                child: Icon(icon, color: Colors.white, size: 23),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
