import "dart:math";
import "dart:ui" as ui;

import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_page_scope.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_elapsed.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_hint.dart";
import "package:photos/ui/rewind/widgets/rewind_numbers.dart";
import "package:photos/ui/rewind/widgets/rewind_pixels.dart";
import "package:photos/ui/rewind/widgets/rewind_reveal_layer.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

enum _Sight {
  person("YOU", "your own height", 1.7, -0.34, span: 0.46),
  giraffe("A GIRAFFE", "a giraffe", 5.5, 0.44, span: 0.6, peak: 0.25),
  redeemer("CHRIST THE REDEEMER", "Christ the Redeemer", 38, -0.24),
  taj("TAJ MAHAL", "the Taj Mahal", 73, 0.4),
  liberty(
    "STATUE OF LIBERTY",
    "the Statue of Liberty",
    93,
    -0.3,
    span: 0.38,
    peak: -0.088,
  ),
  pyramid("GREAT PYRAMID", "the Great Pyramid", 139, 0.36),
  eiffel("EIFFEL TOWER", "the Eiffel Tower", 330, -0.3, span: 0.38),
  empire(
    "EMPIRE STATE BUILDING",
    "the Empire State Building",
    443,
    0.3,
    span: 0.29,
  ),
  burj("BURJ KHALIFA", "the Burj Khalifa", 828, -0.3, span: 0.18),
  table("TABLE MOUNTAIN", "Table Mountain", 1086, 0.62),
  fuji("MOUNT FUJI", "Mount Fuji", 3776, -0.42),
  matterhorn("MATTERHORN", "the Matterhorn", 4478, 0.4, peak: -0.05),
  everest("MOUNT EVEREST", "Mount Everest", 8849, -0.38);

  const _Sight(
    this.label,
    this.phrase,
    this.metres,
    this.aside, {
    this.span,
    this.peak = 0,
  });

  final String label;
  final String phrase;
  final double metres;
  final double aside;
  final double? span;
  final double peak;

  bool get behind => span == null;

  double get looming => switch (span) {
    final span? => (190 / span).clamp(520.0, 760.0),
    null => 620,
  };

  double get inFull => min(looming * 0.72, 445);

  double offset(double tall) {
    final reach = behind ? 150.0 : 120.0;
    return (aside * tall).clamp(-reach, reach);
  }
}

String _height(double metres) => metres < 1
    ? "${metres.toStringAsFixed(2)} M"
    : metres < 10
    ? "${metres.toStringAsFixed(1)} M"
    : metres < 1000
    ? "${metres.round()} M"
    : metres < 10000
    ? "${(metres / 1000).toStringAsFixed(2)} KM"
    : "${(metres / 1000).toStringAsFixed(1)} KM";

double _smooth(double t) {
  final x = t.clamp(0.0, 1.0);
  return x * x * (3 - 2 * x);
}

class TowerPage extends RewindPage {
  TowerPage({
    required this.prints,
    required this.photos,
    this.bytes = rewindThumbnailBytes,
  });

  static const pageKey = "tower";
  static const minimumPrints = 30;
  static const printMetres = 0.15;
  static const printWidthMetres = 0.1;
  static const tiles = 96;

  final int prints;
  final List<EnteFile> photos;
  final RewindBytes bytes;

  late final RewindWarm<RewindAtlas> _strip = RewindWarm(
    () => RewindAtlas.load(photos, tile: 128, bytes: bytes),
    (atlas) => atlas.dispose(),
  );

  double get _metres => prints * printMetres;

  @override
  String get key => pageKey;

  @override
  Duration? get reelHold => const Duration(milliseconds: 4200);

  @override
  Future<bool> warmUp() async => await _strip.value != null;

  @override
  void release() => _strip.release();

  String _boast({bool firstPerson = false}) {
    String phrase(_Sight sight) =>
        firstPerson && sight == _Sight.person ? "my own height" : sight.phrase;
    final metres = _metres;
    final next = _Sight.values.where((sight) => sight.metres > metres);
    if (next.isNotEmpty && metres >= next.first.metres * 0.85) {
      final more = ((next.first.metres - metres) / printMetres).ceil();
      return "Just ${rewindCount(more)} more to top ${phrase(next.first)}.";
    }
    final passed = _Sight.values.lastWhere(
      (sight) => sight.metres <= metres,
      orElse: () => _Sight.person,
    );
    final times = metres / passed.metres;
    return times >= 1.95
        ? "That’s ${times.toStringAsFixed(1)}× ${phrase(passed)}."
        : "Taller than ${phrase(passed)}.";
  }

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final count = "${rewindCount(prints)} prints at 15 cm each.";
    final body = "$count ${_boast()}";
    return Semantics(
      label:
          "Every photo printed, end to end, is ${_height(_metres)} tall. "
          "$body",
      child: ExcludeSemantics(
        child: _Climb(
          prints: prints,
          metres: _metres,
          body: body,
          myBody: "$count ${_boast(firstPerson: true)}",
          strip: _strip,
          active: isActive,
          position: position,
        ),
      ),
    );
  }
}

class _EagerDragRecognizer extends VerticalDragGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _Climb extends StatefulWidget {
  const _Climb({
    required this.prints,
    required this.metres,
    required this.body,
    required this.myBody,
    required this.strip,
    required this.active,
    required this.position,
  });

  final int prints;
  final double metres;
  final String body;
  final String myBody;
  final RewindWarm<RewindAtlas> strip;
  final bool active;
  final double position;

  @override
  State<_Climb> createState() => _ClimbState();
}

class _ClimbState extends State<_Climb> {
  static const _firstPrints = 3;
  static const _zoomStartMs = 1650.0;
  static const _dragSpan = 300.0;

  late final _reel = RewindPageScope.reelOf(context);
  double? _held;
  var _run = 0;
  var _passed = 0;

  double get _near => _Scene.reach / (_firstPrints * TowerPage.printMetres);

  double get _far => _Scene.reach / widget.metres;

  double get _zoomMs => _reel ? 1900 : 1800 + 1400 * log(_near / _far) / ln10;

  double _zoomed(double ms) => Curves.easeInOutSine.transform(
    ((ms - _zoomStartMs) / _zoomMs).clamp(0.0, 1.0),
  );

  @override
  Widget build(BuildContext context) {
    return RewindWarmBuilder<RewindAtlas>(
      warm: widget.strip,
      builder: (context, strip) => Stack(
        fit: StackFit.expand,
        children: [
          RewindShareable(
            enabled: strip != null,
            child: RewindElapsed(
              key: ValueKey(_run),
              active: widget.active,
              stillMs: 600000,
              builder: (context, ms) => _scene(ms, strip),
            ),
          ),
          RewindHint(
            "DRAG TO ZOOM",
            key: ValueKey(_run),
            centerY: 540,
            active: widget.active,
            position: widget.position,
            delayMs: (_zoomStartMs + _zoomMs + 900).round(),
          ),
        ],
      ),
    );
  }

  Widget _scene(double ms, RewindAtlas? strip) {
    final held = _held;
    final zoom = held ?? _zoomed(ms);
    final stacking = held == null && ms < _zoomStartMs;
    final scale = _near * pow(_far / _near, zoom);
    final metres = stacking
        ? TowerPage.printMetres * _firstPrints
        : min(widget.metres, _Scene.reach / scale);
    final arrived = zoom >= 1;
    final passed = _Sight.values
        .where((sight) => sight.metres <= metres)
        .length;
    if (passed != _passed) {
      if (passed > _passed && !stacking && !_reel) {
        HapticFeedback.selectionClick();
      }
      _passed = passed;
    }
    final shown = stacking ? TowerPage.printMetres * _Scene.landed(ms) : metres;
    return Stack(
      fit: StackFit.expand,
      children: [
        const CustomPaint(painter: _Dusk()),
        RewindStage(
          children: [
            Positioned.fill(
              child: RewindLeave(
                position: widget.position,
                centerY: 380,
                child: RewindVoice(
                  you: _Sight.person.label,
                  me: "ME",
                  builder: (person) => CustomPaint(
                    painter: _Scene(
                      scale: scale,
                      metres: metres,
                      far: _far,
                      strip: strip,
                      stackingMs: stacking ? ms : null,
                      finale: _smooth((zoom - 0.82) / 0.18),
                      prints: (metres / TowerPage.printMetres).round(),
                      person: person,
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: const Rect.fromLTWH(
                _Scene.axis - 42,
                150,
                84,
                _Scene.ground - 150,
              ),
              child: RawGestureDetector(
                behavior: HitTestBehavior.opaque,
                gestures: {
                  _EagerDragRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        _EagerDragRecognizer
                      >(
                        _EagerDragRecognizer.new,
                        (recognizer) =>
                            recognizer
                              ..onUpdate = (details) => setState(
                                () => _held =
                                    ((_held ?? zoom) -
                                            details.primaryDelta! / _dragSpan)
                                        .clamp(0.0, 1.0),
                              ),
                      ),
                },
              ),
            ),
            _rider(ms, metres * scale, stacking),
            RewindRevealLayer(
              left: 28,
              top: 597,
              maxWidth: 334,
              height: 18,
              position: widget.position,
              active: widget.active,
              delayMs: 500,
              child: Text(
                "EVERY PHOTO PRINTED, END TO END",
                style: RewindTextStyles.display(17, height: 1.05),
              ),
            ),
            RewindRevealLayer(
              left: 28,
              top: 622,
              height: 52,
              position: widget.position,
              active: widget.active,
              preset: RewindPreset.slap,
              delayMs: 700,
              origin: Alignment.centerLeft,
              child: RewindFitWidth(
                width: 322,
                child: RewindOutlinedText(
                  "${_height(shown)} TALL",
                  style: RewindTextStyles.display(
                    58,
                    color: RewindColors.yellow,
                    height: 0.84,
                  ),
                  shadow: const Offset(2.2, 2.6),
                ),
              ),
            ),
            Positioned(
              left: 28,
              top: 688,
              width: 334,
              child: RewindLeave(
                position: widget.position,
                centerY: 710,
                child: AnimatedSlide(
                  offset: arrived ? Offset.zero : const Offset(0, 0.3),
                  duration: const Duration(milliseconds: 520),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: arrived ? 1 : 0,
                    duration: const Duration(milliseconds: 320),
                    child: RewindVoice(
                      you: widget.body,
                      me: widget.myBody,
                      builder: (text) =>
                          Text(text, style: RewindTextStyles.body(17)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _rider(double ms, double height, bool stacking) {
    const size = Size(54, 60);
    final hop = Curves.easeInOut.transform(
      ((ms - (_zoomStartMs - 420)) / 380).clamp(0.0, 1.0),
    );
    final perched = _held != null || !stacking ? 1.0 : hop;
    final onTop = Offset(
      _Scene.axis - size.width / 2,
      _Scene.ground - height - size.height + 8,
    );
    final waiting = Offset(_Scene.axis - 118, _Scene.ground - size.height + 4);
    final at =
        Offset.lerp(waiting, onTop, perched)! -
        Offset(0, 46 * sin(pi * perched));
    return Positioned(
      left: at.dx,
      top: at.dy + (stacking ? 0 : 1.5 * sin(ms / 420)),
      width: size.width,
      height: size.height,
      child: RewindLeave(
        position: widget.position,
        centerY: 300,
        child: Opacity(
          opacity: ((ms - 250) / 220).clamp(0.0, 1.0),
          child: GestureDetector(
            onTap: () => setState(() {
              _held = null;
              _passed = 0;
              _run++;
            }),
            child: Image.file(RewindAssets.file(RewindAssets.heroDucky)),
          ),
        ),
      ),
    );
  }
}

class _Dusk extends CustomPainter {
  const _Dusk();

  static const _sky = [
    Color(0xFF3F2DB4),
    Color(0xFF6A3CC8),
    Color(0xFFC24FB0),
    Color(0xFFFF7D6B),
    Color(0xFFFFC766),
  ];
  static const _stops = [0.0, 0.3, 0.58, 0.82, 1.0];
  static const earth = Color(0xFF1B1250);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = RewindStage.scaleFor(size);
    final origin = RewindStage.originFor(size);
    final horizon = origin.dy + _Scene.ground * scale;
    final sky = Rect.fromLTRB(0, 0, size.width, horizon);
    canvas.drawRect(
      sky,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, horizon),
          _sky,
          _stops,
        ),
    );
    canvas.save();
    canvas.clipRect(sky);
    final sun = Offset(origin.dx + 290 * scale, horizon - 22 * scale);
    canvas.drawCircle(
      sun,
      210 * scale,
      Paint()
        ..shader = ui.Gradient.radial(sun, 210 * scale, const [
          Color(0x80FFE9A8),
          Color(0x00FFE9A8),
        ]),
    );
    canvas.drawCircle(
      sun,
      76 * scale,
      Paint()..color = const Color(0xFFFFF0B8),
    );
    final random = Random(7);
    for (var star = 0; star < 22; star++) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * horizon * 0.3,
        ),
        (0.7 + random.nextDouble() * 0.9) * scale,
        Paint()
          ..color = RewindColors.cream.withValues(
            alpha: 0.25 + 0.5 * random.nextDouble(),
          ),
      );
    }
    for (final (left, lift, width, height, color) in const [
      (36.0, 156.0, 176.0, 10.0, Color(0x38FFD9E8)),
      (168.0, 122.0, 190.0, 8.0, Color(0x42FFE2C4)),
      (228.0, 226.0, 150.0, 9.0, Color(0x30E6C8FF)),
      (-20.0, 286.0, 132.0, 9.0, Color(0x2AD9C4FF)),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            origin.dx + left * scale,
            horizon - lift * scale,
            width * scale,
            height * scale,
          ),
          Radius.circular(height * scale),
        ),
        Paint()..color = color,
      );
    }
    canvas.restore();
    canvas.drawRect(
      Rect.fromLTRB(0, horizon, size.width, size.height),
      Paint()..color = earth,
    );
  }

  @override
  bool shouldRepaint(_Dusk oldDelegate) => false;
}

class _Shape {
  const _Shape(this.body, {this.shade, this.snow});

  final Path body;
  final Path? shade;
  final Path? snow;
}

class _Scene extends CustomPainter {
  _Scene({
    required this.scale,
    required this.metres,
    required this.far,
    required this.strip,
    required this.stackingMs,
    required this.finale,
    required this.prints,
    required this.person,
  });

  static const ground = 566.0;
  static const axis = 195.0;
  static const reach = 340.0;
  static const _ribbon = 26.0;
  static const _dropMs = [250.0, 800.0, 1150.0];
  static const _nearTones = [Color(0xFF1B1250), Color(0xFF261A6B)];
  static const _farTones = [Color(0xFF4A2F9C), Color(0xFF5B3BAF)];
  static const _snowTone = Color(0xFFF6D3E4);
  static const _drifts = [1.0, 0.35, 0.8, 0.25, 1.15, 0.5, 0.9, 0.3];

  final double scale;
  final double metres;
  final double far;
  final RewindAtlas? strip;
  final double? stackingMs;
  final double finale;
  final int prints;
  final String person;

  static int landed(double ms) => _dropMs.where((at) => ms >= at + 200).length;

  static final Map<_Sight, _Shape> _shapes = {
    _Sight.person: _Shape(
      _join([
        Path()..addOval(
          Rect.fromCircle(center: const Offset(0, -0.91), radius: 0.085),
        ),
        Path()..addRRect(_bar(-0.125, 0.4, 0.125, 0.8, 0.06)),
        Path()..addRRect(_bar(-0.115, 0, -0.012, 0.46, 0.03)),
        Path()..addRRect(_bar(0.012, 0, 0.115, 0.46, 0.03)),
        Path()..addRRect(_bar(-0.2, 0.45, -0.145, 0.79, 0.027)),
        Path()..addRRect(_bar(0.145, 0.45, 0.2, 0.79, 0.027)),
      ]),
    ),
    _Sight.giraffe: _Shape(
      _join([
        Path()..addOval(
          Rect.fromCenter(
            center: const Offset(-0.03, -0.5),
            width: 0.38,
            height: 0.19,
          ),
        ),
        _outline([0.03, 0.5, 0.15, 0.44, 0.275, 0.88, 0.215, 0.915]),
        _outline([
          0.2,
          0.9,
          0.235,
          0.975,
          0.27,
          0.965,
          0.36,
          0.915,
          0.36,
          0.885,
          0.27,
          0.865,
        ]),
        _outline([0.228, 0.96, 0.24, 0.96, 0.24, 1, 0.228, 1]),
        _outline([0.252, 0.955, 0.263, 0.955, 0.263, 0.995, 0.252, 0.995]),
        _outline([0.21, 0.955, 0.18, 0.975, 0.215, 0.93]),
        _outline([-0.185, 0, -0.16, 0, -0.135, 0.5, -0.195, 0.5]),
        _outline([-0.13, 0, -0.105, 0, -0.085, 0.47, -0.14, 0.47]),
        _outline([0.045, 0, 0.07, 0, 0.09, 0.5, 0.03, 0.5]),
        _outline([0.1, 0, 0.125, 0, 0.14, 0.5, 0.085, 0.5]),
        _outline([
          -0.2,
          0.54,
          -0.185,
          0.55,
          -0.215,
          0.3,
          -0.235,
          0.26,
          -0.24,
          0.3,
        ]),
      ]),
    ),
    _Sight.redeemer: _Shape(
      _join([
        _outline([-0.085, 0, 0.085, 0, 0.085, 0.2, -0.085, 0.2]),
        _outline([-0.08, 0.2, 0.08, 0.2, 0.055, 0.8, -0.055, 0.8]),
        _outline([
          -0.37,
          0.775,
          -0.37,
          0.815,
          -0.06,
          0.875,
          0.06,
          0.875,
          0.37,
          0.815,
          0.37,
          0.775,
          0.07,
          0.76,
          -0.07,
          0.76,
        ]),
        Path()..addOval(
          Rect.fromCenter(
            center: const Offset(0, -0.935),
            width: 0.08,
            height: 0.11,
          ),
        ),
      ]),
    ),
    _Sight.taj: _Shape(_taj()),
    _Sight.liberty: _Shape(
      _join([
        _outline([-0.19, 0, 0.19, 0, 0.17, 0.1, -0.17, 0.1]),
        _outline([
          -0.1,
          0.1,
          0.1,
          0.1,
          0.08,
          0.44,
          0.095,
          0.44,
          0.095,
          0.5,
          -0.095,
          0.5,
          -0.095,
          0.44,
          -0.08,
          0.44,
        ]),
        _outline([
          -0.075,
          0.5,
          0.075,
          0.5,
          0.06,
          0.7,
          0.05,
          0.8,
          -0.045,
          0.8,
          -0.06,
          0.7,
        ]),
        Path()..addOval(
          Rect.fromCircle(center: const Offset(0, -0.835), radius: 0.032),
        ),
        _outline([
          -0.03,
          0.85,
          -0.045,
          0.89,
          -0.018,
          0.865,
          -0.012,
          0.905,
          0,
          0.87,
          0.012,
          0.905,
          0.018,
          0.865,
          0.045,
          0.89,
          0.03,
          0.85,
        ]),
        _outline([-0.045, 0.78, -0.02, 0.8, -0.075, 0.955, -0.1, 0.95]),
        _outline([
          -0.115,
          0.945,
          -0.06,
          0.945,
          -0.07,
          0.965,
          -0.08,
          0.985,
          -0.088,
          1,
          -0.098,
          0.985,
          -0.105,
          0.965,
        ]),
        _outline([0.045, 0.68, 0.095, 0.72, 0.085, 0.775, 0.04, 0.75]),
      ]),
    ),
    _Sight.pyramid: _Shape(
      _outline([-0.83, 0, 0.83, 0, 0, 1]),
      shade: _outline([0, 1, 0.83, 0, 0.3, 0]),
    ),
    _Sight.eiffel: _Shape(_eiffel()),
    _Sight.empire: _Shape(
      _stepped(const [
        (0.145, 0.045),
        (0.115, 0.19),
        (0.088, 0.62),
        (0.068, 0.7),
        (0.048, 0.765),
        (0.03, 0.81),
        (0.014, 0.86),
        (0.004, 1),
      ]),
    ),
    _Sight.burj: _Shape(
      _outline([
        -0.09,
        0,
        -0.09,
        0.1,
        -0.075,
        0.1,
        -0.075,
        0.22,
        -0.06,
        0.22,
        -0.06,
        0.36,
        -0.045,
        0.36,
        -0.045,
        0.5,
        -0.032,
        0.5,
        -0.032,
        0.63,
        -0.02,
        0.63,
        -0.02,
        0.74,
        -0.011,
        0.74,
        -0.011,
        0.83,
        -0.005,
        0.83,
        -0.003,
        0.92,
        0,
        1,
        0.004,
        0.9,
        0.008,
        0.79,
        0.016,
        0.79,
        0.016,
        0.69,
        0.027,
        0.69,
        0.027,
        0.57,
        0.04,
        0.57,
        0.04,
        0.43,
        0.056,
        0.43,
        0.056,
        0.29,
        0.072,
        0.29,
        0.072,
        0.15,
        0.09,
        0.15,
        0.09,
        0,
      ]),
    ),
    _Sight.table: _Shape(
      _outline([
        -1.9,
        0,
        -1.55,
        0.45,
        -1.38,
        0.9,
        -1.22,
        0.62,
        -1.05,
        0.72,
        -0.85,
        0.97,
        -0.6,
        1,
        0.55,
        1,
        0.72,
        0.95,
        0.95,
        0.55,
        1.15,
        0.4,
        1.42,
        0.62,
        1.52,
        0.48,
        1.75,
        0.2,
        1.95,
        0,
      ]),
    ),
    _Sight.fuji: _Shape(
      Path()
        ..moveTo(-2.2, 0)
        ..quadraticBezierTo(-0.9, -0.35, -0.16, -1)
        ..lineTo(-0.08, -0.985)
        ..lineTo(0, -1)
        ..lineTo(0.09, -0.98)
        ..lineTo(0.16, -1)
        ..quadraticBezierTo(0.9, -0.35, 2.2, 0)
        ..close(),
      snow: _snowLine(0.74, 0.07, 0.7, 9),
    ),
    _Sight.matterhorn: _Shape(
      _outline([
        -1,
        0,
        -0.62,
        0.3,
        -0.4,
        0.42,
        -0.2,
        0.78,
        -0.05,
        1,
        0.03,
        0.97,
        0.1,
        0.8,
        0.28,
        0.62,
        0.36,
        0.5,
        0.62,
        0.36,
        0.8,
        0.18,
        1.1,
        0,
      ]),
      snow: _snowLine(0.62, 0.09, 0.6, 7),
    ),
    _Sight.everest: _Shape(
      _outline([
        -1.5,
        0,
        -1.1,
        0.32,
        -0.85,
        0.4,
        -0.62,
        0.66,
        -0.5,
        0.6,
        -0.3,
        0.8,
        -0.12,
        0.93,
        0,
        1,
        0.1,
        0.9,
        0.22,
        0.86,
        0.36,
        0.7,
        0.55,
        0.62,
        0.7,
        0.74,
        0.84,
        0.58,
        1.05,
        0.4,
        1.3,
        0.22,
        1.6,
        0,
      ]),
      snow: _snowLine(0.6, 0.08, 1.1, 13),
    ),
  };

  static Path _join(List<Path> parts) => parts.reduce(
    (joined, part) => Path.combine(PathOperation.union, joined, part),
  );

  static RRect _bar(
    double left,
    double bottom,
    double right,
    double top,
    double radius,
  ) => RRect.fromLTRBR(left, -top, right, -bottom, Radius.circular(radius));

  static Path _outline(List<double> points) {
    final path = Path()..moveTo(points[0], -points[1]);
    for (var at = 2; at < points.length; at += 2) {
      path.lineTo(points[at], -points[at + 1]);
    }
    return path..close();
  }

  static Path _stepped(List<(double, double)> tiers) {
    final left = <double>[];
    var floor = 0.0;
    for (final (half, top) in tiers) {
      left.addAll([-half, floor, -half, top]);
      floor = top;
    }
    final right = <double>[];
    for (var at = left.length - 2; at >= 0; at -= 2) {
      right.addAll([-left[at], left[at + 1]]);
    }
    return _outline([...left, ...right]);
  }

  static Path _snowLine(double line, double depth, double half, int teeth) {
    final points = <double>[-half, 1.1, half, 1.1];
    for (var tooth = 0; tooth <= teeth; tooth++) {
      points.addAll([
        half - 2 * half * tooth / teeth,
        line +
            (tooth.isEven ? depth : -depth) * _drifts[tooth % _drifts.length],
      ]);
    }
    return _outline(points);
  }

  static Path _taj() {
    Path box(double left, double bottom, double right, double top) =>
        _outline([left, bottom, right, bottom, right, top, left, top]);
    Path dome(double x, double y, double width, double height) => Path()
      ..addOval(
        Rect.fromCenter(center: Offset(x, -y), width: width, height: height),
      );
    return _join([
      box(-0.68, 0, 0.68, 0.085),
      box(-0.37, 0.085, 0.37, 0.44),
      box(-0.13, 0.085, 0.13, 0.5),
      box(-0.008, 0.92, 0.008, 1),
      Path()
        ..moveTo(-0.15, -0.44)
        ..lineTo(-0.15, -0.56)
        ..cubicTo(-0.29, -0.62, -0.2, -0.86, 0, -0.93)
        ..cubicTo(0.2, -0.86, 0.29, -0.62, 0.15, -0.56)
        ..lineTo(0.15, -0.44)
        ..close(),
      for (final side in const [-1.0, 1.0]) ...[
        box(side * 0.27 - 0.055, 0.44, side * 0.27 + 0.055, 0.5),
        dome(side * 0.27, 0.5, 0.13, 0.14),
        box(side * 0.27 - 0.004, 0.56, side * 0.27 + 0.004, 0.61),
        _outline([
          side * 0.62 - 0.03,
          0.085,
          side * 0.62 + 0.03,
          0.085,
          side * 0.62 + 0.022,
          0.55,
          side * 0.62 - 0.022,
          0.55,
        ]),
        box(side * 0.62 - 0.035, 0.374, side * 0.62 + 0.035, 0.386),
        dome(side * 0.62, 0.575, 0.06, 0.08),
        box(side * 0.62 - 0.003, 0.61, side * 0.62 + 0.003, 0.65),
      ],
    ]);
  }

  static Path _eiffel() => Path()
    ..fillType = PathFillType.evenOdd
    ..moveTo(-0.19, 0)
    ..quadraticBezierTo(-0.105, -0.07, -0.088, -0.165)
    ..lineTo(-0.098, -0.165)
    ..lineTo(-0.098, -0.19)
    ..lineTo(-0.072, -0.19)
    ..quadraticBezierTo(-0.05, -0.27, -0.043, -0.345)
    ..lineTo(-0.052, -0.345)
    ..lineTo(-0.052, -0.365)
    ..lineTo(-0.036, -0.365)
    ..quadraticBezierTo(-0.016, -0.6, -0.011, -0.835)
    ..lineTo(-0.02, -0.835)
    ..lineTo(-0.02, -0.855)
    ..lineTo(-0.009, -0.855)
    ..lineTo(-0.005, -0.92)
    ..lineTo(0, -1)
    ..lineTo(0.005, -0.92)
    ..lineTo(0.009, -0.855)
    ..lineTo(0.02, -0.855)
    ..lineTo(0.02, -0.835)
    ..lineTo(0.011, -0.835)
    ..quadraticBezierTo(0.016, -0.6, 0.036, -0.365)
    ..lineTo(0.052, -0.365)
    ..lineTo(0.052, -0.345)
    ..lineTo(0.043, -0.345)
    ..quadraticBezierTo(0.05, -0.27, 0.072, -0.19)
    ..lineTo(0.098, -0.19)
    ..lineTo(0.098, -0.165)
    ..lineTo(0.088, -0.165)
    ..quadraticBezierTo(0.105, -0.07, 0.19, 0)
    ..close()
    ..moveTo(-0.118, 0)
    ..cubicTo(-0.1, -0.15, 0.1, -0.15, 0.118, 0)
    ..close()
    ..moveTo(-0.04, -0.2)
    ..lineTo(0.04, -0.2)
    ..lineTo(0.016, -0.335)
    ..lineTo(-0.016, -0.335)
    ..close();

  double _tall(_Sight sight) => sight.metres * scale;

  double _presence(_Sight sight) {
    final tall = _tall(sight);
    final near = _smooth((sight.looming - tall) / (sight.looming * 0.28));
    final small = ((tall - 22) / 14).clamp(0.0, 1.0);
    final beyond = sight.metres * far > sight.inFull ? 1 - finale : 1.0;
    return near * small * beyond;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final sights = _Sight.values.reversed.toList();
    canvas.save();
    canvas.clipRect(const Rect.fromLTRB(-2000, -2000, 2390, ground));
    for (final behind in const [true, false]) {
      for (final sight in sights) {
        if (sight.behind == behind) _sight(canvas, sight);
      }
    }
    _stack(canvas);
    canvas.restore();
    for (final sight in sights) {
      _label(canvas, sight);
    }
    _count(canvas);
    _bracket(canvas);
  }

  void _sight(Canvas canvas, _Sight sight) {
    final presence = _presence(sight);
    if (presence <= 0.01) return;
    final tall = _tall(sight);
    final shape = _shapes[sight]!;
    final tones = sight.behind ? _farTones : _nearTones;
    final rank = _Sight.values
        .where(
          (other) =>
              other.behind == sight.behind &&
              other.aside.sign == sight.aside.sign,
        )
        .toList()
        .indexOf(sight);
    final tone = tones[rank.isEven ? 0 : 1].withValues(alpha: presence);
    canvas.save();
    canvas.translate(axis + sight.offset(tall), ground);
    canvas.scale(tall);
    canvas.drawPath(shape.body, Paint()..color = tone);
    final shade = shape.shade;
    if (shade != null) {
      canvas.drawPath(
        shade,
        Paint()..color = _nearTones.first.withValues(alpha: 0.28 * presence),
      );
    }
    final snow = shape.snow;
    if (snow != null) {
      canvas.clipPath(shape.body);
      canvas.drawPath(
        snow,
        Paint()..color = _snowTone.withValues(alpha: 0.8 * presence),
      );
    }
    canvas.restore();
  }

  double get _width => max(_ribbon, TowerPage.printWidthMetres * scale);

  void _stack(Canvas canvas) {
    final stackingMs = this.stackingMs;
    final width = _width;
    if (stackingMs != null) {
      final tall = TowerPage.printMetres * scale;
      for (final (print, at) in _dropMs.indexed) {
        final dropped = Curves.easeOutCubic.transform(
          ((stackingMs - at) / 300).clamp(0.0, 1.0),
        );
        if (dropped <= 0) continue;
        final bottom = ground - print * tall - 70 * (1 - dropped);
        _paper(
          canvas,
          Rect.fromLTRB(
            axis - width / 2,
            bottom - tall,
            axis + width / 2,
            bottom,
          ),
          dropped,
        );
        _print(
          canvas,
          print,
          Rect.fromLTRB(
            axis - width / 2,
            bottom - tall,
            axis + width / 2,
            bottom,
          ),
          width,
          dropped,
        );
      }
      return;
    }
    final whole = Rect.fromLTRB(
      axis - width / 2,
      ground - metres * scale,
      axis + width / 2,
      ground,
    );
    _paper(canvas, whole, 1);
    canvas.save();
    canvas.clipRect(whole);
    final level = max(
      0.0,
      log(1.5 * width / (TowerPage.printMetres * scale)) / ln2,
    );
    final coarse = _smooth((level - level.floor() - 0.5) / 0.4);
    _prints(canvas, level.floor(), width, 1);
    if (coarse > 0) _prints(canvas, level.floor() + 1, width, coarse);
    canvas.restore();
  }

  void _paper(Canvas canvas, Rect sheet, double opacity) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(sheet.inflate(4), const Radius.circular(5)),
      Paint()
        ..color = RewindColors.cream.withValues(alpha: 0.38 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(sheet.inflate(2.4), const Radius.circular(3.4)),
      Paint()..color = RewindColors.ink.withValues(alpha: opacity),
    );
    canvas.drawRect(
      sheet,
      Paint()..color = RewindColors.photoPaper.withValues(alpha: opacity),
    );
  }

  void _prints(Canvas canvas, int level, double width, double opacity) {
    final span = TowerPage.printMetres * (1 << min(level, 30));
    final tall = span * scale;
    for (var tile = 0; tile * span < metres; tile++) {
      final bottom = ground - tile * tall;
      final cell = Rect.fromLTRB(
        axis - width / 2,
        bottom - tall,
        axis + width / 2,
        bottom,
      );
      if (opacity < 1) {
        canvas.drawRect(
          cell,
          Paint()..color = RewindColors.photoPaper.withValues(alpha: opacity),
        );
      }
      _print(canvas, tile << min(level, 30), cell, width, opacity);
    }
  }

  void _print(
    Canvas canvas,
    int photo,
    Rect sheet,
    double width,
    double opacity,
  ) {
    final border = max(1.0, width * 0.06);
    final window = Rect.fromLTRB(
      sheet.left + border,
      sheet.top + border / 2,
      sheet.right - border,
      sheet.bottom - border / 2,
    );
    if (window.height <= 0) return;
    final strip = this.strip;
    if (strip == null) {
      canvas.drawRect(
        window,
        Paint()
          ..color = RewindColors.confetti[1 + photo % 4].withValues(
            alpha: opacity,
          ),
      );
      return;
    }
    final tile = strip.source(_pick(photo, strip.length));
    final aspect = window.width / window.height;
    final source = aspect >= 1
        ? Rect.fromCenter(
            center: tile.center,
            width: tile.width,
            height: tile.height / aspect,
          )
        : Rect.fromCenter(
            center: tile.center,
            width: tile.width * aspect,
            height: tile.height,
          );
    canvas.drawImageRect(
      strip.image,
      source,
      window,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(255, 255, 255, opacity),
    );
  }

  static int _pick(int photo, int count) {
    var mixed = (photo * 0x9E3779B1) & 0x7FFFFFFF;
    mixed ^= mixed >> 15;
    return mixed % count;
  }

  void _label(Canvas canvas, _Sight sight) {
    final tall = _tall(sight);
    final top = ground - tall;
    final opacity =
        _presence(sight) *
        _smooth((tall - 96) / 30) *
        _smooth((top - 146) / 22);
    if (opacity <= 0.01) return;
    final passed = metres >= sight.metres;
    final name = _text(
      sight == _Sight.person ? person : sight.label,
      RewindTextStyles.display(
        10.5,
        height: 1.1,
      ).copyWith(color: RewindColors.cream.withValues(alpha: opacity)),
    );
    final height = _text(
      _height(sight.metres),
      RewindTextStyles.numeral(
        9.5,
        color: (passed ? RewindColors.yellow : RewindColors.cream).withValues(
          alpha: opacity,
        ),
      ),
    );
    final wide = max(name.width, height.width) + 14;
    final clear = _width / 2 + 34;
    var center = axis + sight.offset(tall) + sight.peak * tall;
    center = sight.aside < 0
        ? min(center, axis - clear - wide / 2)
        : max(center, axis + clear + wide / 2);
    center = center.clamp(14 + wide / 2, 376 - wide / 2);
    final plate = Rect.fromLTWH(center - wide / 2, top - 40, wide, 32);
    canvas.drawRRect(
      RRect.fromRectAndRadius(plate, const Radius.circular(7)),
      Paint()..color = RewindColors.ink.withValues(alpha: 0.78 * opacity),
    );
    name.paint(canvas, Offset(center - name.width / 2, plate.top + 4.5));
    height.paint(canvas, Offset(center - height.width / 2, plate.top + 17.5));
    name.dispose();
    height.dispose();
  }

  void _count(Canvas canvas) {
    if (stackingMs != null) return;
    final text = _text(
      rewindCounted(prints, "PRINT", "PRINTS"),
      RewindTextStyles.display(11.5, height: 1.1),
    );
    final top = ground - metres * scale;
    final plate = Rect.fromLTWH(
      axis - text.width / 2 - 8,
      top - 78,
      text.width + 16,
      22,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(plate, const Radius.circular(6)),
      Paint()..color = RewindColors.hotPink,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(plate, const Radius.circular(6)),
      Paint()
        ..color = RewindColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    text.paint(canvas, Offset(plate.left + 8, plate.top + 4.5));
    text.dispose();
  }

  void _bracket(Canvas canvas) {
    final stackingMs = this.stackingMs;
    if (stackingMs == null) return;
    final opacity = ((stackingMs - 520) / 240).clamp(0.0, 1.0);
    if (opacity <= 0) return;
    final tall = TowerPage.printMetres * scale;
    final x = axis + _width / 2 + 16;
    final line = Paint()
      ..color = RewindColors.cream.withValues(alpha: opacity)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(x, ground - 3), Offset(x, ground - tall + 3), line);
    canvas.drawLine(Offset(x - 6, ground - 3), Offset(x + 6, ground - 3), line);
    canvas.drawLine(
      Offset(x - 6, ground - tall + 3),
      Offset(x + 6, ground - tall + 3),
      line,
    );
    final text = _text(
      "15 CM",
      RewindTextStyles.display(
        15,
        height: 1.1,
      ).copyWith(color: RewindColors.cream.withValues(alpha: opacity)),
    );
    final caption = _text(
      "ONE PRINT",
      RewindTextStyles.numeral(
        9.5,
        color: RewindColors.yellow.withValues(alpha: opacity),
      ),
    );
    final plate = Rect.fromLTWH(
      x + 12,
      ground - tall / 2 - 21,
      max(text.width, caption.width) + 18,
      42,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(plate, const Radius.circular(8)),
      Paint()..color = RewindColors.ink.withValues(alpha: 0.78 * opacity),
    );
    text.paint(canvas, Offset(plate.left + 9, plate.top + 6));
    caption.paint(canvas, Offset(plate.left + 9, plate.top + 25));
    text.dispose();
    caption.dispose();
  }

  static TextPainter _text(String text, TextStyle style) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  bool shouldRepaint(_Scene oldDelegate) =>
      oldDelegate.scale != scale ||
      oldDelegate.metres != metres ||
      oldDelegate.strip != strip ||
      oldDelegate.stackingMs != stackingMs ||
      oldDelegate.finale != finale ||
      oldDelegate.person != person;
}
