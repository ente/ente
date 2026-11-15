import "dart:math";
import "dart:ui" as ui;

import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_page_scope.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_elapsed.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_hint.dart";
import "package:photos/ui/rewind/widgets/rewind_layer.dart";
import "package:photos/ui/rewind/widgets/rewind_numbers.dart";
import "package:photos/ui/rewind/widgets/rewind_pixels.dart";
import "package:photos/ui/rewind/widgets/rewind_reveal_layer.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

const _months = [
  "JAN",
  "FEB",
  "MAR",
  "APR",
  "MAY",
  "JUN",
  "JUL",
  "AUG",
  "SEP",
  "OCT",
  "NOV",
  "DEC",
];

typedef RewindLapseFrame = ({
  EnteFile file,
  int month,
  int day,
  Offset leftEye,
  Offset rightEye,
});

class TimelapsePage extends RewindPage {
  TimelapsePage({
    required this.frames,
    required this.name,
    required this.photoCount,
    this.bytes = rewindThumbnailBytes,
  });

  static const pageKey = "timelapse";
  static const minimumFrames = 8;

  final List<RewindLapseFrame> frames;
  final String? name;
  final int photoCount;
  final RewindBytes bytes;

  late final RewindWarm<_Reel> _reel = RewindWarm(
    () => _Reel.of(frames, bytes),
    (reel) => reel.atlas.dispose(),
  );

  @override
  String get key => pageKey;

  @override
  Duration? get reelHold => Duration(
    milliseconds:
        950 +
        min(
          _Flipbook._frameMs * (_reel.loaded?.frames.length ?? frames.length),
          _Flipbook._reelLapMs,
        ).round(),
  );

  @override
  Future<bool> warmUp() async => await _reel.value != null;

  @override
  void release() => _reel.release();

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final who = name?.toUpperCase();
    final span =
        "${_months[frames.first.month - 1]} TO ${_months[frames.last.month - 1]}";
    final body =
        "${rewindCounted(photoCount, "photo", "photos")} this year, "
        "lined up by the eyes.";
    return RewindWarmBuilder<_Reel>(
      warm: _reel,
      builder: (context, reel) => Stack(
        fit: StackFit.expand,
        children: [
          _card(position, isActive, who, span, body, reel),
          RewindHint(
            "TAP A FACE",
            centerY: 566,
            active: isActive && reel != null,
            position: position,
            delayMs: 3400,
          ),
        ],
      ),
    );
  }

  Widget _card(
    double position,
    bool isActive,
    String? who,
    String span,
    String body,
    _Reel? reel,
  ) {
    return RewindShareable(
      enabled: reel != null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RewindBackdrop(
            color: Color(0xFF9841E3),
            pattern: RewindStripes(Color(0xFF9D4EE0)),
          ),
          Semantics(
            label: "A year of ${who ?? "YOU"}, $span. $body",
            child: ExcludeSemantics(
              child: RewindStage(
                children: [
                  Positioned.fill(
                    child: RewindLeave(
                      position: position,
                      centerY: 320,
                      child: _Flipbook(
                        key: ValueKey(reel),
                        reel: reel,
                        active: isActive,
                      ),
                    ),
                  ),
                  RewindRevealLayer(
                    left: 28,
                    top: 597,
                    maxWidth: 316,
                    height: 18,
                    position: position,
                    active: isActive,
                    delayMs: 500,
                    child: Text(
                      "A YEAR OF",
                      style: RewindTextStyles.display(17, height: 1.05),
                    ),
                  ),
                  RewindLayer(
                    rect: const Rect.fromLTWH(28, 620, 334, 62),
                    position: position,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: RewindEntrance(
                        preset: RewindPreset.slap,
                        active: isActive,
                        delayMs: 700,
                        origin: Alignment.centerLeft,
                        child: RewindFitWidth(
                          width: 322,
                          child: RewindVoice(
                            you: who ?? "YOU",
                            me: who ?? "ME",
                            builder: (text) => RewindOutlinedText(
                              text,
                              style: RewindTextStyles.display(
                                62,
                                color: RewindColors.yellow,
                                height: 0.9,
                                letterSpacing: -1.2,
                              ),
                              outline: 3.6,
                              shadow: const Offset(2.4, 2.9),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  RewindRevealLayer(
                    left: 28,
                    top: 690,
                    width: 334,
                    height: 44,
                    position: position,
                    active: isActive,
                    delayMs: 1000,
                    child: Text(body, style: RewindTextStyles.body(17)),
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

class _Reel {
  const _Reel(this.atlas, this.frames);

  static const _side = 256;
  static const _eyeLine = 0.43;
  static const _eyeGap = 0.3;

  final RewindAtlas atlas;
  final List<RewindLapseFrame> frames;

  static Future<_Reel?> of(
    List<RewindLapseFrame> frames,
    RewindBytes bytes,
  ) async {
    final atlas = await RewindAtlas.load(
      [for (final frame in frames) frame.file],
      tile: _side,
      decodeSide: 512,
      bytes: bytes,
      minimum: TimelapsePage.minimumFrames,
      paint: (canvas, image, cell, index) =>
          _align(canvas, image, cell, frames[index]),
    );
    if (atlas == null) return null;
    return _Reel(atlas, [
      for (final file in atlas.files)
        frames.firstWhere((frame) => identical(frame.file, file)),
    ]);
  }

  static void _align(
    Canvas canvas,
    ui.Image image,
    Rect cell,
    RewindLapseFrame frame,
  ) {
    final left = Offset(
      frame.leftEye.dx * image.width,
      frame.leftEye.dy * image.height,
    );
    final right = Offset(
      frame.rightEye.dx * image.width,
      frame.rightEye.dy * image.height,
    );
    final across = right - left;
    canvas.drawRect(cell, Paint()..color = const Color(0xFF2A2233));
    canvas.translate(
      cell.left + cell.width / 2,
      cell.top + cell.height * _eyeLine,
    );
    canvas.rotate(-across.direction);
    canvas.scale(cell.width * _eyeGap / max(1, across.distance));
    canvas.translate(-(left.dx + right.dx) / 2, -(left.dy + right.dy) / 2);
    canvas.drawImage(
      image,
      Offset.zero,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }
}

class _EagerSwipeRecognizer extends HorizontalDragGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _Flipbook extends StatefulWidget {
  const _Flipbook({required this.reel, required this.active, super.key});

  static const portrait = Rect.fromLTWH(95, 102, 200, 200);
  static const wall = Rect.fromLTWH(27.5, 330, 335, 212);
  static const _startMs = 900.0;
  static const _frameMs = 150.0;
  static const _reelLapMs = 2200.0;
  static const _restFrames = 10.0;
  static const _dragPerFrame = 9.0;
  static const _handsOffMs = 2400.0;

  final _Reel? reel;
  final bool active;

  @override
  State<_Flipbook> createState() => _FlipbookState();
}

class _Grid {
  const _Grid(this.count);

  static const _gap = 4.4;

  final int count;

  int get columns => count <= 18
      ? 6
      : count <= 28
      ? 7
      : 8;

  int get rows => (count / columns).ceil();

  double get cell => (_Flipbook.wall.width - (columns - 1) * _gap) / columns;

  double get _pitch => cell + _gap;

  double get _top => (_Flipbook.wall.height - rows * _pitch + _gap) / 2;

  Rect tile(int index) => Rect.fromLTWH(
    (index % columns) * _pitch,
    _top + (index ~/ columns) * _pitch,
    cell,
    cell,
  );

  int? under(Offset touch) {
    final column = (touch.dx / _pitch).floor();
    final row = ((touch.dy - _top) / _pitch).floor();
    final index = row * columns + column;
    final inside = column >= 0 && column < columns && row >= 0 && index < count;
    return inside ? index : null;
  }
}

class _FlipbookState extends State<_Flipbook> {
  double? _held;
  var _heldAtMs = 0.0;
  var _phase = 0.0;
  var _ms = 0.0;

  int get _count => widget.reel?.frames.length ?? 0;

  double get _frameMs => RewindPageScope.reelOf(context)
      ? min(_Flipbook._frameMs, _Flipbook._reelLapMs / max(1, _count))
      : _Flipbook._frameMs;

  double _playing(double ms) {
    final lap = _count + _Flipbook._restFrames * _Flipbook._frameMs / _frameMs;
    return min(
      _count - 1.0,
      max(0.0, (ms - _Flipbook._startMs) / _frameMs + _phase) % lap,
    );
  }

  double _at(double ms) {
    final held = _held;
    if (held == null) return _playing(ms);
    if (ms - _heldAtMs < _Flipbook._handsOffMs) return held;
    _phase = held - (ms - _Flipbook._startMs) / _frameMs;
    _held = null;
    return _playing(ms);
  }

  void _hold(double frame) {
    final clamped = frame.clamp(0.0, _count - 1.0);
    if (clamped.round() != _held?.round()) HapticFeedback.selectionClick();
    setState(() {
      _held = clamped;
      _heldAtMs = _ms;
    });
  }

  @override
  Widget build(BuildContext context) {
    final reel = widget.reel;
    final grid = _Grid(_count);
    return RewindElapsed(
      active: widget.active,
      stillMs: 600000,
      builder: (context, ms) {
        _ms = ms;
        final at = reel == null ? 0.0 : _at(ms);
        final shown = reel?.frames[at.round()];
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fromRect(
              rect: _Flipbook.portrait.inflate(14),
              child: RewindEntrance(
                preset: RewindPreset.pop,
                active: widget.active,
                child: CustomPaint(
                  painter: _PortraitPainter(
                    reel: reel,
                    at: at,
                    ms: ms,
                    yearGone: shown == null
                        ? 0
                        : ((shown.month - 1) * 30.4 + shown.day) / 365,
                  ),
                ),
              ),
            ),
            if (shown != null)
              Positioned(
                left: _Flipbook.portrait.right - 78,
                top: _Flipbook.portrait.bottom - 38,
                child: RewindEntrance(
                  preset: RewindPreset.pop,
                  active: widget.active,
                  delayMs: 500,
                  child: Transform.rotate(
                    angle: -0.09,
                    child: _DateTag("${shown.day} ${_months[shown.month - 1]}"),
                  ),
                ),
              ),
            Positioned.fromRect(
              rect: _Flipbook.wall,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  final index = grid.under(details.localPosition);
                  if (index != null) _hold(index.toDouble());
                },
                child: CustomPaint(
                  painter: _FacesPainter(
                    reel: reel,
                    grid: grid,
                    current: reel == null ? -1 : at.round(),
                    frameMs: _frameMs,
                    ms: ms,
                  ),
                ),
              ),
            ),
            if (reel != null)
              Positioned.fromRect(
                rect: _Flipbook.portrait,
                child: RawGestureDetector(
                  behavior: HitTestBehavior.opaque,
                  gestures: {
                    _EagerSwipeRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          _EagerSwipeRecognizer
                        >(
                          _EagerSwipeRecognizer.new,
                          (recognizer) => recognizer
                            ..onUpdate = (details) => _hold(
                              (_held ?? at) +
                                  details.primaryDelta! /
                                      _Flipbook._dragPerFrame,
                            ),
                        ),
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PortraitPainter extends CustomPainter {
  _PortraitPainter({
    required this.reel,
    required this.at,
    required this.ms,
    required this.yearGone,
  });

  final _Reel? reel;
  final double at;
  final double ms;
  final double yearGone;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 14;
    final ink = Paint()..color = RewindColors.ink;
    canvas.drawCircle(center + const Offset(6, 7), radius + 12, ink);
    canvas.drawCircle(center, radius + 12, ink);
    canvas.drawCircle(
      center,
      radius + 8.5,
      Paint()..color = RewindColors.cream,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius + 5),
      -pi / 2,
      2 * pi * yearGone.clamp(0.0, 1.0),
      false,
      Paint()
        ..color = RewindColors.yellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7,
    );
    canvas.drawCircle(center, radius + 1.5, ink);
    final face = Rect.fromCircle(center: center, radius: radius);
    canvas.save();
    canvas.clipPath(Path()..addOval(face));
    final reel = this.reel;
    if (reel == null) {
      canvas.drawRect(face, Paint()..color = const Color(0xFF2A2233));
      canvas.drawCircle(
        center,
        radius * (0.25 + 0.08 * sin(ms / 300)),
        Paint()..color = const Color(0xFF473A57),
      );
    } else {
      final from = at.floor().clamp(0, reel.frames.length - 1);
      final to = min(from + 1, reel.frames.length - 1);
      final blend = Curves.easeInOut.transform(at - at.floor());
      final paint = Paint()..filterQuality = FilterQuality.medium;
      canvas.drawImageRect(
        reel.atlas.image,
        reel.atlas.source(from),
        face,
        paint,
      );
      canvas.drawImageRect(
        reel.atlas.image,
        reel.atlas.source(to),
        face,
        paint..color = Color.fromRGBO(255, 255, 255, blend),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PortraitPainter oldDelegate) =>
      oldDelegate.reel != reel || oldDelegate.at != at || oldDelegate.ms != ms;
}

class _FacesPainter extends CustomPainter {
  _FacesPainter({
    required this.reel,
    required this.grid,
    required this.current,
    required this.frameMs,
    required this.ms,
  });

  static const _empty = Color(0xFF7B36BE);

  final _Reel? reel;
  final _Grid grid;
  final int current;
  final double frameMs;
  final double ms;

  @override
  void paint(Canvas canvas, Size size) {
    final reel = this.reel;
    if (reel == null) {
      for (var slot = 0; slot < 24; slot++) {
        final beat = 0.5 + 0.5 * sin(ms / 280 - slot * 0.5);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const _Grid(24).tile(slot).deflate(3 - 3 * beat),
            const Radius.circular(8),
          ),
          Paint()..color = _empty.withValues(alpha: 0.5 + 0.4 * beat),
        );
      }
      return;
    }
    for (var index = 0; index < grid.count; index++) {
      if (index != current) _tile(canvas, reel, index);
    }
    if (current >= 0) _tile(canvas, reel, current);
  }

  void _tile(Canvas canvas, _Reel reel, int index) {
    final slot = grid.tile(index);
    final arrived = Curves.easeOutBack.transform(
      ((ms - _Flipbook._startMs - index * frameMs) / 260).clamp(0.0, 1.0),
    );
    final round = Radius.circular(slot.width * 0.2);
    if (arrived <= 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(slot.deflate(2), round),
        Paint()..color = _empty,
      );
      return;
    }
    final isCurrent = index == current;
    final rect = Rect.fromCenter(
      center: slot.center,
      width: slot.width * arrived * (isCurrent ? 1.2 : 1),
      height: slot.height * arrived * (isCurrent ? 1.2 : 1),
    );
    final ink = Paint()..color = RewindColors.ink;
    final frame = RRect.fromRectAndRadius(rect.inflate(2.2), round);
    canvas.drawRRect(frame.shift(const Offset(2, 2.6)), ink);
    canvas.drawRRect(
      frame,
      isCurrent ? (Paint()..color = RewindColors.yellow) : ink,
    );
    if (isCurrent) {
      canvas.drawRRect(
        frame,
        Paint()
          ..color = RewindColors.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
    final face = RRect.fromRectAndRadius(
      rect.deflate(isCurrent ? 1.2 : 0),
      Radius.circular(slot.width * 0.16),
    );
    canvas.save();
    canvas.clipRRect(face);
    canvas.drawImageRect(
      reel.atlas.image,
      reel.atlas.source(index),
      face.outerRect,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FacesPainter oldDelegate) =>
      oldDelegate.reel != reel ||
      oldDelegate.current != current ||
      oldDelegate.ms != ms;
}

class _DateTag extends StatelessWidget {
  const _DateTag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: RewindColors.hotPink,
        border: Border.all(color: RewindColors.ink, width: 3),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(color: RewindColors.ink, offset: Offset(3, 4)),
        ],
      ),
      child: Text(text, style: RewindTextStyles.display(18, height: 1.1)),
    );
  }
}
