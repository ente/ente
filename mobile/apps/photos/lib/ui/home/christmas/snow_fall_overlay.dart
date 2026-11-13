import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

enum SnowflakeStyle { circles, stars, mixed }

class _Snowflake {
  double x;
  double y;
  double radius;
  double speed;
  double drift;
  double phase;
  double rotation;
  double rotationSpeed;
  bool isStar;

  _Snowflake({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.drift,
    required this.phase,
    required this.rotation,
    required this.rotationSpeed,
    required this.isStar,
  });

  factory _Snowflake.random(Random random, SnowflakeStyle style) {
    return _Snowflake(
      x: random.nextDouble(),
      y: -random.nextDouble() * 0.5,
      radius: 1.0 + random.nextDouble() * 3.0,
      speed: 0.3 + random.nextDouble() * 0.7,
      drift: 0.02 + random.nextDouble() * 0.04,
      phase: random.nextDouble() * 2 * pi,
      rotation: random.nextDouble() * 2 * pi,
      rotationSpeed: (random.nextDouble() - 0.5) * 0.1,
      isStar:
          style == SnowflakeStyle.stars ||
          (style == SnowflakeStyle.mixed && random.nextBool()),
    );
  }
}

class _SnowPainter extends CustomPainter {
  final List<_Snowflake> snowflakes;
  final SnowflakeStyle style;
  final Color color;
  final double time;
  final double baseSpeed;
  final Random _random = Random();

  static final Path _starPath = _buildStarPath();

  _SnowPainter({
    required this.snowflakes,
    required this.style,
    required this.color,
    required this.time,
    required this.baseSpeed,
    required Listenable repaint,
  }) : super(repaint: repaint);

  static Path _buildStarPath() {
    final path = Path();
    const points = 6;
    const outerRadius = 1.0;
    const innerRadius = 0.4;

    for (int i = 0; i < points * 2; i++) {
      final radius = i.isEven ? outerRadius : innerRadius;
      final angle = (i * pi / points) - pi / 2;
      final x = cos(angle) * radius;
      final y = sin(angle) * radius;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const deltaTime = 0.016;

    for (final flake in snowflakes) {
      flake.x += sin(time * 2 + flake.phase) * flake.drift * deltaTime;
      flake.y += flake.speed * baseSpeed * deltaTime * 0.3;
      flake.rotation += flake.rotationSpeed;

      if (flake.y > 1.1) {
        flake.y = -0.1;
        flake.x = _random.nextDouble();
      }
      if (flake.x < -0.1) flake.x = 1.1;
      if (flake.x > 1.1) flake.x = -0.1;
    }

    if (style == SnowflakeStyle.circles) {
      _drawCircles(canvas, size);
    } else if (style == SnowflakeStyle.stars) {
      _drawStars(canvas, size);
    } else {
      _drawMixed(canvas, size);
    }
  }

  void _drawCircles(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.fill;

    final smallFlakes = <Offset>[];
    final mediumFlakes = <Offset>[];
    final largeFlakes = <Offset>[];

    for (final flake in snowflakes) {
      final offset = Offset(flake.x * size.width, flake.y * size.height);
      if (flake.radius < 2) {
        smallFlakes.add(offset);
      } else if (flake.radius < 3) {
        mediumFlakes.add(offset);
      } else {
        largeFlakes.add(offset);
      }
    }

    paint.strokeWidth = 3;
    if (smallFlakes.isNotEmpty) {
      canvas.drawPoints(PointMode.points, smallFlakes, paint);
    }
    paint.strokeWidth = 5;
    if (mediumFlakes.isNotEmpty) {
      canvas.drawPoints(PointMode.points, mediumFlakes, paint);
    }
    paint.strokeWidth = 8;
    if (largeFlakes.isNotEmpty) {
      canvas.drawPoints(PointMode.points, largeFlakes, paint);
    }
  }

  void _drawStars(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (final flake in snowflakes) {
      canvas.save();
      canvas.translate(flake.x * size.width, flake.y * size.height);
      canvas.rotate(flake.rotation);
      canvas.scale(flake.radius * 1.5);
      canvas.drawPath(_starPath, paint);
      canvas.restore();
    }
  }

  void _drawMixed(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.fill;

    final circleFlakes = <_Snowflake>[];
    final starFlakes = <_Snowflake>[];

    for (final flake in snowflakes) {
      if (flake.isStar) {
        starFlakes.add(flake);
      } else {
        circleFlakes.add(flake);
      }
    }

    final smallFlakes = <Offset>[];
    final mediumFlakes = <Offset>[];
    final largeFlakes = <Offset>[];

    for (final flake in circleFlakes) {
      final offset = Offset(flake.x * size.width, flake.y * size.height);
      if (flake.radius < 2) {
        smallFlakes.add(offset);
      } else if (flake.radius < 3) {
        mediumFlakes.add(offset);
      } else {
        largeFlakes.add(offset);
      }
    }

    paint.strokeWidth = 3;
    if (smallFlakes.isNotEmpty) {
      canvas.drawPoints(PointMode.points, smallFlakes, paint);
    }
    paint.strokeWidth = 5;
    if (mediumFlakes.isNotEmpty) {
      canvas.drawPoints(PointMode.points, mediumFlakes, paint);
    }
    paint.strokeWidth = 8;
    if (largeFlakes.isNotEmpty) {
      canvas.drawPoints(PointMode.points, largeFlakes, paint);
    }

    for (final flake in starFlakes) {
      canvas.save();
      canvas.translate(flake.x * size.width, flake.y * size.height);
      canvas.rotate(flake.rotation);
      canvas.scale(flake.radius * 1.5);
      canvas.drawPath(_starPath, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _SnowPainter oldDelegate) => false;
}

class SnowFallOverlay extends StatefulWidget {
  final int snowflakeCount;

  final SnowflakeStyle style;

  final Color? color;

  final double opacity;

  final double speedMultiplier;

  const SnowFallOverlay({
    super.key,
    this.snowflakeCount = 80,
    this.style = SnowflakeStyle.circles,
    this.color,
    this.opacity = 0.7,
    this.speedMultiplier = 1.0,
  });

  @override
  State<SnowFallOverlay> createState() => _SnowFallOverlayState();
}

class _SnowFallOverlayState extends State<SnowFallOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_Snowflake> _snowflakes;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _snowflakes = List.generate(
      widget.snowflakeCount,
      (_) => _Snowflake.random(_random, widget.style),
    );

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SnowFallOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snowflakeCount != widget.snowflakeCount ||
        oldWidget.style != widget.style) {
      _snowflakes = List.generate(
        widget.snowflakeCount,
        (_) => _Snowflake.random(_random, widget.style),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.color ?? Colors.white;
    final snowColor = baseColor.withValues(alpha: widget.opacity);

    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          isComplex: true,
          willChange: true,
          painter: _SnowPainter(
            snowflakes: _snowflakes,
            style: widget.style,
            color: snowColor,
            time: _controller.value * 2 * pi,
            baseSpeed: widget.speedMultiplier,
            repaint: _controller,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class FadingSnowOverlay extends StatefulWidget {
  final ValueNotifier<double> pullOffsetNotifier;

  const FadingSnowOverlay({super.key, required this.pullOffsetNotifier});

  @override
  State<FadingSnowOverlay> createState() => _FadingSnowOverlayState();
}

class _FadingSnowOverlayState extends State<FadingSnowOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _isVisible = false;
  bool _wasPulling = false;
  bool _isFadingOut = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    widget.pullOffsetNotifier.addListener(_onPullOffsetChanged);
  }

  @override
  void dispose() {
    widget.pullOffsetNotifier.removeListener(_onPullOffsetChanged);
    _fadeController.dispose();
    super.dispose();
  }

  void _onPullOffsetChanged() {
    final isPulling = widget.pullOffsetNotifier.value > 0;

    if (isPulling && !_isVisible) {
      _isFadingOut = false;
      _fadeController.stop();
      setState(() {
        _isVisible = true;
      });
      _fadeController.duration = const Duration(milliseconds: 200);
      _fadeController.forward();
    } else if (!isPulling && _wasPulling && _isVisible && !_isFadingOut) {
      _isFadingOut = true;
      _fadeController.duration = const Duration(milliseconds: 1000);
      _fadeController.reverse().then((_) {
        if (mounted) {
          setState(() {
            _isVisible = false;
            _isFadingOut = false;
          });
        }
      });
    }

    _wasPulling = isPulling;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) {
      return const SizedBox.shrink();
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: const SnowFallOverlay(
        snowflakeCount: 50,
        style: SnowflakeStyle.mixed,
        opacity: 0.8,
        speedMultiplier: 0.6,
      ),
    );
  }
}
