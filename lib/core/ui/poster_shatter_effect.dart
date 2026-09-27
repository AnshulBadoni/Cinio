import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// A wrapper widget that disintegrates its child into floating ash and dust
/// particles with a sweeping erosion wave and wind drift (Thanos snap effect).
class PosterShatterEffect extends StatefulWidget {
  const PosterShatterEffect({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 850),
  });

  final Widget child;
  final Duration duration;

  @override
  State<PosterShatterEffect> createState() => PosterShatterEffectState();
}

class _AshFlake {
  _AshFlake({
    required this.srcRect,
    required this.dstRect,
    required this.center,
    required this.vx,
    required this.vy,
    required this.lift,
    required this.swayFreq,
    required this.swayAmp,
    required this.swayPhase,
    required this.rotSpeed,
    required this.delay,
  });

  final Rect srcRect;
  final Rect dstRect;
  final Offset center;
  final double vx;
  final double vy;
  final double lift;
  final double swayFreq;
  final double swayAmp;
  final double swayPhase;
  final double rotSpeed;
  final double delay;
}

class _Ember {
  _Ember({
    required this.origin,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    required this.delay,
    required this.swayFreq,
    required this.swayAmp,
  });

  final Offset origin;
  final double vx;
  final double vy;
  final double size;
  final Color color;
  final double delay;
  final double swayFreq;
  final double swayAmp;
}

class PosterShatterEffectState extends State<PosterShatterEffect>
    with SingleTickerProviderStateMixin {
  final GlobalKey _boundaryKey = GlobalKey();
  late final AnimationController _controller;
  ui.Image? _snapshot;
  List<_AshFlake> _flakes = const [];
  List<_Ember> _embers = const [];
  bool _isShattering = false;

  static const _emberPalette = [
    Color(0xFFFFA726), // Amber glow
    Color(0xFFFF7043), // Orange spark
    Color(0xFFCFD8DC), // Light ash
    Color(0xFF90A4AE), // Medium ash
    Color(0xFF455A64), // Charcoal
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _snapshot?.dispose();
    super.dispose();
  }

  /// Trigger the Thanos snap ash disintegration animation.
  /// Returns a Future that completes when all particles have faded away.
  Future<void> shatter() async {
    if (_isShattering) return;
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}

    final boundary = _boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary != null && boundary.hasSize) {
      final size = boundary.size;
      try {
        _snapshot = await boundary.toImage(pixelRatio: 2.0);
      } catch (_) {
        // Fall back gracefully to color-shaded flakes
      }
      _generateAsh(size);
    }

    if (mounted) {
      setState(() => _isShattering = true);
      await _controller.forward(from: 0.0);
    }
  }

  /// Alias for [shatter] to match the disintegration theme.
  Future<void> disintegrate() => shatter();

  void _generateAsh(Size size) {
    final flakes = <_AshFlake>[];
    final embers = <_Ember>[];
    final rng = math.Random();

    const cols = 16;
    const rows = 24;
    final cellW = size.width / cols;
    final cellH = size.height / rows;

    final imgW = _snapshot?.width.toDouble() ?? (size.width * 2.0);
    final imgH = _snapshot?.height.toDouble() ?? (size.height * 2.0);
    final srcCellW = imgW / cols;
    final srcCellH = imgH / rows;

    for (var r = 0; r < rows; r++) {
      final ny = r / (rows - 1); // 0.0 (top) to 1.0 (bottom)
      for (var c = 0; c < cols; c++) {
        final nx = c / (cols - 1); // 0.0 (left) to 1.0 (right)

        final dstRect = Rect.fromLTWH(c * cellW, r * cellH, cellW, cellH);
        final srcRect =
            Rect.fromLTWH(c * srcCellW, r * srcCellH, srcCellW, srcCellH);

        // Diagonal erosion wave: sweeps from bottom-left up towards top-right
        final waveDist =
            (1.0 - ny) * 0.42 + nx * 0.22 + (rng.nextDouble() - 0.5) * 0.08;
        final delay = (waveDist / 0.70 * 0.48).clamp(0.0, 0.52);

        // Drift wind physics: blowing rightward and lifting gently
        final vx = 75.0 + rng.nextDouble() * 150.0;
        final vy = -35.0 - rng.nextDouble() * 70.0;
        final lift = 20.0 + rng.nextDouble() * 35.0;
        final swayFreq = 1.2 + rng.nextDouble() * 1.8;
        final swayAmp = 8.0 + rng.nextDouble() * 16.0;
        final swayPhase = rng.nextDouble() * math.pi * 2;
        final rotSpeed = (rng.nextDouble() - 0.5) * 5.0;

        flakes.add(_AshFlake(
          srcRect: srcRect,
          dstRect: dstRect,
          center: dstRect.center,
          vx: vx,
          vy: vy,
          lift: lift,
          swayFreq: swayFreq,
          swayAmp: swayAmp,
          swayPhase: swayPhase,
          rotSpeed: rotSpeed,
          delay: delay,
        ));
      }
    }

    // Generate flying ember and dust specks along the erosion front
    const emberCount = 95;
    for (var i = 0; i < emberCount; i++) {
      final ox = rng.nextDouble() * size.width;
      final oy = rng.nextDouble() * size.height;
      final nx = ox / size.width;
      final ny = oy / size.height;

      final waveDist =
          (1.0 - ny) * 0.42 + nx * 0.22 + (rng.nextDouble() - 0.5) * 0.08;
      final delay = (waveDist / 0.70 * 0.48).clamp(0.0, 0.52);

      embers.add(_Ember(
        origin: Offset(ox, oy),
        vx: 110.0 + rng.nextDouble() * 190.0,
        vy: -70.0 - rng.nextDouble() * 130.0,
        size: 1.2 + rng.nextDouble() * 2.2,
        color: _emberPalette[rng.nextInt(_emberPalette.length)],
        delay: delay,
        swayFreq: 1.5 + rng.nextDouble() * 2.0,
        swayAmp: 10.0 + rng.nextDouble() * 16.0,
      ));
    }

    _flakes = flakes;
    _embers = embers;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        if (!_isShattering) {
          return RepaintBoundary(
            key: _boundaryKey,
            child: widget.child,
          );
        }

        return CustomPaint(
          size: Size.infinite,
          painter: _DisintegratePainter(
            progress: _controller.value,
            snapshot: _snapshot,
            flakes: _flakes,
            embers: _embers,
          ),
          child: Opacity(
            opacity: 0.0,
            child: widget.child,
          ),
        );
      },
    );
  }
}

class _DisintegratePainter extends CustomPainter {
  _DisintegratePainter({
    required this.progress,
    required this.snapshot,
    required this.flakes,
    required this.embers,
  });

  final double progress;
  final ui.Image? snapshot;
  final List<_AshFlake> flakes;
  final List<_Ember> embers;

  final Paint _intactPaint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.low;

  final Paint _flakePaint = Paint()
    ..isAntiAlias = true
    ..filterQuality = FilterQuality.low;

  final Paint _fallbackPaint = Paint()..style = PaintingStyle.fill;
  final Paint _emberPaint = Paint()..isAntiAlias = true;

  @override
  void paint(Canvas canvas, Size size) {
    if (flakes.isEmpty) return;

    final img = snapshot;

    for (final flake in flakes) {
      final localProgress =
          flake.delay >= 1.0 ? 0.0 : ((progress - flake.delay) / (1.0 - flake.delay));

      if (localProgress <= 0.0) {
        // Before the erosion wave reaches this patch, draw in place
        if (img != null) {
          canvas.drawImageRect(img, flake.srcRect, flake.dstRect, _intactPaint);
        } else {
          _fallbackPaint.color = AppColors.surface2;
          canvas.drawRect(flake.dstRect, _fallbackPaint);
        }
      } else if (localProgress < 1.0) {
        // Flake has detached: float, drift, char to ash, shrink and fade
        final tau = localProgress;
        final alpha = math.pow(1.0 - tau, 1.35).toDouble().clamp(0.0, 1.0);
        if (alpha <= 0.01) continue;

        final dx = flake.vx * tau +
            math.sin(flake.swayFreq * tau * math.pi * 2 + flake.swayPhase) *
                flake.swayAmp;
        final dy = flake.vy * tau -
            flake.lift * math.sin(tau * math.pi) +
            (tau * tau * 35.0);
        final scale = (1.0 - tau * 0.72).clamp(0.0, 1.0);
        final rot = flake.rotSpeed * tau;

        canvas.save();
        canvas.translate(flake.center.dx + dx, flake.center.dy + dy);
        canvas.rotate(rot);
        canvas.scale(scale);
        canvas.translate(-flake.center.dx, -flake.center.dy);

        // Char and darken as the flake turns to ash
        final charFactor = (tau * 1.8).clamp(0.0, 0.88);
        _flakePaint.color = Colors.white.withValues(alpha: alpha);
        _flakePaint.colorFilter = ColorFilter.mode(
          Color.lerp(Colors.transparent, const Color(0xFF212124), charFactor)!,
          BlendMode.srcATop,
        );

        if (img != null) {
          canvas.drawImageRect(img, flake.srcRect, flake.dstRect, _flakePaint);
        } else {
          _fallbackPaint.color = Color.lerp(
            AppColors.surface2,
            const Color(0xFF212124),
            charFactor,
          )!
              .withValues(alpha: alpha);
          canvas.drawRect(flake.dstRect, _fallbackPaint);
        }
        canvas.restore();
      }
      // If localProgress >= 1.0, particle has completely dissolved into ash
    }

    // Draw floating embers and ash dust motes
    for (final ember in embers) {
      final localProgress =
          ember.delay >= 1.0 ? 0.0 : ((progress - ember.delay) / (1.0 - ember.delay));
      if (localProgress <= 0.0 || localProgress >= 1.0) continue;

      final tau = localProgress;
      final alpha = math.pow(1.0 - tau, 1.25).toDouble().clamp(0.0, 1.0);
      final dx = ember.vx * tau +
          math.sin(ember.swayFreq * tau * math.pi * 2) * ember.swayAmp;
      final dy = ember.vy * tau + (tau * tau * 20.0);
      final currentSize = ember.size * (1.0 - tau * 0.45);

      _emberPaint.color = ember.color.withValues(alpha: alpha);
      canvas.drawCircle(
        Offset(ember.origin.dx + dx, ember.origin.dy + dy),
        currentSize,
        _emberPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_DisintegratePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
