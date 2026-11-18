import "dart:math";
import "dart:ui" show lerpDouble;

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_page_scope.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_motion.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_elapsed.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_photo.dart";
import "package:photos/ui/rewind/widgets/rewind_reveal_layer.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

typedef _Pose = ({Offset center, double turn, double scale, double opacity});

typedef _Settle = ({double from, double to, double atMs});

_Pose _lerp(_Pose a, _Pose b, double t) => (
  center: Offset.lerp(a.center, b.center, t)!,
  turn: lerpDouble(a.turn, b.turn, t)!,
  scale: lerpDouble(a.scale, b.scale, t)!,
  opacity: lerpDouble(a.opacity, b.opacity, t)!,
);

const _line = "Memories to be grateful for!";
const _titleRect = Rect.fromLTWH(28, 664, 334, 40);
const _lineRect = Rect.fromLTWH(28, 718, 334, 22);
const _sparkleAt = Offset(38.9, 110.9);
const _hundredAt = Offset(277, 482.7);

Widget _backdrop() => RewindBackdrop(
  color: const Color(0xFFFB4196),
  pattern: RewindStripes(const Color(0xFFFF4D9F).withValues(alpha: 0.42)),
);

Widget _title(String title) => RewindOutlinedText(
  title,
  style: RewindTextStyles.display(
    48.039,
    color: RewindColors.white,
    height: 0.84,
    letterSpacing: -1.4412,
  ),
  shadow: const Offset(1.766, 2.119),
);

Widget _sparkle() =>
    const CustomPaint(size: Size.square(70), painter: _SparklePainter());

Widget _hundred() => Image.file(
  RewindAssets.file(RewindAssets.hundredSticker),
  width: 110,
  height: 104,
);

class FavouritesPage extends RewindPage {
  const FavouritesPage(this.photos);

  final List<EnteFile> photos;

  @override
  String get key => "favourites";

  @override
  Duration? get reelHold =>
      const Duration(milliseconds: 3100 + RewindMotion.reelReadingMs);

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    return _Favourites(photos: photos, position: position, isActive: isActive);
  }
}

class _Favourites extends StatefulWidget {
  const _Favourites({
    required this.photos,
    required this.position,
    required this.isActive,
  });

  final List<EnteFile> photos;
  final double position;
  final bool isActive;

  @override
  State<_Favourites> createState() => _FavouritesState();
}

class _FavouritesState extends State<_Favourites> {
  static const _firstTurnMs = 2200.0;
  static const _beatMs = 2100.0;
  static const _handsOffMs = 3000.0;
  static const _turn = RewindMotion.soft;
  static const _dragPerTurn = 110.0;
  static const _flingVelocity = 350.0;

  var _ms = 0.0;
  var _shownFront = 0;
  var _latchedFront = 0;
  bool? _still;
  double? _dragged;
  _Settle? _settle;

  List<EnteFile> get _photos => widget.photos;

  bool get _wraps => _photos.length >= 3;

  bool get _swipes => _photos.length >= 2;

  double get _turnMs => _turn.duration.inMilliseconds.toDouble();

  static int _frontOf(double spun) => (spun + 0.5).floor();

  double _spunAt(double ms, {required bool still}) {
    final dragged = _dragged;
    if (dragged != null) return dragged;
    final settle = _settle;
    if (settle == null) {
      return _wraps ? _autoSpun(ms, from: 0, turnAtMs: _firstTurnMs) : 0;
    }
    final into = ms - settle.atMs;
    if (!still && into >= 0 && into < _turnMs) {
      return lerpDouble(
        settle.from,
        settle.to,
        _turn.transform(into / _turnMs),
      )!;
    }
    return _wraps
        ? _autoSpun(ms, from: settle.to, turnAtMs: settle.atMs + _handsOffMs)
        : settle.to;
  }

  double _autoSpun(
    double ms, {
    required double from,
    required double turnAtMs,
  }) {
    if (ms < turnAtMs) return from;
    final since = ms - turnAtMs;
    final turns = (since / _beatMs).floor();
    final within = (since - turns * _beatMs) / _turnMs;
    return from + turns + _turn.transform(min(1.0, within));
  }

  double _bounded(double spun) =>
      _wraps ? spun : spun.clamp(0.0, _photos.length - 1.0);

  double get _stageScale => RewindStage.scaleFor(MediaQuery.sizeOf(context));

  void _settleTo(double from, double to) {
    setState(() {
      _dragged = null;
      _settle = (from: from, to: _bounded(to), atMs: _ms);
    });
  }

  void _step(int by) {
    final front = _shownFront.toDouble();
    _settleTo(front, front + by);
  }

  void _restartFromShown(double ms) {
    final front = _shownFront.toDouble();
    _settle = (from: front, to: front, atMs: ms);
  }

  void _grab(DragStartDetails details) {
    setState(
      () => _dragged = _spunAt(
        _ms,
        still: MediaQuery.disableAnimationsOf(context),
      ),
    );
  }

  void _drag(DragUpdateDetails details) {
    final dragged = _dragged;
    if (dragged == null) return;
    final next = _bounded(
      dragged - details.primaryDelta! / (_dragPerTurn * _stageScale),
    );
    if (_frontOf(next) != _frontOf(dragged)) HapticFeedback.selectionClick();
    setState(() => _dragged = next);
  }

  void _release(DragEndDetails details) {
    final dragged = _dragged;
    if (dragged == null) return;
    final velocity = (details.primaryVelocity ?? 0) / _stageScale;
    _settleTo(
      dragged,
      velocity.abs() < _flingVelocity
          ? dragged.roundToDouble()
          : velocity < 0
          ? dragged.floorToDouble() + 1
          : dragged.ceilToDouble() - 1,
    );
  }

  void _latch() => _latchedFront = _shownFront;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      onScrollLeft: _swipes ? () => _step(1) : null,
      onScrollRight: _swipes ? () => _step(-1) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        excludeFromSemantics: true,
        onHorizontalDragStart: _swipes ? _grab : null,
        onHorizontalDragUpdate: _swipes ? _drag : null,
        onHorizontalDragEnd: _swipes ? _release : null,
        onHorizontalDragCancel: _swipes
            ? () => _release(DragEndDetails())
            : null,
        child: RewindShareable(
          onShare: _latch,
          child: Builder(
            builder: (context) =>
                _page(context, capturing: RewindShareable.capturing(context)),
          ),
        ),
      ),
    );
  }

  Widget _page(BuildContext context, {required bool capturing}) {
    final position = capturing ? 0.0 : widget.position;
    final isActive = widget.isActive || capturing;
    final covered = RewindPageScope.coveredOf(context);
    final media = MediaQuery.of(context);
    final title = capturing
        ? "MY FAVOURITE"
        : RewindPageScope.reelOf(context)
        ? "MY FAVOURITES"
        : "YOUR FAVOURITES";
    return MediaQuery(
      data: media.copyWith(
        disableAnimations: media.disableAnimations || capturing,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _backdrop(),
          Semantics(
            label: "Your favourites. $_line",
            child: ExcludeSemantics(
              child: RewindStage(
                children: [
                  Positioned.fill(
                    child: RewindLeave(
                      position: position,
                      centerY: 340,
                      child: RewindElapsed(
                        active: isActive && !covered,
                        stillMs: _firstTurnMs,
                        builder: (context, ms) {
                          if (capturing) {
                            return _Deck(
                              photos: _photos,
                              ms: ms,
                              spun: _latchedFront.toDouble(),
                              wraps: _wraps,
                              frontOnly: true,
                            );
                          }
                          final still = MediaQuery.disableAnimationsOf(context);
                          if (_still != null && _still != still) {
                            _restartFromShown(ms);
                          }
                          _still = still;
                          final spun = _spunAt(ms, still: still);
                          _ms = ms;
                          _shownFront = _frontOf(spun);
                          return _Deck(
                            photos: _photos,
                            ms: ms,
                            spun: spun,
                            wraps: _wraps,
                            frontOnly: false,
                          );
                        },
                      ),
                    ),
                  ),
                  RewindRevealLayer(
                    left: _hundredAt.dx,
                    top: _hundredAt.dy,
                    height: 104,
                    position: position,
                    active: isActive,
                    preset: RewindPreset.pop,
                    delayMs: 1150,
                    child: _hundred(),
                  ),
                  RewindRevealLayer(
                    left: _sparkleAt.dx,
                    top: _sparkleAt.dy,
                    height: 70,
                    position: position,
                    active: isActive,
                    preset: RewindPreset.twinkle,
                    delayMs: 1250,
                    child: RewindIdleLoop(
                      idle: RewindIdle.twinkle,
                      active: isActive,
                      delayMs: 1950,
                      child: _sparkle(),
                    ),
                  ),
                  RewindRevealLayer(
                    left: _titleRect.left,
                    top: _titleRect.top,
                    width: _titleRect.width,
                    maxWidth: _titleRect.width,
                    height: _titleRect.height,
                    position: position,
                    active: isActive,
                    preset: RewindPreset.slap,
                    delayMs: 1300,
                    child: _title(title),
                  ),
                  RewindRevealLayer(
                    left: _lineRect.left,
                    top: _lineRect.top,
                    width: _lineRect.width,
                    height: _lineRect.height,
                    position: position,
                    active: isActive,
                    delayMs: 1600,
                    child: capturing
                        ? const SizedBox.shrink()
                        : Text(
                            _line,
                            textAlign: TextAlign.center,
                            style: RewindTextStyles.body(17),
                          ),
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

class _Deck extends StatelessWidget {
  const _Deck({
    required this.photos,
    required this.ms,
    required this.spun,
    required this.wraps,
    required this.frontOnly,
  });

  static const _entrance = RewindMotion.soft;
  static const _backDelayMs = 260.0;
  static const _sideDelayMs = 320.0;
  static const _reach = 2.0;

  static const _pivot = Offset(194.6, 581);
  static const _radius = 240.8;
  static const _slotArc = 25.4 * pi / 180;
  static const _slotTurn = 19.8;
  static const _sideScale = 0.892;
  static const _offsideShift = 430.0;
  static const _offsideY = 380.0;
  static const _offsideTurn = 30.0;
  static const _bobPx = 2.4;
  static const _bobMs = 2800.0;

  static const _Pose _frontFrom = (
    center: Offset(194.6, 400),
    turn: 0,
    scale: 0.9,
    opacity: 0,
  );
  static const _Pose _backFrom = (
    center: Offset(194.6, 350),
    turn: 0,
    scale: 0.892,
    opacity: 0,
  );

  final List<EnteFile> photos;
  final double ms;
  final double spun;
  final bool wraps;
  final bool frontOnly;

  @override
  Widget build(BuildContext context) {
    if (frontOnly) {
      return Stack(clipBehavior: Clip.none, children: [_card(spun.round(), 0)]);
    }
    final cards = [
      for (
        var sequence = (spun - _reach).floor();
        sequence <= (spun + _reach).ceil();
        sequence++
      )
        if ((sequence - spun).abs() < _reach &&
            (wraps || (sequence >= 0 && sequence < photos.length)))
          (sequence: sequence, slot: sequence - spun),
    ];
    cards.sort((a, b) {
      final depth = b.slot.abs().compareTo(a.slot.abs());
      return depth != 0 ? depth : a.slot.compareTo(b.slot);
    });
    return Stack(
      clipBehavior: Clip.none,
      children: [for (final card in cards) _card(card.sequence, card.slot)],
    );
  }

  Widget _card(int sequence, double slot) {
    final pose = frontOnly
        ? _onWheel(0)
        : spun == 0
        ? _entering(slot)
        : _onWheel(slot);
    final bob = frontOnly
        ? 0.0
        : _bobPx * sin(2 * pi * ms / _bobMs + sequence * 1.7);
    return Positioned.fromRect(
      key: ValueKey(sequence),
      rect: Rect.fromCenter(
        center: pose.center + Offset(0, bob),
        width: _FavouriteCard.size.width,
        height: _FavouriteCard.size.height,
      ),
      child: Opacity(
        opacity: pose.opacity.clamp(0.0, 1.0),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..rotateZ(pose.turn * pi / 180)
            ..scaleByDouble(pose.scale, pose.scale, 1, 1),
          child: _FavouriteCard(photos[sequence % photos.length]),
        ),
      ),
    );
  }

  _Pose _entering(double slot) {
    final resting = _onWheel(slot);
    if (slot.abs() > 1) return resting;
    final (from, delayMs) = switch (slot) {
      0 => (_frontFrom, 0.0),
      < 0 => (_backFrom, _backDelayMs),
      _ => (_backFrom, _sideDelayMs),
    };
    return _lerp(
      from,
      resting,
      rewindProgress(
        ms,
        delayMs: delayMs,
        durationMs: _entrance.duration.inMilliseconds.toDouble(),
        curve: _entrance,
      ),
    );
  }

  _Pose _onWheel(double slot) {
    if (slot.abs() <= 1) {
      final arc = slot * _slotArc;
      return (
        center: _pivot + Offset(sin(arc), -cos(arc)) * _radius,
        turn: slot * _slotTurn,
        scale: 1 - (1 - _sideScale) * slot * slot,
        opacity: 1,
      );
    }
    final side = slot.sign;
    final _Pose offside = (
      center: Offset(_pivot.dx + side * _offsideShift, _offsideY),
      turn: side * _offsideTurn,
      scale: _sideScale,
      opacity: 1,
    );
    return _lerp(_onWheel(side), offside, slot.abs() - 1);
  }
}

class _FavouriteCard extends StatelessWidget {
  const _FavouriteCard(this.file);

  static const size = Size(302.042, 380.35);

  final EnteFile file;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8.95),
      decoration: BoxDecoration(
        color: RewindColors.cream,
        borderRadius: BorderRadius.circular(26.85),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E000000),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19.02),
        child: RewindPhoto(file, placeholder: const Color(0x1F151515)),
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  const _SparklePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 70);
    final star = Path()
      ..moveTo(46.38, 2.5)
      ..cubicTo(42.22, 22.23, 49.03, 36.86, 66.81, 46.38)
      ..cubicTo(47.07, 42.22, 32.45, 49.03, 22.93, 66.8)
      ..cubicTo(27.09, 47.07, 20.28, 32.45, 2.5, 22.93)
      ..cubicTo(22.23, 27.09, 36.86, 20.28, 46.38, 2.5)
      ..close();
    canvas.drawPath(star, Paint()..color = RewindColors.yellow);
    canvas.drawPath(
      star,
      Paint()
        ..color = RewindColors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparklePainter oldDelegate) => false;
}
