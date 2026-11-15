import "dart:math";
import "dart:ui" show lerpDouble;

import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:photos/models/file/file.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_motion.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_elapsed.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_numbers.dart";
import "package:photos/ui/rewind/widgets/rewind_photo.dart";
import "package:photos/ui/rewind/widgets/rewind_reveal_layer.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

typedef _Pose = ({Offset center, double turn, double scale, double opacity});

typedef _Spot = ({Offset center, double width, double turn});

_Pose _lerp(_Pose a, _Pose b, double t) => (
  center: Offset.lerp(a.center, b.center, t)!,
  turn: lerpDouble(a.turn, b.turn, t)!,
  scale: lerpDouble(a.scale, b.scale, t)!,
  opacity: lerpDouble(a.opacity, b.opacity, t)!,
);

const _line = "Memories to be grateful for!";
const _titleRect = Rect.fromLTWH(28, 664, 331, 40);
const _lineRect = Rect.fromLTWH(28, 718, 316, 22);
const _sparkleAt = Offset(38.9, 110.9);
const _hundredAt = Offset(277, 466);

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
  const FavouritesPage(this.favourites, this.photos);

  final rust.Favourites favourites;
  final List<EnteFile> photos;

  @override
  String get key => "favourites";

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final count = favourites.photoCount;
    final title = rewindCounted(count, "FAVOURITE", "FAVOURITES");
    final covered = ModalRoute.of(context)?.isCurrent == false;
    final heart = SvgPicture.file(RewindAssets.file(RewindAssets.pinkHeart));
    return RewindShareable(
      shared: _Collage(photos: photos, count: count, title: title),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _backdrop(),
          Semantics(
            label: "${title.toLowerCase()}. $_line",
            child: ExcludeSemantics(
              child: RewindStage(
                children: [
                  Positioned.fill(
                    child: RewindLeave(
                      position: position,
                      centerY: 340,
                      child: RewindElapsed(
                        active: isActive && !covered,
                        stillMs: _Deck.stillMs,
                        builder: (context, ms) =>
                            _Deck(photos: photos, ms: ms, heart: heart),
                      ),
                    ),
                  ),
                  if (count >= 100)
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
                    child: Text(_line, style: RewindTextStyles.body(17)),
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
  const _Deck({required this.photos, required this.ms, required this.heart});

  static const stillMs = _firstTurnMs;
  static const _firstPopMs = 820.0;
  static const _firstTurnMs = 2200.0;
  static const _beatMs = 2100.0;
  static const _popDelayMs = 260.0;
  static const _turn = RewindMotion.soft;
  static const _entrance = RewindMotion.soft;
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
  final Widget heart;

  bool get _spins => photos.length >= 3;

  double get _spun {
    if (!_spins || ms < _firstTurnMs) return 0;
    final since = ms - _firstTurnMs;
    final turns = (since / _beatMs).floor();
    final within = (since - turns * _beatMs) / _turn.duration.inMilliseconds;
    return turns + _turn.transform(min(1.0, within));
  }

  @override
  Widget build(BuildContext context) {
    final spun = _spun;
    final cards = [
      for (
        var sequence = (spun - _reach).floor();
        sequence <= (spun + _reach).ceil();
        sequence++
      )
        if ((sequence - spun).abs() < _reach &&
            (_spins || (sequence >= 0 && sequence < photos.length)))
          (sequence: sequence, slot: sequence - spun),
    ];
    cards.sort((a, b) {
      final depth = b.slot.abs().compareTo(a.slot.abs());
      return depth != 0 ? depth : a.slot.compareTo(b.slot);
    });
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final card in cards) _card(card.sequence, card.slot, spun),
      ],
    );
  }

  Widget _card(int sequence, double slot, double spun) {
    final pose = spun == 0 ? _entering(slot) : _onWheel(slot);
    final pop = _popMs(sequence);
    final scale = pose.scale * (pop == null ? 1.0 : _HeartPop.squash(pop));
    final bob = _bobPx * sin(2 * pi * ms / _bobMs + sequence * 1.7);
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
            ..scaleByDouble(scale, scale, 1, 1),
          child: _FavouriteCard(
            photos[sequence % photos.length],
            pop: pop == null ? null : _HeartPop(pop, heart: heart),
          ),
        ),
      ),
    );
  }

  _Pose _entering(double slot) {
    final resting = _onWheel(slot);
    if (slot.abs() > 1) return resting;
    final (from, delayMs) = switch (slot) {
      0 => (_frontFrom, 0.0),
      < 0 => (_backFrom, 260.0),
      _ => (_backFrom, 320.0),
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

  double? _popMs(int sequence) {
    final double start;
    if (sequence == 0) {
      start = _firstPopMs;
    } else if (_spins && sequence > 0) {
      start = _firstTurnMs + (sequence - 1) * _beatMs + _popDelayMs;
    } else {
      return null;
    }
    final since = ms - start;
    return since >= 0 && since <= _HeartPop.durationMs ? since : null;
  }
}

class _FavouriteCard extends StatelessWidget {
  const _FavouriteCard(this.file, {this.pop, this.badged = false});

  static const size = Size(302.042, 380.35);

  final EnteFile file;
  final Widget? pop;
  final bool badged;

  @override
  Widget build(BuildContext context) {
    final pop = this.pop;
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        Container(
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
        ),
        if (pop != null) IgnorePointer(child: pop),
        if (badged)
          Positioned(
            right: -24,
            top: -28,
            width: 88,
            height: 88,
            child: Transform.rotate(
              angle: 14 * pi / 180,
              child: SvgPicture.file(RewindAssets.file(RewindAssets.pinkHeart)),
            ),
          ),
      ],
    );
  }
}

class _HeartPop extends StatelessWidget {
  const _HeartPop(this.ms, {required this.heart});

  static const durationMs = 1150.0;
  static const _size = 118.0;
  static const _sparks = 6;
  static const _sparkStartMs = 80.0;
  static const _sparkMs = 640.0;
  static const _sparkTravel = 104.0;
  static const _fadeStartMs = 700.0;
  static const _fadeMs = 380.0;
  static const _squashKeys = [
    (0.0, 1.0),
    (90.0, 0.965),
    (240.0, 1.03),
    (420.0, 1.0),
  ];

  final double ms;
  final Widget heart;

  static double squash(double ms) {
    for (var i = 1; i < _squashKeys.length; i++) {
      final (endMs, end) = _squashKeys[i];
      if (ms > endMs) continue;
      final (startMs, start) = _squashKeys[i - 1];
      final t = Curves.easeInOut.transform(
        ((ms - startMs) / (endMs - startMs)).clamp(0.0, 1.0),
      );
      return lerpDouble(start, end, t)!;
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final grow = rewindProgress(
      ms,
      delayMs: 0,
      durationMs: RewindMotion.pop.duration.inMilliseconds.toDouble(),
      curve: RewindMotion.pop,
    );
    final fade = rewindProgress(
      ms,
      delayMs: _fadeStartMs,
      durationMs: _fadeMs,
      curve: Curves.easeIn,
    );
    final center =
        _FavouriteCard.size.center(Offset.zero) - Offset(0, 26 * fade);
    final sparkT = (ms - _sparkStartMs) / _sparkMs;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (sparkT > 0 && sparkT < 1)
          for (var i = 0; i < _sparks; i++) _spark(i, sparkT, center),
        Positioned.fromRect(
          rect: Rect.fromCenter(center: center, width: _size, height: _size),
          child: Opacity(
            opacity: 1 - fade,
            child: Transform.scale(
              scale: grow * (1 - 0.15 * fade),
              child: heart,
            ),
          ),
        ),
      ],
    );
  }

  Widget _spark(int i, double t, Offset from) {
    final angle = -pi / 2 + 0.35 + i * 2 * pi / _sparks;
    final travel = _sparkTravel * Curves.easeOutCubic.transform(t);
    final size = 34 * (1 - 0.35 * t);
    return Positioned.fromRect(
      rect: Rect.fromCenter(
        center:
            from + Offset(cos(angle), sin(angle)) * travel - Offset(0, 10 * t),
        width: size,
        height: size,
      ),
      child: Opacity(
        opacity: 1 - Curves.easeIn.transform(t),
        child: Transform.rotate(
          angle: (i.isEven ? 0.5 : -0.5) * t,
          child: heart,
        ),
      ),
    );
  }
}

class _Collage extends StatelessWidget {
  const _Collage({
    required this.photos,
    required this.count,
    required this.title,
  });

  static const _layouts = <List<_Spot>>[
    [(center: Offset(195, 362), width: 288, turn: -3)],
    [
      (center: Offset(140, 262), width: 216, turn: -6),
      (center: Offset(252, 478), width: 216, turn: 5),
    ],
    [
      (center: Offset(116, 236), width: 190, turn: -7),
      (center: Offset(276, 290), width: 190, turn: 6),
      (center: Offset(186, 500), width: 200, turn: -2),
    ],
    [
      (center: Offset(106, 256), width: 170, turn: -6),
      (center: Offset(284, 266), width: 170, turn: 5),
      (center: Offset(106, 480), width: 170, turn: 4),
      (center: Offset(284, 470), width: 170, turn: -5),
    ],
    [
      (center: Offset(105, 188), width: 152, turn: -6),
      (center: Offset(285, 196), width: 152, turn: 5),
      (center: Offset(195, 370), width: 156, turn: -3),
      (center: Offset(105, 552), width: 152, turn: 5),
      (center: Offset(285, 544), width: 152, turn: -4),
    ],
    [
      (center: Offset(105, 188), width: 152, turn: -6),
      (center: Offset(285, 196), width: 152, turn: 5),
      (center: Offset(105, 372), width: 152, turn: 4),
      (center: Offset(285, 366), width: 152, turn: -5),
      (center: Offset(105, 554), width: 152, turn: -3),
      (center: Offset(285, 548), width: 152, turn: 6),
    ],
  ];

  final List<EnteFile> photos;
  final int count;
  final String title;

  @override
  Widget build(BuildContext context) {
    final shown = photos.take(_layouts.length).toList();
    final spots = _layouts[max(shown.length, 1) - 1];
    return Stack(
      fit: StackFit.expand,
      children: [
        _backdrop(),
        RewindStage(
          children: [
            for (var i = shown.length - 1; i >= 0; i--)
              _placed(shown[i], spots[i], badged: i == 0),
            if (count >= 100)
              Positioned(
                left: _hundredAt.dx,
                top: _hundredAt.dy,
                child: _hundred(),
              ),
            Positioned(
              left: _sparkleAt.dx,
              top: _sparkleAt.dy,
              child: _sparkle(),
            ),
            Positioned(
              left: _titleRect.left,
              top: _titleRect.top,
              width: _titleRect.width,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: _titleRect.width),
                child: FittedBox(fit: BoxFit.scaleDown, child: _title(title)),
              ),
            ),
            Positioned(
              left: _lineRect.left,
              top: _lineRect.top,
              width: _lineRect.width,
              child: Text(_line, style: RewindTextStyles.body(17)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _placed(EnteFile file, _Spot spot, {required bool badged}) {
    final scale = spot.width / _FavouriteCard.size.width;
    return Positioned.fromRect(
      rect: Rect.fromCenter(
        center: spot.center,
        width: _FavouriteCard.size.width,
        height: _FavouriteCard.size.height,
      ),
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..rotateZ(spot.turn * pi / 180)
          ..scaleByDouble(scale, scale, 1, 1),
        child: _FavouriteCard(file, badged: badged),
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
