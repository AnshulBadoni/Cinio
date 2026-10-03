// Loading skeleton and its shimmer gradient.
part of 'detail_screen.dart';


/// Shimmering placeholder shown while the detail loads — mirrors the real
/// layout (backdrop, title/meta, Play/Download, synopsis, credits) so the
/// screen eases in instead of popping from a blank spinner to a full page.
/// One shared [AnimationController] (same pattern as RowSkeleton/SkeletonGrid).
class _DetailSkeleton extends StatefulWidget {
  const _DetailSkeleton({
    required this.heroHeight,
    this.coverUrl,
    this.coverHeaders,
    this.heroTag,
  });

  final double heroHeight;
  final String? coverUrl;
  final Map<String, String>? coverHeaders;
  final String? heroTag;

  @override
  State<_DetailSkeleton> createState() => _DetailSkeletonState();
}

class _DetailSkeletonState extends State<_DetailSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    // One continuous forward sweep (not a reversing fade) reads as a real
    // shimmer rather than a dull pulse.
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _coverBackdrop() {
    final url = widget.coverUrl;
    if (url == null || url.isEmpty) {
      return ColoredBox(color: AppColors.surface2);
    }
    final aniSrcId = widget.coverHeaders?['x-ani-src'];
    final mihonSrcId = widget.coverHeaders?['x-mihon-src'];
    if (aniSrcId != null || mihonSrcId != null) {
      return Image(
        image: ResizeImage(
          aniSrcId != null
              ? AniyomiImage(int.parse(aniSrcId), url)
              : MihonImage(int.parse(mihonSrcId!), url),
          width: 1440,
        ),
        fit: BoxFit.cover,
        alignment: const Alignment(0, -0.20),
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) =>
            ColoredBox(color: AppColors.surface2),
      );
    }
    final effectiveHeaders =
        resolveEffectiveCoverHeaders(url, widget.coverHeaders);
    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: effectiveHeaders,
      fit: BoxFit.cover,
      alignment: const Alignment(0, -0.20),
      memCacheWidth: 1440,
      filterQuality: FilterQuality.high,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (c, u) => ColoredBox(color: AppColors.surface2),
      errorWidget: (c, u, e) => ColoredBox(color: AppColors.surface2),
    );
  }

  Widget _buildBackdropWithHero() {
    final backdrop = _coverBackdrop();
    if (widget.heroTag == null || widget.heroTag!.isEmpty) return backdrop;
    return Hero(
      tag: widget.heroTag!,
      createRectTween: (begin, end) =>
          MaterialRectArcTween(begin: begin, end: end),
      flightShuttleBuilder: posterHeroFlightShuttle,
      child: backdrop,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final base = AppColors.surface2;
    final highlight = Color.lerp(base, Colors.white, 0.14)!;

    Widget box(double w, double h, [double r = 8]) => ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: SizedBox(
        width: w,
        height: h,
        child: ColoredBox(color: base),
      ),
    );

    // The skeleton shapes, painted in the flat base colour. A moving highlight
    // is swept across them by the ShaderMask below.
    final shimmerShapes = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        box(width * 0.66, 26), // title
        const SizedBox(height: 12),
        box(width * 0.42, 14), // meta line
        const SizedBox(height: 20),
        box(double.infinity, 50, 14), // Play
        const SizedBox(height: 10),
        box(double.infinity, 50, 14), // Download
        const SizedBox(height: 22),
        box(double.infinity, 12), // synopsis line 1
        const SizedBox(height: 9),
        box(double.infinity, 12), // synopsis line 2
        const SizedBox(height: 9),
        box(width * 0.55, 12), // synopsis line 3
      ],
    );

    // A diagonal highlight band swept across the masked shapes — the classic
    // shimmer sheen, far livelier than a flat opacity pulse.
    final shimmerContent = AnimatedBuilder(
      animation: _ctrl,
      child: shimmerShapes,
      builder: (context, child) {
        final t =
            _ctrl.value * 3 - 1; // -1 → 2 : band enters left, exits right
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [base, highlight, base],
            stops: const [0.32, 0.5, 0.68],
            transform: _SlideGradient(t),
          ).createShader(bounds),
          child: child,
        );
      },
    );

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Real cover backdrop with matching Hero tag ─────────────
          SizedBox(
            width: double.infinity,
            height: widget.heroHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildBackdropWithHero(),
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: AppColors.topScrim),
                  ),
                ),
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.transparent,
                          AppColors.bg.withValues(alpha: 0.12),
                          AppColors.bg.withValues(alpha: 0.40),
                          AppColors.bg.withValues(alpha: 0.75),
                          AppColors.bg,
                        ],
                        stops: const [0.0, 0.28, 0.50, 0.70, 0.88, 1.0],
                      ),
                    ),
                  ),
                ),
                // Top-left back button so user can pop back even while loading
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 4,
                  left: 16,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.55),
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(CupertinoIcons.chevron_back,
                          color: Colors.white, size: 19.5),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 64),
            child: shimmerContent,
          ),
        ],
      ),
    );
  }
}

/// Translates a gradient horizontally by [t] × width — used to sweep the
/// shimmer highlight across the skeleton.
class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.t);

  final double t;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * t, 0, 0);
}

// ─────────────────────────────────────────────────────────────────────────────
// Cast Tab Skeleton — Shimmering grid of actor avatar cards shown while
// metadata enrichment is in flight.
// ─────────────────────────────────────────────────────────────────────────────

class _CastSkeletonTab extends StatelessWidget {
  const _CastSkeletonTab();

  @override
  Widget build(BuildContext context) {
    final base = AppColors.surface2;

    Widget box(double w, double h, [double r = 8]) => ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: SizedBox(
        width: w,
        height: h,
        child: ColoredBox(color: base),
      ),
    );

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
        childAspectRatio: 0.66,
      ),
      itemCount: 6,
      itemBuilder: (_, _) => Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 1,
              child: ColoredBox(color: base),
            ),
          ),
          const SizedBox(height: 8),
          box(70, 12, 4),
          const SizedBox(height: 4),
          box(45, 10, 4),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Relations Tab Skeleton — Shimmering grid of relation cards.
// ─────────────────────────────────────────────────────────────────────────────

class _RelationsSkeletonTab extends StatelessWidget {
  const _RelationsSkeletonTab();

  @override
  Widget build(BuildContext context) {
    final base = AppColors.surface2;

    Widget box(double w, double h, [double r = 8]) => ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: SizedBox(
        width: w,
        height: h,
        child: ColoredBox(color: base),
      ),
    );

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
        childAspectRatio: 0.47,
      ),
      itemCount: 6,
      itemBuilder: (_, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: ColoredBox(color: base),
            ),
          ),
          const SizedBox(height: 8),
          box(40, 10, 4),
          const SizedBox(height: 4),
          box(75, 12, 4),
        ],
      ),
    );
  }
}


