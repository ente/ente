import "dart:async";
import "dart:math";
import "dart:ui" show lerpDouble;

import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_page_scope.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_motion.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_buttons.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_rive.dart";
import "package:photos/ui/rewind/widgets/rewind_splat.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

class CoverPage extends RewindPage {
  const CoverPage();

  static const _lockup = Rect.fromLTWH(14, 87, 354, 316);
  static const _camera = Rect.fromLTWH(251.7, 100.3, 63, 67);
  static const _ducky = Rect.fromLTWH(68.4, 381, 262.7, 269);
  static const _tagline = Rect.fromLTWH(23.75, 669, 344.5, 24);
  static const _button = Offset(252, 755);

  @override
  String get key => "cover";

  @override
  Duration? get reelHold =>
      const Duration(milliseconds: 2600 + RewindMotion.reelReadingMs);

  @override
  RewindChrome get chrome => const RewindChrome(foreground: RewindColors.cream);

  @override
  Future<bool> warmUp() async {
    await Future.wait([
      _FlyingLockupState.warmUp(),
      _imageLoaded(FileImage(RewindAssets.file(RewindAssets.cameraSticker))),
    ]);
    return true;
  }

  static Future<void> _imageLoaded(ImageProvider provider) {
    final loaded = Completer<void>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    void done() {
      if (!loaded.isCompleted) loaded.complete();
      stream.removeListener(listener);
    }

    listener = ImageStreamListener((image, _) {
      image.dispose();
      done();
    }, onError: (_, _) => done());
    stream.addListener(listener);
    return loaded.future;
  }

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    Widget layer(Rect rect, Widget child) => Positioned.fromRect(
      rect: rect,
      child: RewindLeave(
        position: position,
        centerY: rect.center.dy,
        child: child,
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: RewindPageScope.navigatorOf(context)?.next,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RewindBackdrop(
            color: RewindColors.green,
            doodle: RewindColors.doodleGreen,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.58, 1],
                colors: [Color(0x0008C225), RewindColors.green],
              ),
            ),
          ),
          RewindSplat(active: isActive, finalColor: RewindColors.green),
          RewindStage(
            children: [
              layer(
                _lockup,
                _FlyingLockup(
                  active: isActive,
                  from: RewindStage.size.center(Offset.zero) - _lockup.center,
                ),
              ),
              layer(
                _camera,
                RewindEntrance(
                  preset: RewindPreset.pop,
                  active: isActive,
                  delayMs: 1250,
                  child: Image.file(
                    RewindAssets.file(RewindAssets.cameraSticker),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              layer(
                _ducky,
                RewindEntrance(
                  preset: RewindPreset.hop,
                  active: isActive,
                  delayMs: 683,
                  child: const RewindDucky(RewindAssets.introDucky),
                ),
              ),
              layer(
                _tagline,
                RewindEntrance(
                  preset: RewindPreset.pop,
                  active: isActive,
                  delayMs: 1500,
                  child: RewindFitWidth(
                    width: _tagline.width,
                    alignment: Alignment.center,
                    child: RewindVoice(
                      you: "YOUR YEAR IN PHOTOS",
                      me: "MY YEAR IN PHOTOS",
                      builder: (text) => Text(
                        text,
                        style: RewindTextStyles.display(
                          23.96,
                          color: RewindColors.white,
                          height: 0.84,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (!RewindPageScope.reelOf(context))
                layer(
                  Rect.fromCenter(center: _button, width: 320, height: 120),
                  Center(
                    child: RewindEntrance(
                      preset: RewindPreset.pop,
                      active: isActive,
                      delayMs: 1750,
                      child: RewindIdleLoop(
                        idle: RewindIdle.pulse,
                        active: isActive,
                        delayMs: 2700,
                        child: Transform.rotate(
                          angle: -3.7 * pi / 180,
                          child: RewindCandyButton(
                            label: "Tap to start",
                            onTap: () =>
                                RewindPageScope.navigatorOf(context)?.next(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FlyingLockup extends StatefulWidget {
  const _FlyingLockup({required this.active, required this.from});

  final bool active;
  final Offset from;

  @override
  State<_FlyingLockup> createState() => _FlyingLockupState();
}

class _FlyingLockupState extends State<_FlyingLockup>
    with TickerProviderStateMixin {
  static const _delayMs = 120;
  static const _shineDelayMs = 2000;

  static const List<_Piece> _pieces = [
    (
      name: "ente",
      rect: Rect.fromLTWH(19.92, -6.4, 129.0, 71.0),
      at: 240,
      kind: _Kind.fly,
      outline: false,
    ),
    (
      name: "R",
      rect: Rect.fromLTWH(-4.67, 23.7, 131.0, 152.0),
      at: 315,
      kind: _Kind.fly,
      outline: true,
    ),
    (
      name: "E",
      rect: Rect.fromLTWH(62.72, 23.7, 125.0, 154.0),
      at: 390,
      kind: _Kind.fly,
      outline: true,
    ),
    (
      name: "W",
      rect: Rect.fromLTWH(-8.94, 123.82, 184.0, 147.0),
      at: 465,
      kind: _Kind.fly,
      outline: true,
    ),
    (
      name: "I",
      rect: Rect.fromLTWH(111.12, 121.93, 95.0, 153.0),
      at: 540,
      kind: _Kind.fly,
      outline: true,
    ),
    (
      name: "N",
      rect: Rect.fromLTWH(146.24, 119.55, 142.0, 154.0),
      at: 615,
      kind: _Kind.fly,
      outline: true,
    ),
    (
      name: "D",
      rect: Rect.fromLTWH(226.43, 117.65, 132.0, 154.0),
      at: 690,
      kind: _Kind.fly,
      outline: true,
    ),
    (
      name: "tag",
      rect: Rect.fromLTWH(136.25, 33.6, 196.0, 140.0),
      at: 430,
      kind: _Kind.fly,
      outline: true,
    ),
    (
      name: "sparkleL",
      rect: Rect.fromLTWH(7.12, 239.13, 57.0, 57.0),
      at: 1150,
      kind: _Kind.twinkle,
      outline: false,
    ),
    (
      name: "sparkleR",
      rect: Rect.fromLTWH(297.41, 23.41, 38.0, 38.0),
      at: 1250,
      kind: _Kind.twinkle,
      outline: false,
    ),
  ];

  static final _lastMs = _pieces
      .map((piece) => piece.at + piece.kind.ms)
      .reduce(max);

  static final _layerNames = [
    for (final piece in _pieces)
      if (piece.outline) (piece: piece, name: "${piece.name}-outline"),
    for (final piece in _pieces) (piece: piece, name: piece.name),
  ];

  static Future<void> warmUp() => Future.wait([
    for (final layer in _layerNames)
      _loader(layer.name).loadBytes(null).then<void>((_) {}, onError: (_) {}),
  ]);

  late final _layers = [
    for (final (:piece, :name) in _layerNames)
      (piece: piece, image: _svg(name)),
  ];

  late final _flight = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _delayMs + _lastMs),
  );
  late final _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4000),
  );
  late final _shineWait = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _shineDelayMs),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(_FlyingLockup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && _flight.isDismissed) _start();
  }

  void _start() {
    _flight.forward();
    _shineWait.forward().whenCompleteOrCancel(() {
      if (mounted) _shine.repeat();
    });
  }

  @override
  void dispose() {
    _flight.dispose();
    _shine.dispose();
    _shineWait.dispose();
    super.dispose();
  }

  Matrix4 _pose(double t, Offset from) {
    const at = [0.0, 0.42, 0.64, 0.82, 1.0];
    const move = [1.0, -0.12, 0.035, 0.0, 0.0];
    const sx = [0.4, 1.16, 0.96, 1.02, 1.0];
    const sy = [0.4, 0.88, 1.05, 0.985, 1.0];
    const turn = [8.0, -2.4, 0.8, 0.0, 0.0];
    final m = _smooth(at, move, t);
    return Matrix4.identity()
      ..translateByDouble(from.dx * m, from.dy * m, 0, 1)
      ..rotateZ(_smooth(at, turn, t) * pi / 180)
      ..scaleByDouble(_smooth(at, sx, t), _smooth(at, sy, t), 1, 1);
  }

  static double _smooth(List<double> at, List<double> v, double t) {
    if (t <= 0) return v.first;
    if (t >= 1) return v.last;
    var i = 0;
    while (i < at.length - 2 && t > at[i + 1]) {
      i++;
    }
    double slope(int k) {
      if (k == 0 || k == at.length - 1) return 0;
      return (v[k + 1] - v[k - 1]) / (at[k + 1] - at[k - 1]);
    }

    final h = at[i + 1] - at[i];
    final u = (t - at[i]) / h;
    final u2 = u * u, u3 = u2 * u;
    return (2 * u3 - 3 * u2 + 1) * v[i] +
        (u3 - 2 * u2 + u) * h * slope(i) +
        (-2 * u3 + 3 * u2) * v[i + 1] +
        (u3 - u2) * h * slope(i + 1);
  }

  static final _loaders = <String, SvgFileLoader>{};

  static SvgFileLoader _loader(String name) {
    final file = RewindAssets.file(RewindAssets.lockupPiece(name));
    return _loaders.putIfAbsent(file.path, () => SvgFileLoader(file));
  }

  static Widget _svg(String name) =>
      SvgPicture(_loader(name), fit: BoxFit.fill);

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Opacity(
        opacity: widget.active ? 1 : 0,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final (:piece, :image) in _layers)
              Positioned.fromRect(rect: piece.rect, child: image),
          ],
        ),
      );
    }
    return AnimatedBuilder(
      animation: Listenable.merge([_flight, _shine]),
      builder: (context, _) {
        final elapsed = _flight.value * (_delayMs + _lastMs) - _delayMs;
        final lockup = Stack(
          clipBehavior: Clip.none,
          children: [
            for (final (:piece, :image) in _layers)
              Positioned.fromRect(
                rect: piece.rect,
                child: _posed(piece, elapsed - piece.at, image),
              ),
          ],
        );
        return _shine.isAnimating ? _shined(lockup) : lockup;
      },
    );
  }

  Widget _posed(_Piece piece, double since, Widget child) {
    if (since <= 0) return Opacity(opacity: 0, child: child);
    if (since >= piece.kind.ms) return child;
    final t = since / piece.kind.ms;
    switch (piece.kind) {
      case _Kind.twinkle:
        final grow = RewindMotion.pop.transform(t);
        return Transform.rotate(
          angle: (1 - grow) * pi / 3,
          child: Transform.scale(scale: grow, child: child),
        );
      case _Kind.fly:
        final from =
            widget.from +
            CoverPage._lockup.size.center(Offset.zero) -
            piece.rect.center;
        return Opacity(
          opacity: (since / 70).clamp(0.0, 1.0),
          child: Transform(
            transform: _pose(t, from),
            alignment: Alignment.center,
            child: child,
          ),
        );
    }
  }

  Widget _shined(Widget child) {
    final sweep = _shine.value / 0.23;
    if (sweep >= 1) return child;
    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (bounds) {
        final direction = Offset(sin(115 * pi / 180), -cos(115 * pi / 180));
        final center = Offset(
          lerpDouble(-1.1, 2.1, sweep)! * bounds.width,
          bounds.height / 2,
        );
        final half = direction * bounds.width * 0.25;
        Alignment at(Offset point) => Alignment(
          point.dx / bounds.width * 2 - 1,
          point.dy / bounds.height * 2 - 1,
        );
        return LinearGradient(
          begin: at(center - half),
          end: at(center + half),
          colors: const [
            Color(0x00FFFFFF),
            Color(0xBFFFFFFF),
            Color(0x00FFFFFF),
          ],
        ).createShader(Offset.zero & bounds.size);
      },
      child: child,
    );
  }
}

typedef _Piece = ({String name, Rect rect, int at, _Kind kind, bool outline});

enum _Kind {
  fly(1150),
  twinkle(879);

  const _Kind(this.ms);

  final int ms;
}
