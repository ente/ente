import "dart:math";

import "package:flutter/widgets.dart";
import "package:photos/services/rewind/rewind_asset_store.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/widgets/rewind_svg.dart";

const _background = Color(0xFF0C0C0C);
const _edge = Color(0xFFFFF3DA);
const _pop = 0.25;
const _exit = 0.30;
const _burst = Offset(180, 308.333);
const _stickerWidth = 63.333;

double _progress(double t, double start, double length) =>
    ((t - start) / length).clamp(0.0, 1.0);

double _outBack(double x, double c) {
  final y = x - 1;
  return 1 + (c + 1) * y * y * y + c * y * y;
}

double _outQuint(double x) => 1 - pow(1 - x, 5).toDouble();

double _seconds(Duration elapsed) =>
    elapsed.inMicroseconds / Duration.microsecondsPerSecond;

double _radians(double degrees) => degrees * pi / 180;

class RewindCardExit extends StatelessWidget {
  const RewindCardExit({required this.elapsed, required this.child, super.key});

  final Duration elapsed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final x = _progress(_seconds(elapsed), 0, _exit);
    final k = min(1.0, x * 1.6);
    final scale = cos(x * pi / 2);
    final screen = max(scale, 0.02);
    final radius = 11.333 * k / screen;
    final edge = 3 * k / screen;
    return Opacity(
      opacity: scale < 0.004 ? 0 : 1,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.translationValues(0, -11.667 * k, 0)
          ..rotateZ(_radians(-18 * x * x))
          ..scaleByDouble(scale, scale, 1, 1),
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -edge,
              top: -edge,
              right: -edge,
              bottom: -edge,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: k > 0 ? _edge : const Color(0x00000000),
                  borderRadius: BorderRadius.circular(radius + edge),
                ),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              clipBehavior: k > 0 ? Clip.antiAlias : Clip.none,
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class RewindEndCard extends StatelessWidget {
  const RewindEndCard({required this.elapsed, super.key});

  static const duration = Duration(milliseconds: 3400);

  final Duration elapsed;

  static const _tagline = TextStyle(
    inherit: false,
    fontFamily: RewindAssetStore.figtree,
    fontWeight: FontWeight.w700,
    fontSize: 21.333,
    height: 1.2,
    letterSpacing: -0.64,
    color: Color(0xFF8F8F8F),
    leadingDistribution: TextLeadingDistribution.even,
  );

  @override
  Widget build(BuildContext context) {
    final t = _seconds(elapsed);
    final rays = _progress(t, _pop - 0.02, 0.55);
    final tagline = _progress(t, _pop + 0.22, 0.35);
    final logo = _progress(t, _pop + 0.03, 0.42);
    final logoScale = 0.5 + 0.5 * _outBack(logo, 1.6);
    final raysScale = 0.1 + 0.9 * _outQuint(rays);
    return ColoredBox(
      color: _background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fromRect(
            rect: Rect.fromCenter(
              center: const Offset(180, 308.667),
              width: 2215.333,
              height: 2215.333,
            ),
            child: Opacity(
              opacity: min(1.0, rays * 2) * 0.32,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.diagonal3Values(raysScale, raysScale, 1)
                  ..rotateZ(_radians((t - _pop) * 3)),
                child: const RewindSvg(
                  RewindAssets.endCardRays,
                  fit: BoxFit.fill,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 267.333,
            child: Opacity(
              opacity: tagline,
              child: Transform.translate(
                offset: Offset(0, 7.333 * (1 - _outQuint(tagline))),
                child: const Text(
                  "Look back at\nyour year with",
                  textAlign: TextAlign.center,
                  style: _tagline,
                ),
              ),
            ),
          ),
          Positioned(
            left: 100,
            top: 327.333,
            width: 160,
            height: 24.253,
            child: Opacity(
              opacity: min(1.0, logo * 3),
              child: Transform.scale(
                scale: logoScale,
                child: const RewindSvg(RewindAssets.endCardLogo),
              ),
            ),
          ),
          for (var i = 0; i < _stickers.length; i++) _stickers[i].build(t, i),
          Positioned.fill(child: CustomPaint(painter: _ImpactLines(t))),
        ],
      ),
    );
  }
}

class _Sticker {
  const _Sticker(this.name, this.rest, this.turn, this.scale, this.size);

  final String name;
  final Offset rest;
  final double turn;
  final double scale;
  final Size size;

  double startOf(int i) => _pop + 0.012 * i;

  double landingOf(int i) => startOf(i) + 0.26;

  Widget build(double t, int i) {
    final q = _progress(t, startOf(i), 0.45);
    var position = _burst + (rest - _burst) * _outBack(q, 1.6);
    final settled = _outQuint(q);
    final grow = 0.2 + (scale - 0.2) * settled;
    var spin = turn + (1 - settled) * (i.isOdd ? -70 : 70);
    final landed = t - landingOf(i);
    final slap = landed > 0 ? exp(-7 * landed) * sin(28 * landed) : 0.0;
    var scaleX = 1 + 0.22 * slap;
    var scaleY = 1 - 0.22 * slap;
    final u = t - (_pop + 0.75);
    if (u > 0) {
      switch (i) {
        case 1:
          position += Offset(10 * sin(2.4 * u), -8 * sin(2.4 * u + 1)) / 3;
          spin += 4 * sin(2.4 * u);
        case 2:
          scaleY *= 1 + 0.05 * sin(11 * u) + 0.03 * sin(17 * u);
          scaleX *= 1 - 0.025 * sin(11 * u);
          spin += 2 * sin(7 * u);
        case 3:
          final twinkle = 1 + 0.14 * max(0.0, sin(4 * u));
          scaleX *= twinkle;
          scaleY *= twinkle;
          spin += 5 * sin(2 * u);
        case 4:
          spin += 6 * sin(6 * u) * max(0.0, sin(1.6 * u));
        case 5:
          final bounce = sin(3.2 * u).abs();
          position -= Offset(0, 14 * bounce / 3);
          scaleY *= 1 - 0.06 * (1 - bounce);
          scaleX *= 1 + 0.06 * (1 - bounce);
      }
    }
    return Positioned(
      left: position.dx - _stickerWidth / 2,
      top: position.dy - _stickerWidth / 2,
      width: _stickerWidth,
      height: _stickerWidth * size.height / size.width,
      child: Opacity(
        opacity: t >= _pop ? 1 : 0,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.rotationZ(_radians(spin))
            ..scaleByDouble(grow * scaleX, grow * scaleY, 1, 1),
          child: RewindSvg(RewindAssets.endCardSticker(name), fit: BoxFit.fill),
        ),
      ),
    );
  }
}

const _stickers = [
  _Sticker("camera", Offset(71.667, 191.667), -14, 1.15, Size(280, 299)),
  _Sticker("star", Offset(205, 136.667), 8, 0.88, Size(380, 269)),
  _Sticker("fire", Offset(291.667, 216.667), 12, 1.05, Size(207, 271)),
  _Sticker("sparkles", Offset(53.333, 430), 10, 0.85, Size(232, 237)),
  _Sticker("wow", Offset(158.333, 476.667), -8, 1.2, Size(280, 285)),
  _Sticker("hundred", Offset(288.333, 411.667), -10, 0.95, Size(267, 245)),
];

class _ImpactLines extends CustomPainter {
  _ImpactLines(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < _stickers.length; i++) {
      final q = _progress(t, _stickers[i].landingOf(i), 0.32);
      if (q <= 0 || q >= 1) continue;
      final paint = Paint()
        ..color = _edge.withValues(alpha: 1 - q * q)
        ..strokeWidth = (7 * (1 - q) + 1) / 3
        ..strokeCap = StrokeCap.round;
      final inner = (88 + 46 * q) / 3;
      final outer = inner + (28 * (1 - q) + 6) / 3;
      for (var r = 0; r < 5; r++) {
        final a = r / 5 * 2 * pi + i;
        final direction = Offset(cos(a), sin(a));
        canvas.drawLine(
          _stickers[i].rest + direction * inner,
          _stickers[i].rest + direction * outer,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ImpactLines oldDelegate) => oldDelegate.t != t;
}
