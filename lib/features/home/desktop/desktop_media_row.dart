import 'package:flutter/material.dart';

import '../../../core/models/media_item.dart';
import 'desktop_media_card.dart';

/// Desktop content rail. Each rail intentionally chooses either portrait or
/// landscape artwork; cards are never stretched between aspect ratios.
class DesktopMediaRow extends StatefulWidget {
  const DesktopMediaRow({
    super.key,
    required this.title,
    required this.items,
    required this.onTap,
    this.onSeeAll,
    this.landscape = false,
    this.showTitles = true,
    this.padding,
  });

  final String title;
  final List<MediaItem> items;
  final void Function(MediaItem item) onTap;
  final VoidCallback? onSeeAll;
  final bool landscape;
  final bool showTitles;
  final EdgeInsetsGeometry? padding;

  @override
  State<DesktopMediaRow> createState() => _DesktopMediaRowState();
}

class _DesktopMediaRowState extends State<DesktopMediaRow> {
  final ScrollController _scrollController = ScrollController();
  bool _hovered = false;
  bool _canScrollLeft = false;
  bool _canScrollRight = true;

  double get _cardWidth => widget.landscape ? 310 : 160;
  double get _cardHeight => widget.landscape ? 175 : 240;
  double get _itemExtent => _cardWidth + 22;

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
    final left = current > 20;
    final right = current < max - 20;
    if (left != _canScrollLeft || right != _canScrollRight) {
      setState(() {
        _canScrollLeft = left;
        _canScrollRight = right;
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
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    final cardBottom = widget.showTitles ? (widget.landscape ? 48.0 : 48.0) : 0.0;
    final rowHeight = _cardHeight + cardBottom;

    return Padding(
      padding: widget.padding ?? const EdgeInsets.only(top: 26, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 56),
            child: Row(
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                if (widget.onSeeAll != null)
                  _SeeAllButton(onTap: widget.onSeeAll!),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: rowHeight,
            child: MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: Stack(
                children: [
                  ListView.separated(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 56),
                    physics: const ClampingScrollPhysics(),
                    itemCount: widget.items.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 22),
                    itemBuilder: (context, index) {
                      final item = widget.items[index];
                      return DesktopMediaCard(
                        item: item,
                        landscape: widget.landscape,
                        showTitle: widget.showTitles,
                        width: _cardWidth,
                        height: _cardHeight,
                        onTap: () => widget.onTap(item),
                      );
                    },
                  ),
                  if (_hovered && _canScrollLeft)
                    Positioned(
                      left: 18,
                      top: rowHeight / 2 - 22,
                      child: _RowChevron(
                        icon: Icons.chevron_left_rounded,
                        onTap: () => _scroll(-_itemExtent * 3),
                      ),
                    ),
                  if (_hovered && _canScrollRight)
                    Positioned(
                      right: 18,
                      top: rowHeight / 2 - 22,
                      child: _RowChevron(
                        icon: Icons.chevron_right_rounded,
                        onTap: () => _scroll(_itemExtent * 3),
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
}

class _SeeAllButton extends StatelessWidget {
  const _SeeAllButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Icon(
            Icons.chevron_right_rounded,
            size: 22,
            color: Colors.white.withValues(alpha: 0.65),
          ),
        ),
      ),
    );
  }
}

class _RowChevron extends StatelessWidget {
  const _RowChevron({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: Colors.white, size: 27),
        ),
      ),
    );
  }
}
