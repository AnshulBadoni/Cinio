import 'package:flutter/material.dart';

import '../../../core/models/media_item.dart';
import 'desktop_media_card.dart';

/// Desktop content rail matching the reference design: clean section title
/// with "See All >", portrait 2:3 posters with title underneath, and smooth
/// hover chevron buttons for fast browsing.
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

    // Responsive portrait card sizing (approx 2:3 ratio)
    const cardWidth = 165.0;
    const cardHeight = 248.0;
    const rowHeight = cardHeight + 54.0; // poster + 9px gap + 2 lines of text

    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section Title & "See All >" ───────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 56),
            child: Row(
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
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

          // ── Scrollable Row with Hover Chevrons ────────────────────
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
                    padding: const EdgeInsets.symmetric(horizontal: 56),
                    itemCount: widget.items.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 16),
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

                  // Left Chevron
                  if (_hovered && _canScrollLeft)
                    Positioned(
                      left: 12,
                      top: 0,
                      bottom: 50,
                      child: Center(
                        child: _RowChevron(
                          icon: Icons.chevron_left_rounded,
                          onTap: () => _scroll(-cardWidth * 3.5),
                        ),
                      ),
                    ),

                  // Right Chevron
                  if (_hovered && _canScrollRight)
                    Positioned(
                      right: 12,
                      top: 0,
                      bottom: 50,
                      child: Center(
                        child: _RowChevron(
                          icon: Icons.chevron_right_rounded,
                          onTap: () => _scroll(cardWidth * 3.5),
                        ),
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

class _SeeAllButton extends StatefulWidget {
  const _SeeAllButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_SeeAllButton> createState() => _SeeAllButtonState();
}

class _SeeAllButtonState extends State<_SeeAllButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 160),
          style: TextStyle(
            color: _hovered
                ? Colors.white
                : Colors.white.withValues(alpha: 0.55),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('See All'),
              const SizedBox(width: 3),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: _hovered
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowChevron extends StatefulWidget {
  const _RowChevron({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_RowChevron> createState() => _RowChevronState();
}

class _RowChevronState extends State<_RowChevron> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 140),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: _hovered ? 0.85 : 0.65),
              border: Border.all(
                color: Colors.white.withValues(alpha: _hovered ? 0.35 : 0.15),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Icon(widget.icon, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }
}
