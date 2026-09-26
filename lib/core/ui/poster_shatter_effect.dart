import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// A wrapper widget that can shatter its child into broken polygon shards
/// with physics-driven explosive dispersal and gravity.
class PosterShatterEffect extends StatefulWidget {
  const PosterShatterEffect({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 700),
  });

  final Widget child;
  final Duration duration;

  @override
  State<PosterShatterEffect> createState() => PosterShatterEffectState();
}

class _Shard {
  _Shard({
    required this.path,
    required this.centroid,
    required this.vx,
    required this.vy,
    required this.rotSpeed,
  });

  final Path path;
  final Offset centroid;
  final double vx;
  final double vy;
  final double rotSpeed;
}

class _Debris {
  _Debris({
    required this.origin,
    required this.vx,
    required this.vy,
    required this.size,
  });

  final Offset origin;
  final double vx;
  final double vy;
  final double size;
}

class PosterShatterEffectState extends State<PosterShatterEffect>
    with SingleTickerProviderStateMixin {
  final GlobalKey _boundaryKey = GlobalKey();
  late final AnimationController _controller;
  ui.Image? _snapshot;
  List<_Shard> _shards = const [];
  List<_Debris> _debris = const [];
  bool _isShattering = false;

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

  /// Trigger the shatter animation. Returns a Future that completes when the
  /// pieces have finished scattering.
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
        // Fall back gracefully to color-shaded shards
      }
      _generateShards(size);
    }

    if (mounted) {
      setState(() => _isShattering = true);
      await _controller.forward(from: 0.0);
    }
  }

  void _generateShards(Size size) {
    final shards = <_Shard>[];
    final debris = <_Debris>[];
    final rng = math.Random();
    const cols = 5;
    const rows = 7;
    final cellW = size.width / cols;
    final cellH = size.height / rows;
    final center = Offset(size.width / 2, size.height / 2);

    // Generate perturbed grid points
    final points = List.generate(
      rows + 1,
      (r) => List.generate(cols + 1, (c) {
        if (r == 0 || r == rows || c == 0 || c == cols) {
          return Offset(c * cellW, r * cellH);
        }
        final jx = (rng.nextDouble() - 0.5) * cellW * 0.55;
        final jy = (rng.nextDouble() - 0.5) * cellH * 0.55;
        return Offset(c * cellW + jx, r * cellH + jy);
      }),
    );

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final p00 = points[r][c];
        final p10 = points[r][c + 1];
        final p11 = points[r + 1][c + 1];
        final p01 = points[r + 1][c];

        // Split quad into two triangular shards
        for (final tri in [
          [p00, p10, p11],
          [p00, p11, p01],
        ]) {
          final cx = (tri[0].dx + tri[1].dx + tri[2].dx) / 3;
          final cy = (tri[0].dy + tri[1].dy + tri[2].dy) / 3;
          final centroid = Offset(cx, cy);

          final path = Path()
            ..moveTo(tri[0].dx, tri[0].dy)
            ..lineTo(tri[1].dx, tri[1].dy)
            ..lineTo(tri[2].dx, tri[2].dy)
            ..close();

          final angle = math.atan2(cy - center.dy, cx - center.dx);
          final dist = (centroid - center).distance;
          final speed = 160.0 + rng.nextDouble() * 240.0 + dist * 0.4;
          final vx = math.cos(angle) * speed + (rng.nextDouble() - 0.5) * 60;
          final vy = math.sin(angle) * speed - 110.0 - rng.nextDouble() * 90;
          final rotSpeed = (rng.nextDouble() - 0.5) * 12.0;

          shards.add(_Shard(
            path: path,
            centroid: centroid,
            vx: vx,
            vy: vy,
            rotSpeed: rotSpeed,
          ));
        }

        // Add 1-2 small debris particles per cell
        if (rng.nextDouble() > 0.5) {
          final dx = c * cellW + rng.nextDouble() * cellW;
          final dy = r * cellH + rng.nextDouble() * cellH;
          final angle = rng.nextDouble() * math.pi * 2;
          debris.add(_Debris(
            origin: Offset(dx, dy),
            vx: math.cos(angle) * (100 + rng.nextDouble() * 180),
            vy: math.sin(angle) * (100 + rng.nextDouble() * 180) - 130,
            size: 1.5 + rng.nextDouble() * 2.5,
          ));
        }
      }
    }

    _shards = shards;
    _debris = debris;
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
          painter: _ShatterPainter(
            progress: _controller.value,
            snapshot: _snapshot,
            shards: _shards,
            debris: _debris,
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

class _ShatterPainter extends CustomPainter {
  _ShatterPainter({
    required this.progress,
    required this.snapshot,
    required this.shards,
    required this.debris,
  });

  final double progress;
  final ui.Image? snapshot;
  final List<_Shard> shards;
  final List<_Debris> debris;

  @override
  void paint(Canvas canvas, Size size) {
    if (shards.isEmpty) return;
    const gravity = 880.0; // px/s^2
    final t = progress * 0.72; // time in seconds
    final fade = (1.0 - progress * 1.15).clamp(0.0, 1.0);

    final img = snapshot;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: fade)
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.medium;

    final fallbackPaint = Paint()
      ..color = AppColors.surface2.withValues(alpha: fade)
      ..style = PaintingStyle.fill;

    for (final shard in shards) {
      final dx = shard.vx * t;
      final dy = shard.vy * t + 0.5 * gravity * t * t;
      final rot = shard.rotSpeed * t;
      final scale = math.max(0.0, 1.0 - progress * 0.35);

      canvas.save();
      canvas.translate(shard.centroid.dx + dx, shard.centroid.dy + dy);
      canvas.rotate(rot);
      canvas.scale(scale);
      canvas.translate(-shard.centroid.dx, -shard.centroid.dy);

      canvas.clipPath(shard.path);
      if (img != null) {
        final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
        final dst = Rect.fromLTWH(0, 0, size.width, size.height);
        canvas.drawImageRect(img, src, dst, paint);
      } else {
        canvas.drawPath(shard.path, fallbackPaint);
      }
      canvas.restore();
    }

    // Draw small flying debris particles
    final debrisPaint = Paint()
      ..color = Colors.white.withValues(alpha: (fade * 0.85).clamp(0.0, 1.0));
    for (final d in debris) {
      final dx = d.origin.dx + d.vx * t;
      final dy = d.origin.dy + d.vy * t + 0.5 * (gravity * 1.1) * t * t;
      canvas.drawCircle(Offset(dx, dy), d.size * (1.0 - progress * 0.5), debrisPaint);
    }
  }

  @override
  bool shouldRepaint(_ShatterPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
