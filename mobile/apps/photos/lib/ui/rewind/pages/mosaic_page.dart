import "dart:math";
import "dart:typed_data";
import "dart:ui" as ui;

import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:photos/models/file/file.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_page_scope.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_elapsed.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_hint.dart";
import "package:photos/ui/rewind/widgets/rewind_numbers.dart";
import "package:photos/ui/rewind/widgets/rewind_pixels.dart";
import "package:photos/ui/rewind/widgets/rewind_reveal_layer.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";

class MosaicPage extends RewindPage {
  MosaicPage({
    required this.files,
    this.subject,
    this.subjectName,
    this.bytes = rewindThumbnailBytes,
  });

  static const pageKey = "mosaic";
  static const minimumTiles = 120;

  final List<EnteFile> files;
  final Uint8List? subject;
  final String? subjectName;
  final RewindBytes bytes;

  var _isOnScreen = false;

  late final RewindWarm<_Tiling> _tiling = RewindWarm(
    () => _Tiling.of(files, subject, bytes, () => _isOnScreen),
    (tiling) => tiling.dispose(),
  );

  @override
  String get key => pageKey;

  @override
  int get warmAhead => 8;

  @override
  Duration? get reelHold => const Duration(milliseconds: 3400);

  @override
  Future<bool> warmUp() async => await _tiling.value != null;

  @override
  void release() => _tiling.release();

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    _isOnScreen = _isOnScreen || isActive;
    final who = subject == null
        ? "${RewindEdition.year}"
        : subjectName?.toUpperCase();
    final pace = _Pace.of(context);
    return RewindWarmBuilder<_Tiling>(
      warm: _tiling,
      builder: (context, tiling) => Stack(
        fit: StackFit.expand,
        children: [
          _card(position, isActive, who, tiling, pace),
          RewindHint(
            "TAP OR PINCH TO DIVE IN",
            centerY: 500,
            active: isActive && tiling != null,
            position: position,
            delayMs: pace.revealedMs + 300,
          ),
        ],
      ),
    );
  }

  Widget _card(
    double position,
    bool isActive,
    String? who,
    _Tiling? tiling,
    _Pace pace,
  ) {
    final count = tiling == null
        ? "GATHERING"
        : "${rewindCount(tiling.atlas.length)} OF";
    final label = "$count YOUR PHOTOS";
    final title = "MAKE ONE ${who ?? "OF YOU"}";
    const body = "Every tile is a real photo from your year.";
    return RewindShareable(
      enabled: tiling != null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RewindBackdrop(
            color: Color(0xFFFF6727),
            pattern: RewindStripes(Color(0xFFFF7638)),
          ),
          Semantics(
            label: "$label $title. $body",
            child: ExcludeSemantics(
              child: RewindStage(
                children: [
                  Positioned.fromRect(
                    rect: _Wall.frame.inflate(12),
                    child: RewindLeave(
                      position: position,
                      centerY: _Wall.frame.center.dy,
                      child: RewindEntrance(
                        preset: RewindPreset.drop,
                        active: isActive,
                        child: _Wall(
                          key: ValueKey(tiling),
                          tiling: tiling,
                          pace: pace,
                          active: isActive,
                        ),
                      ),
                    ),
                  ),
                  ...rewindCaption(
                    label: label,
                    title: title,
                    body: body,
                    me: (
                      label: "$count MY PHOTOS",
                      title: "MAKE ONE ${who ?? "OF ME"}",
                      body: "Every tile is a real photo from my year.",
                    ),
                    position: position,
                    active: isActive && tiling != null,
                    delayMs: pace.revealedMs - 500,
                    top: 600,
                    titleSize: 44,
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

class _Tiling {
  _Tiling(this.atlas, this.print, this.transforms, this.sources);

  static const columns = 44;
  static const rows = 56;
  static const _detail = 2;
  static const _printCell = 24.0;
  static const _tint = 0.62;
  static const _reuseCost = 2600.0;
  static const _neighbourCost = 9000.0;

  final RewindAtlas atlas;
  final ui.Image print;
  final Float32List transforms;
  final Float32List sources;

  void dispose() {
    atlas.dispose();
    print.dispose();
  }

  static Future<_Tiling?> of(
    List<EnteFile> files,
    Uint8List? subject,
    RewindBytes bytes,
    bool Function() isRushed,
  ) async {
    final target = await _target(subject);
    if (target == null) return null;
    final atlas = await RewindAtlas.load(
      files,
      tile: 80,
      bytes: bytes,
      minimum: MosaicPage.minimumTiles,
      budget: const Duration(seconds: 25),
      isRushed: isRushed,
    );
    if (atlas == null) return null;
    final quarters = await atlas.quarters();
    final cells = await _assign(quarters, target);
    final cell = _Wall.frame.width / columns;
    final transforms = Float32List(cells.length * 4);
    final sources = Float32List(cells.length * 4);
    for (final (index, tile) in cells.indexed) {
      final source = atlas.source(tile);
      transforms
        ..[index * 4] = cell / atlas.tile
        ..[index * 4 + 1] = 0
        ..[index * 4 + 2] = (index % columns) * cell
        ..[index * 4 + 3] = (index ~/ columns) * cell;
      sources
        ..[index * 4] = source.left
        ..[index * 4 + 1] = source.top
        ..[index * 4 + 2] = source.right
        ..[index * 4 + 3] = source.bottom;
    }
    return _Tiling(
      atlas,
      await _develop(atlas, quarters, cells, target),
      transforms,
      sources,
    );
  }

  static Future<Float32List?> _target(Uint8List? subject) async {
    const wide = columns * _detail;
    const tall = rows * _detail;
    const draft = 4;
    const size = Size(wide * draft * 1.0, tall * draft * 1.0);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (subject == null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = RewindColors.ink);
      const year = "${RewindEdition.year}";
      for (final (line, digits) in [
        year.substring(0, 2),
        year.substring(2),
      ].indexed) {
        final painter = TextPainter(
          text: TextSpan(
            text: digits,
            style: RewindTextStyles.display(
              220,
              color: line == 0 ? RewindColors.yellow : RewindColors.hotPink,
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(
          canvas,
          Offset((size.width - painter.width) / 2, 18 + line * 206.0),
        );
        painter.dispose();
      }
    } else {
      final codec = await ui.instantiateImageCodec(subject);
      final face = (await codec.getNextFrame()).image;
      codec.dispose();
      final scale = max(size.width / face.width, size.height / face.height);
      canvas.drawImageRect(
        face,
        Rect.fromCenter(
          center: Offset(face.width / 2, face.height * 0.47),
          width: size.width / scale,
          height: size.height / scale,
        ),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium,
      );
      face.dispose();
    }
    final drawn = recorder.endRecording();
    final large = await drawn.toImage(size.width.round(), size.height.round());
    drawn.dispose();
    final shrink = ui.PictureRecorder();
    Canvas(shrink).drawImageRect(
      large,
      Offset.zero & size,
      Rect.fromLTWH(0, 0, wide.toDouble(), tall.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final small = shrink.endRecording();
    final image = await small.toImage(wide, tall);
    small.dispose();
    large.dispose();
    final pixels = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    image.dispose();
    if (pixels == null) return null;
    final target = Float32List(wide * tall * 3);
    final lights = Float32List(wide * tall);
    for (var pixel = 0; pixel < wide * tall; pixel++) {
      for (var channel = 0; channel < 3; channel++) {
        target[pixel * 3 + channel] = pixels
            .getUint8(pixel * 4 + channel)
            .toDouble();
      }
      lights[pixel] = _light(target, pixel * 3);
    }
    if (subject == null) return target;
    final sorted = Float32List.fromList(lights)..sort();
    final dark = sorted[(sorted.length * 0.02).floor()];
    final bright = sorted[(sorted.length * 0.98).floor()];
    final stretch = (236 / max(1.0, bright - dark)).clamp(1.0, 2.4);
    for (var pixel = 0; pixel < wide * tall; pixel++) {
      final light = (lights[pixel] - dark) * stretch + 10;
      for (var channel = 0; channel < 3; channel++) {
        final colour = (target[pixel * 3 + channel] - dark) * stretch + 10;
        target[pixel * 3 + channel] = (light + (colour - light) * 1.18).clamp(
          0.0,
          255.0,
        );
      }
    }
    return target;
  }

  static double _light(Float32List colours, int at) =>
      0.3 * colours[at] + 0.59 * colours[at + 1] + 0.11 * colours[at + 2];

  static Future<Int32List> _assign(
    Float32List tiles,
    Float32List target,
  ) async {
    final count = tiles.length ~/ 12;
    final uses = Int32List(count);
    final cells = Int32List(columns * rows)..fillRange(0, columns * rows, -1);
    final order = [for (var cell = 0; cell < cells.length; cell++) cell]
      ..shuffle(Random(RewindEdition.year));
    final crowding = _reuseCost / pow(cells.length / count, 2);
    final wanted = Float32List(12);
    final clock = Stopwatch()..start();
    for (final cell in order) {
      if (clock.elapsedMilliseconds > 5) {
        await Future<void>.delayed(Duration.zero);
        clock.reset();
      }
      final column = cell % columns;
      final row = cell ~/ columns;
      for (var quarter = 0; quarter < 4; quarter++) {
        final at =
            ((row * _detail + (quarter >> 1)) * columns * _detail +
                column * _detail +
                (quarter & 1)) *
            3;
        wanted
          ..[quarter * 3] = target[at]
          ..[quarter * 3 + 1] = target[at + 1]
          ..[quarter * 3 + 2] = target[at + 2];
      }
      final left = column > 0 ? cells[cell - 1] : -1;
      final right = column < columns - 1 ? cells[cell + 1] : -1;
      final above = row > 0 ? cells[cell - columns] : -1;
      final below = row < rows - 1 ? cells[cell + columns] : -1;
      var best = 0;
      var bestCost = double.infinity;
      for (var tile = 0; tile < count; tile++) {
        var cost = crowding * uses[tile] * uses[tile];
        if (tile == left || tile == right || tile == above || tile == below) {
          cost += _neighbourCost;
        }
        if (cost >= bestCost) continue;
        final base = tile * 12;
        for (var part = 0; part < 12; part += 3) {
          final red = tiles[base + part] - wanted[part];
          final green = tiles[base + part + 1] - wanted[part + 1];
          final blue = tiles[base + part + 2] - wanted[part + 2];
          cost += 0.5 * red * red + green * green + 0.75 * blue * blue;
        }
        if (cost < bestCost) {
          bestCost = cost;
          best = tile;
        }
      }
      cells[cell] = best;
      uses[best]++;
    }
    return cells;
  }

  static Future<ui.Image> _develop(
    RewindAtlas atlas,
    Float32List quarters,
    Int32List cells,
    Float32List target,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final (cell, tile) in cells.indexed) {
      final column = cell % columns;
      final row = cell ~/ columns;
      final shift = [0.0, 0.0, 0.0];
      for (var quarter = 0; quarter < 4; quarter++) {
        final at =
            ((row * _detail + (quarter >> 1)) * columns * _detail +
                column * _detail +
                (quarter & 1)) *
            3;
        for (var channel = 0; channel < 3; channel++) {
          shift[channel] +=
              (target[at + channel] -
                  quarters[tile * 12 + quarter * 3 + channel]) /
              4;
        }
      }
      canvas.drawImageRect(
        atlas.image,
        atlas.source(tile),
        Rect.fromLTWH(
          column * _printCell,
          row * _printCell,
          _printCell,
          _printCell,
        ),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..colorFilter = ColorFilter.matrix([
            1,
            0,
            0,
            0,
            _tint * shift[0],
            0,
            1,
            0,
            0,
            _tint * shift[1],
            0,
            0,
            1,
            0,
            _tint * shift[2],
            0,
            0,
            0,
            1,
            0,
          ]),
      );
    }
    final drawn = recorder.endRecording();
    final print = await drawn.toImage(
      (columns * _printCell).round(),
      (rows * _printCell).round(),
    );
    drawn.dispose();
    return print;
  }
}

class _EagerScaleRecognizer extends ScaleGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

enum _Pace {
  viewer(holdMs: 1500, pullMs: 3800),
  reel(holdMs: 400, pullMs: 2300);

  const _Pace({required this.holdMs, required this.pullMs});

  final int holdMs;
  final int pullMs;

  int get revealedMs => holdMs + pullMs;

  static _Pace of(BuildContext context) =>
      RewindPageScope.reelOf(context) ? reel : viewer;
}

class _Wall extends StatefulWidget {
  const _Wall({
    required this.tiling,
    required this.pace,
    required this.active,
    super.key,
  });

  static const frame = Rect.fromLTWH(30, 110, 330, 420);
  static const _opening = 10.0;
  static const _closest = 14.0;
  static const _dive = 8.0;
  static const _eye = Offset(0.42, 0.4);

  final _Tiling? tiling;
  final _Pace pace;
  final bool active;

  @override
  State<_Wall> createState() => _WallState();
}

class _WallState extends State<_Wall> with SingleTickerProviderStateMixin {
  late final _glide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..addListener(_onGlide);

  var _zoom = 1.0;
  var _focus = const Offset(0.5, 0.5);
  var _handsOn = false;
  var _fromZoom = 1.0;
  var _fromFocus = const Offset(0.5, 0.5);
  var _toZoom = 1.0;
  var _toFocus = const Offset(0.5, 0.5);
  var _grabZoom = 1.0;
  var _grabbed = Offset.zero;
  var _travel = 0.0;
  var _fingers = 0;
  var _pinched = false;

  @override
  void dispose() {
    _glide.dispose();
    super.dispose();
  }

  static Offset _clamped(Offset focus, double zoom) {
    final reach = 0.5 / zoom;
    return Offset(
      focus.dx.clamp(reach, 1 - reach),
      focus.dy.clamp(reach, 1 - reach),
    );
  }

  ({double zoom, Offset focus}) _reveal(double ms) {
    final pulled = Curves.easeInOutCubic.transform(
      ((ms - widget.pace.holdMs) / widget.pace.pullMs).clamp(0.0, 1.0),
    );
    final zoom = exp(log(_Wall._opening) * (1 - pulled));
    final drift = Offset(0.012 * sin(ms / 900), 0.008 * cos(ms / 700));
    return (
      zoom: zoom,
      focus: _clamped(
        Offset.lerp(
          _Wall._eye + drift * (1 - pulled),
          const Offset(0.5, 0.5),
          pulled,
        )!,
        zoom,
      ),
    );
  }

  void _onGlide() {
    final eased = Curves.easeInOutCubic.transform(_glide.value);
    setState(() {
      _zoom = exp(log(_fromZoom) + (log(_toZoom) - log(_fromZoom)) * eased);
      _focus = _clamped(Offset.lerp(_fromFocus, _toFocus, eased)!, _zoom);
    });
  }

  void _glideTo(double zoom, Offset focus) {
    _fromZoom = _zoom;
    _fromFocus = _focus;
    _toZoom = zoom;
    _toFocus = _clamped(focus, zoom);
    _glide.forward(from: 0);
    HapticFeedback.selectionClick();
  }

  void _touch() {
    _pinched = _fingers > 0;
    if (!_pinched) _travel = 0;
    _fingers++;
  }

  void _lift({required bool tapped}) {
    _fingers = max(0, _fingers - 1);
    if (!tapped || _fingers > 0 || _pinched || _travel > 10) return;
    _zoom < 1.5
        ? _glideTo(_Wall._dive, _grabbed)
        : _glideTo(1, const Offset(0.5, 0.5));
  }

  Offset _under(Offset touch, double zoom, Offset focus) => Offset(
    focus.dx + (touch.dx - _Wall.frame.width / 2) / (_Wall.frame.width * zoom),
    focus.dy +
        (touch.dy - _Wall.frame.height / 2) / (_Wall.frame.height * zoom),
  );

  @override
  Widget build(BuildContext context) {
    final tiling = widget.tiling;
    return RewindElapsed(
      active: widget.active && tiling != null,
      stillMs: 60000,
      builder: (context, ms) {
        final revealed = ms >= widget.pace.revealedMs;
        final view = _handsOn ? (zoom: _zoom, focus: _focus) : _reveal(ms);
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _WallPainter(
                  tiling: tiling,
                  zoom: view.zoom,
                  focus: view.focus,
                  ms: tiling == null ? ms : 0,
                ),
              ),
            ),
            if (tiling != null && revealed)
              Positioned.fill(
                left: 12,
                top: 12,
                right: 12,
                bottom: 12,
                child: Listener(
                  onPointerDown: (_) => _touch(),
                  onPointerUp: (_) => _lift(tapped: true),
                  onPointerCancel: (_) => _lift(tapped: false),
                  child: RawGestureDetector(
                    behavior: HitTestBehavior.opaque,
                    gestures: {
                      _EagerScaleRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            _EagerScaleRecognizer
                          >(
                            _EagerScaleRecognizer.new,
                            (recognizer) => recognizer
                              ..onStart = (details) {
                                _glide.stop();
                                if (!_handsOn) {
                                  _zoom = view.zoom;
                                  _focus = view.focus;
                                  _handsOn = true;
                                }
                                _grabZoom = _zoom;
                                _grabbed = _under(
                                  details.localFocalPoint,
                                  _zoom,
                                  _focus,
                                );
                              }
                              ..onUpdate = (details) {
                                _travel += details.focalPointDelta.distance;
                                final zoom = (_grabZoom * details.scale).clamp(
                                  1.0,
                                  _Wall._closest,
                                );
                                final touch = details.localFocalPoint;
                                setState(() {
                                  _zoom = zoom;
                                  _focus = _clamped(
                                    Offset(
                                      _grabbed.dx -
                                          (touch.dx - _Wall.frame.width / 2) /
                                              (_Wall.frame.width * zoom),
                                      _grabbed.dy -
                                          (touch.dy - _Wall.frame.height / 2) /
                                              (_Wall.frame.height * zoom),
                                    ),
                                    zoom,
                                  );
                                });
                              },
                          ),
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _WallPainter extends CustomPainter {
  _WallPainter({
    required this.tiling,
    required this.zoom,
    required this.focus,
    required this.ms,
  });

  static const _inset = 12.0;
  static const _mat = 7.0;

  final _Tiling? tiling;
  final double zoom;
  final Offset focus;
  final double ms;

  @override
  void paint(Canvas canvas, Size size) {
    final print = Rect.fromLTWH(
      _inset - _mat,
      _inset - _mat,
      size.width - 2 * (_inset - _mat),
      size.height - 2 * (_inset - _mat),
    );
    final picture = (Offset.zero & size).deflate(_inset);
    final ink = Paint()..color = RewindColors.ink;
    final card = RRect.fromRectAndRadius(print, const Radius.circular(8));
    canvas.drawRRect(card.shift(const Offset(5, 6)), ink);
    canvas.drawRRect(card, Paint()..color = RewindColors.cream);
    canvas.drawRRect(
      card,
      Paint()
        ..color = RewindColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.save();
    canvas.clipRect(picture);
    final tiling = this.tiling;
    if (tiling == null) {
      _developing(canvas, picture);
    } else {
      canvas.translate(picture.center.dx, picture.center.dy);
      canvas.scale(zoom);
      canvas.translate(-focus.dx * picture.width, -focus.dy * picture.height);
      final near = ((zoom - 1.6) / 4.4).clamp(0.0, 1.0);
      final tinted = 1 - near * near * (3 - 2 * near);
      if (tinted < 1) {
        canvas.drawRawAtlas(
          tiling.atlas.image,
          tiling.transforms,
          tiling.sources,
          null,
          null,
          null,
          Paint()..filterQuality = FilterQuality.medium,
        );
      }
      if (tinted > 0) {
        canvas.drawImageRect(
          tiling.print,
          Rect.fromLTWH(
            0,
            0,
            tiling.print.width.toDouble(),
            tiling.print.height.toDouble(),
          ),
          Rect.fromLTWH(
            0,
            0,
            picture.width,
            _Tiling.rows * picture.width / _Tiling.columns,
          ),
          Paint()
            ..filterQuality = FilterQuality.medium
            ..color = Color.fromRGBO(255, 255, 255, tinted),
        );
      }
    }
    canvas.restore();
    canvas.drawRect(
      picture,
      Paint()
        ..color = RewindColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _developing(Canvas canvas, Rect picture) {
    final cell = picture.width / 10;
    for (var row = 0; row * cell < picture.height; row++) {
      for (var column = 0; column < 10; column++) {
        final wave = 0.5 + 0.5 * sin(ms / 260 - (row + column) * 0.7);
        canvas.drawRect(
          Rect.fromLTWH(
            picture.left + column * cell,
            picture.top + row * cell,
            cell,
            cell,
          ).deflate(1.5),
          Paint()
            ..color = Color.lerp(
              const Color(0xFFFFE2B8),
              const Color(0xFFFFC79A),
              wave,
            )!,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_WallPainter oldDelegate) =>
      oldDelegate.tiling != tiling ||
      oldDelegate.zoom != zoom ||
      oldDelegate.focus != focus ||
      oldDelegate.ms != ms;
}
