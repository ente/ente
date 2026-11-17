import "dart:math";
import "dart:ui" as ui;

import "package:flutter/material.dart";
import "package:flutter/scheduler.dart";
import "package:flutter/services.dart";
import "package:photos/models/file/file.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/ui/rewind/pages/finale/finale_actions.dart";
import "package:photos/ui/rewind/pages/finale/finale_video_tile.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_photo.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";

const _skyTop = Color(0xFF0B1240);
const _skyBottom = Color(0xFF2A3A8F);
const _hills = Color(0xFF0A0F33);
const _sparkColors = [
  RewindColors.yellow,
  RewindColors.hotPink,
  Color(0xFF7CF0FF),
  RewindColors.cream,
  Color(0xFF9DFF7A),
];

const _flipAtMs = 1300.0;
const _flipMs = 520.0;
const _climbMs = 640.0;
const _burstMs = 1900.0;
const _photosPerBurst = 8;
const _ground = 600.0;
const _sky = Rect.fromLTRB(20, 250, 370, 520);
const _autoLaunches = [
  (1650.0, Offset(66, 330)),
  (2250.0, Offset(324, 296)),
  (2900.0, Offset(72, 462)),
  (3500.0, Offset(318, 444)),
];
const _idleEveryMs = 3600.0;
const _freshMs = 120.0;
const _actionsDelayMs = 700;
const _tapArea = Rect.fromLTRB(0, 240, 390, 590);

class FireworksFinale extends StatefulWidget {
  const FireworksFinale({
    required this.photos,
    required this.active,
    super.key,
  });

  final List<EnteFile> photos;
  final bool active;

  @override
  State<FireworksFinale> createState() => _FireworksFinaleState();
}

class _Rocket {
  _Rocket(
    this.launchMs,
    this.target,
    this.firstPhoto,
    this.seed, {
    required this.felt,
  });

  final double launchMs;
  final Offset target;
  final int firstPhoto;
  final int seed;
  final bool felt;

  late final _sparks = _scatterSparks(Random(seed));

  double get burstMs => launchMs + _climbMs;

  bool doneAt(double ms) => ms > burstMs + _burstMs;
}

class _Spark {
  const _Spark(this.angle, this.speed, this.color, this.size);

  final double angle;
  final double speed;
  final Color color;
  final double size;
}

List<_Spark> _scatterSparks(Random random) => [
  for (var i = 0; i < 34; i++)
    _Spark(
      random.nextDouble() * 2 * pi,
      70 + random.nextDouble() * 70,
      _sparkColors[random.nextInt(_sparkColors.length)],
      1.6 + random.nextDouble() * 1.8,
    ),
];

class _FireworksFinaleState extends State<FireworksFinale>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  late final _stars = _scatterStars(Random(27));
  final _rockets = <_Rocket>[];
  final _burst = <_Rocket>{};
  var _ms = 0.0;
  var _banked = Duration.zero;
  var _since = Duration.zero;
  var _nextPhoto = 0;
  var _seed = 1;
  var _launched = 0;
  var _lastIdle = 0.0;
  var _flipped = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(FireworksFinale oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final run = widget.active && !MediaQuery.disableAnimationsOf(context);
    if (run && !_ticker.isActive) {
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _banked = _since;
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    _since = _banked + elapsed;
    final ms = _since.inMicroseconds / 1000;
    if (!_flipped && ms >= _flipAtMs + _flipMs / 2) {
      _flipped = true;
      if (ms < _flipAtMs + _flipMs) HapticFeedback.mediumImpact().ignore();
    }
    while (_launched < _autoLaunches.length &&
        ms >= _autoLaunches[_launched].$1) {
      final (at, target) = _autoLaunches[_launched++];
      if (ms < at + _climbMs + _burstMs) _launch(target, at: at);
    }
    if (_launched == _autoLaunches.length &&
        ms - max(_lastIdle, _autoLaunches.last.$1) > _idleEveryMs &&
        _rockets.isEmpty) {
      _lastIdle = ms;
      final random = Random(_seed);
      final x = 30 + random.nextDouble() * 70;
      _launch(
        Offset(
          random.nextBool() ? x : 390 - x,
          _sky.top + 20 + random.nextDouble() * (_sky.height * 0.7),
        ),
        at: ms,
        felt: false,
      );
    }
    for (final rocket in _rockets) {
      if (ms >= rocket.burstMs &&
          _burst.add(rocket) &&
          rocket.felt &&
          ms - rocket.burstMs < _freshMs) {
        HapticFeedback.lightImpact().ignore();
      }
    }
    _rockets.removeWhere((rocket) => rocket.doneAt(ms));
    _burst.removeWhere((rocket) => rocket.doneAt(ms));
    setState(() => _ms = ms);
  }

  void _launch(Offset target, {required double at, bool felt = true}) {
    _rockets.add(_Rocket(at, target, _nextPhoto, _seed++, felt: felt));
    _nextPhoto += _photosPerBurst;
  }

  void _tapSky(TapUpDetails details) {
    final tap = details.localPosition + _tapArea.topLeft;
    final target = Offset(
      tap.dx.clamp(_sky.left, _sky.right),
      tap.dy.clamp(_sky.top - 40, _sky.bottom),
    );
    HapticFeedback.selectionClick().ignore();
    _launch(target, at: _ms);
    _lastIdle = _ms;
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final photos = widget.photos;
    return Stack(
      fit: StackFit.expand,
      children: [
        Semantics(
          label: "See you in ${RewindEdition.year + 1}",
          child: ExcludeSemantics(
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [_skyTop, _skyBottom],
                    ),
                  ),
                ),
                RewindStage(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _SkyPainter(
                            stars: _stars,
                            rockets: still ? const [] : _rockets,
                            ms: _ms,
                          ),
                        ),
                      ),
                    ),
                    if (!still)
                      for (final rocket in _burst)
                        for (
                          var i = 0;
                          i < _photosPerBurst && photos.isNotEmpty;
                          i++
                        )
                          _photoSpark(rocket, i, photos),
                    if (!still)
                      Positioned.fromRect(
                        rect: _tapArea,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: _tapSky,
                        ),
                      ),
                    Positioned(
                      left: 15,
                      top: 86,
                      width: 360,
                      child: IgnorePointer(
                        child: RewindEntrance(
                          preset: RewindPreset.line,
                          active: widget.active,
                          delayMs: 120,
                          child: Text(
                            "SEE YOU IN",
                            textAlign: TextAlign.center,
                            style: RewindTextStyles.display(
                              36,
                              color: RewindColors.cream,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 130,
                      child: IgnorePointer(
                        child: RewindEntrance(
                          preset: RewindPreset.pop,
                          active: widget.active,
                          delayMs: 280,
                          child: _FlipCounter(
                            progress: still
                                ? 1
                                : ((_ms - _flipAtMs) / _flipMs).clamp(0.0, 1.0),
                          ),
                        ),
                      ),
                    ),
                    const Positioned(
                      left: -60,
                      right: -60,
                      top: 520,
                      height: 500,
                      child: IgnorePointer(
                        child: CustomPaint(painter: _HillsPainter()),
                      ),
                    ),
                    Positioned(
                      left:
                          (RewindStage.size.width -
                              FinaleVideoTile.size.width) /
                          2,
                      top: 250,
                      child: IgnorePointer(
                        child: RewindEntrance(
                          preset: RewindPreset.pop,
                          active: widget.active,
                          delayMs: 420,
                          child: FinaleVideoTile(active: widget.active),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        RewindStage(
          children: [
            Positioned(
              left: 20,
              top: 566,
              width: 350,
              child: IgnorePointer(
                child: RewindEntrance(
                  preset: RewindPreset.line,
                  active: widget.active,
                  delayMs: 600,
                  child: const _ShareLine(),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 606,
              child: Center(
                child: IgnorePointer(
                  ignoring: !widget.active || (!still && _ms < _actionsDelayMs),
                  child: FinaleActions(
                    active: widget.active,
                    delayMs: _actionsDelayMs,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _photoSpark(_Rocket rocket, int i, List<EnteFile> photos) {
    final t = ((_ms - rocket.burstMs) / _burstMs).clamp(0.0, 1.0);
    final jitter = sin(rocket.seed * 12.9898 + i * 78.233);
    final angle =
        -pi / 2 + (i + 0.3 * jitter) * 2 * pi / _photosPerBurst + rocket.seed;
    final reach = (82 + 22 * jitter) * Curves.easeOutCubic.transform(t);
    final fall = 70 * t * t;
    final center =
        rocket.target + Offset(cos(angle) * reach, sin(angle) * reach + fall);
    final size = 34 * (0.4 + 0.6 * Curves.easeOutBack.transform(min(1, t * 3)));
    final fade = t < 0.7 ? 1.0 : 1 - (t - 0.7) / 0.3;
    final photo = photos[(rocket.firstPhoto + i) % photos.length];
    return Positioned(
      key: ValueKey((rocket.seed, i)),
      left: center.dx - size / 2,
      top: center.dy - size / 2,
      width: size,
      height: size,
      child: IgnorePointer(
        child: Opacity(
          opacity: fade.clamp(0.0, 1.0),
          child: Transform.rotate(
            angle: (i.isEven ? 1 : -1) * t * 0.8,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: RewindColors.cream,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Color(0x88FFE9A8), blurRadius: 10),
                ],
              ),
              child: ClipOval(
                child: RewindPhoto(
                  photo,
                  key: ValueKey(photo.tag),
                  zoomable: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static List<(Offset, double, double)> _scatterStars(Random random) => [
    for (var i = 0; i < 70; i++)
      (
        Offset(random.nextDouble() * 390, random.nextDouble() * 560),
        0.6 + random.nextDouble() * 1.4,
        random.nextDouble() * 2 * pi,
      ),
  ];
}

class _SkyPainter extends CustomPainter {
  _SkyPainter({required this.stars, required this.rockets, required this.ms});

  final List<(Offset, double, double)> stars;
  final List<_Rocket> rockets;
  final double ms;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (at, radius, phase) in stars) {
      final twinkle = 0.45 + 0.55 * (0.5 + 0.5 * sin(ms / 520 + phase));
      canvas.drawCircle(
        at,
        radius,
        Paint()..color = RewindColors.cream.withValues(alpha: 0.7 * twinkle),
      );
    }
    for (final rocket in rockets) {
      _paintRocket(canvas, rocket);
    }
  }

  void _paintRocket(Canvas canvas, _Rocket rocket) {
    final climb = ((ms - rocket.launchMs) / _climbMs).clamp(0.0, 1.0);
    final from = Offset(rocket.target.dx + 18, _ground);
    if (climb < 1) {
      final eased = Curves.easeOutCubic.transform(climb);
      final head = Offset.lerp(from, rocket.target, eased)!;
      final tail = Offset.lerp(from, rocket.target, max(0, eased - 0.22))!;
      canvas.drawLine(
        tail,
        head,
        Paint()
          ..shader = ui.Gradient.linear(tail, head, [
            RewindColors.yellow.withValues(alpha: 0),
            RewindColors.yellow,
          ])
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(head, 3.4, Paint()..color = RewindColors.cream);
      return;
    }
    final t = ((ms - rocket.burstMs) / _burstMs).clamp(0.0, 1.0);
    final flash = (1 - t * 5).clamp(0.0, 1.0);
    if (flash > 0) {
      canvas.drawCircle(
        rocket.target,
        46 * (1 - flash) + 12,
        Paint()
          ..color = RewindColors.cream.withValues(alpha: 0.6 * flash)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
    }
    final fade = t < 0.6 ? 1.0 : 1 - (t - 0.6) / 0.4;
    for (final spark in rocket._sparks) {
      final reach = spark.speed * Curves.easeOutCubic.transform(t) * 1.25;
      final fall = 60 * t * t;
      final direction = Offset(cos(spark.angle), sin(spark.angle));
      final head = rocket.target + direction * reach + Offset(0, fall);
      final tail =
          rocket.target +
          direction * max(0.0, reach - 16) +
          Offset(0, fall * 0.8);
      final paint = Paint()
        ..color = spark.color.withValues(alpha: fade.clamp(0.0, 1.0))
        ..strokeWidth = spark.size
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(tail, head, paint);
    }
  }

  @override
  bool shouldRepaint(_SkyPainter oldDelegate) => true;
}

class _HillsPainter extends CustomPainter {
  const _HillsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final back = Path()
      ..moveTo(0, h)
      ..lineTo(0, 60)
      ..quadraticBezierTo(w * 0.18, 20, w * 0.36, 52)
      ..quadraticBezierTo(w * 0.55, 84, w * 0.72, 40)
      ..quadraticBezierTo(w * 0.88, 6, w, 46)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(back, Paint()..color = const Color(0xFF141C55));
    final roofs = Path()..moveTo(0, h);
    var x = 0.0;
    const heights = <double>[70, 56, 84, 62, 92, 66, 78, 58, 88, 64, 74];
    for (final (i, top) in heights.indexed) {
      final width = w / heights.length;
      roofs
        ..lineTo(x, top)
        ..lineTo(x + width * 0.5, top - (i.isEven ? 14 : 0))
        ..lineTo(x + width, top);
      x += width;
    }
    roofs
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(roofs, Paint()..color = _hills);
    final window = Paint()..color = RewindColors.yellow.withValues(alpha: 0.75);
    final random = Random(5);
    const outer = [0, 1, 2, 8, 9, 10];
    for (var i = 0; i < 22; i++) {
      final column = outer[random.nextInt(outer.length)];
      final left = column * w / heights.length + 6 + random.nextDouble() * 14;
      final top = heights[column] + 12 + random.nextDouble() * 40;
      canvas.drawRect(Rect.fromLTWH(left, top, 4, 6), window);
    }
  }

  @override
  bool shouldRepaint(_HillsPainter oldDelegate) => false;
}

class _ShareLine extends StatelessWidget {
  const _ShareLine();

  @override
  Widget build(BuildContext context) {
    final style = RewindTextStyles.body(
      18,
      color: RewindColors.cream,
      weight: FontWeight.w600,
      height: 1.1,
    );
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          const TextSpan(text: "Your "),
          TextSpan(
            text: "whole Rewind",
            style: style.copyWith(
              color: RewindColors.yellow,
              fontWeight: FontWeight.w800,
            ),
          ),
          const TextSpan(text: ", in one video."),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _FlipCounter extends StatelessWidget {
  const _FlipCounter({required this.progress});

  static const _from = "${RewindEdition.year}";
  static const _to = "${RewindEdition.year + 1}";

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < _to.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          _FlipTile(
            from: _from[i],
            to: _to[i],
            progress: _from[i] == _to[i] ? 0 : progress,
          ),
        ],
      ],
    );
  }
}

class _FlipTile extends StatelessWidget {
  const _FlipTile({
    required this.from,
    required this.to,
    required this.progress,
  });

  static const _size = Size(70, 96);

  final String from;
  final String to;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final first = progress < 0.5;
    final fold = first ? progress * 2 : (progress - 0.5) * 2;
    Widget half(String digit, {required bool top}) => ClipRect(
      child: Align(
        alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
        heightFactor: 0.5,
        child: _face(digit),
      ),
    );
    return SizedBox.fromSize(
      size: _size,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: RewindColors.ink,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Color(0xAA000000), offset: Offset(0, 6)),
                ],
              ),
            ),
          ),
          Column(children: [half(to, top: true), half(from, top: false)]),
          if (progress > 0 && progress < 1)
            Positioned.fill(
              child: Column(
                children: [
                  if (first)
                    Transform(
                      alignment: Alignment.bottomCenter,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.004)
                        ..rotateX(-fold * pi / 2),
                      child: half(from, top: true),
                    )
                  else
                    SizedBox(height: _size.height / 2),
                  if (!first)
                    Transform(
                      alignment: Alignment.topCenter,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.004)
                        ..rotateX((1 - fold) * pi / 2),
                      child: half(to, top: false),
                    ),
                ],
              ),
            )
          else
            Column(
              children: [
                half(progress >= 1 ? to : from, top: true),
                half(progress >= 1 ? to : from, top: false),
              ],
            ),
          Positioned(
            left: 0,
            right: 0,
            top: _size.height / 2 - 1,
            child: Container(height: 2, color: RewindColors.ink),
          ),
        ],
      ),
    );
  }

  Widget _face(String digit) => Container(
    width: _size.width,
    height: _size.height,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: RewindColors.cream,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: RewindColors.ink, width: 3),
    ),
    child: Text(
      digit,
      style: RewindTextStyles.display(76, color: RewindColors.ink, height: 1),
    ),
  );
}
