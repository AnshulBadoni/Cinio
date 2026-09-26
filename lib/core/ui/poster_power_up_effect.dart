import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// A wrapper widget that plays a subtle, premium "power up" animation on its child.
/// Includes a slight scale bounce, radiant diagonal light sweep, accent glow aura,
/// and small ascending energy spark particles.
class PosterPowerUpEffect extends StatefulWidget {
  const PosterPowerUpEffect({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 650),
    this.glowColor,
  });

  final Widget child;
  final Duration duration;
  final Color? glowColor;

  @override
  State<PosterPowerUpEffect> createState() => PosterPowerUpEffectState();
}

class _Spark {
  _Spark({
    required this.xRatio,
    required this.speed,
    required this.size,
    required this.wobblePhase,
  });

  final double xRatio;
  final double speed;
  final double size;
  final double wobblePhase;
}

class PosterPowerUpEffectState extends State<PosterPowerUpEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  List<_Spark> _sparks = const [];

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
    super.dispose();
  }

  /// Trigger the power-up animation. Returns a Future that completes when the
  /// animation finishes.
  Future<void> powerUp() async {
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}

    final rng = math.Random();
    _sparks = List.generate(8, (_) => _Spark(
      xRatio: 0.15 + rng.nextDouble() * 0.70,
      speed: 120.0 + rng.nextDouble() * 140.0,
      size: 2.0 + rng.nextDouble() * 2.5,
      wobblePhase: rng.nextDouble() * math.pi * 2,
    ));

    if (mounted) {
      await _controller.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auraColor = widget.glowColor ?? AppColors.accent;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        if (t == 0.0 || t == 1.0) {
          return widget.child;
        }

        // Subtle scale pulse: 1.0 -> 1.035 -> 1.0
        final scale = 1.0 + math.sin(t * math.pi) * 0.035;

        // Aura glow swell: peaks at t ~ 0.35, fades by t ~ 0.85
        final auraIntensity = (math.sin(t * math.pi) * (1.0 - t * 0.3)).clamp(0.0, 1.0);
        final sweepPosition = -0.5 + t * 2.0;

        return Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: auraIntensity > 0.05
                  ? [
                      BoxShadow(
                        color: auraColor.withValues(alpha: (auraIntensity * 0.65).clamp(0.0, 1.0)),
                        blurRadius: 18 * auraIntensity + 4,
                        spreadRadius: 2.5 * auraIntensity,
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  widget.child,

                  // Subtle border flash
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: auraColor.withValues(alpha: (auraIntensity * 0.85).clamp(0.0, 1.0)),
                            width: 1.8,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Diagonal radiant gleam sweep
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _GleamSweepPainter(
                          position: sweepPosition,
                          opacity: (math.sin(t * math.pi) * 0.45).clamp(0.0, 0.45),
                        ),
                      ),
                    ),
                  ),

                  // Rising sparks
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _SparksPainter(
                          progress: t,
                          sparks: _sparks,
                          color: auraColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _GleamSweepPainter extends CustomPainter {
  _GleamSweepPainter({
    required this.position,
    required this.opacity,
  });

  final double position;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.0) return;
    final w = size.width;
    final h = size.height;

    final startX = position * w - w * 0.3;
    final endX = startX + w * 0.6;

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: opacity),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTRB(startX, 0, endX, h))
      ..blendMode = BlendMode.screen;

    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);
  }

  @override
  bool shouldRepaint(_GleamSweepPainter oldDelegate) =>
      oldDelegate.position != position || oldDelegate.opacity != opacity;
}

class _SparksPainter extends CustomPainter {
  _SparksPainter({
    required this.progress,
    required this.sparks,
    required this.color,
  });

  final double progress;
  final List<_Spark> sparks;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (sparks.isEmpty) return;
    final t = progress;
    final fade = (math.sin(t * math.pi) * 0.9).clamp(0.0, 1.0);
    if (fade <= 0.0) return;

    final sparkPaint = Paint()
      ..color = color.withValues(alpha: fade)
      ..style = PaintingStyle.fill;

    final corePaint = Paint()
      ..color = Colors.white.withValues(alpha: fade)
      ..style = PaintingStyle.fill;

    for (final s in sparks) {
      final baseY = size.height * 0.95 - (s.speed * t);
      final wobble = math.sin(t * 8.0 + s.wobblePhase) * 6.0;
      final x = s.xRatio * size.width + wobble;
      final y = baseY;

      if (y > -10 && y < size.height + 10) {
        final currentSize = s.size * (1.0 - t * 0.4);
        canvas.drawCircle(Offset(x, y), currentSize, sparkPaint);
        canvas.drawCircle(Offset(x, y), currentSize * 0.5, corePaint);
      }
    }
  }

  @override
  bool shouldRepaint(_SparksPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
