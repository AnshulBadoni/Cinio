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
  });

  final String title;
  final List<MediaItem> items;
  final void Function(MediaItem item) onTap;
  final VoidCallback? onSeeAll;
  final bool landscape;

  @override
  State<DesktopMediaRow> createState() => _DesktopMediaRowState();
}

class _DesktopMediaRowState extends State<DesktopMediaRow> {
  final ScrollController _scrollController = ScrollController();
  bool _hovered = false;
  bool _canScrollLeft = false;
  bool _canScrollRight = true;

  double get _cardWidth => widget.landscape ? 300 : 165;
  double get _cardHeight => widget.landscape ? 169 : 275;
  double get _itemExtent => _cardWidth + 20;

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

    final cardBottom = widget.landscape ? 48.0 : 54.0;
    final rowHeight = _cardHeight + cardBottom;

    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 8),
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
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
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
                    separatorBuilder: (_, _) => const SizedBox(width: 20),
                    itemBuilder: (context, index) {
                      final item = widget.items[index];
                      return DesktopMediaCard(
                        item: item,
                        landscape: widget.landscape,
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
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white.withValues(alpha: 0.58),
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.chevron_right_rounded, size: 17),
      label: const Text('See all'),
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
