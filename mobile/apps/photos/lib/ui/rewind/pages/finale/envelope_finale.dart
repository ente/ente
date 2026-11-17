import "dart:math";

import "package:flutter/material.dart";
import "package:flutter/scheduler.dart";
import "package:flutter/services.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/rewind/pages/finale/envelope.dart";
import "package:photos/ui/rewind/pages/finale/finale_actions.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_elapsed.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_wordmark.dart";

const _riseAtMs = 80.0;
const _riseMs = 760.0;
const _outAtMs = 640.0;
const _outEveryMs = 150.0;
const _outMs = 860.0;
const _settledMs =
    _outAtMs + (EnvelopeFinale.photoCount - 1) * _outEveryMs + _outMs;
const _actionsDelayMs = 1150;
const _tuckedTop = 610.0;
const _stickersAtMs = 1340;

class _Slot {
  const _Slot(this.left, this.top, this.width, this.height, this.tiltDeg);

  final double left;
  final double top;
  final double width;
  final double height;
  final double tiltDeg;
}

const _slots = [
  _Slot(108, 212, 174, 200, 3),
  _Slot(12, 332, 136, 188, -9),
  _Slot(243, 338, 136, 186, 8),
  _Slot(119, 394, 150, 168, -3),
];

const _duckSlot = _Slot(85, 296, 220, 244, -4);

const _slotsForCount = [
  <int>[],
  [0],
  [1, 2],
  [0, 1, 2],
  [0, 1, 2, 3],
];

class EnvelopeFinale extends StatefulWidget {
  const EnvelopeFinale({required this.photos, required this.active, super.key});

  static const photoCount = 4;

  final List<EnteFile> photos;
  final bool active;

  @override
  State<EnvelopeFinale> createState() => _EnvelopeFinaleState();
}

class _EnvelopeFinaleState extends State<EnvelopeFinale>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final _ms = ValueNotifier(0.0);
  var _banked = Duration.zero;
  var _since = Duration.zero;
  var _landed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(EnvelopeFinale oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _ms.dispose();
    super.dispose();
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

  void _onTick(Duration elapsed) {
    _since = _banked + elapsed;
    final ms = _since.inMicroseconds / 1000;
    if (!_landed && ms > _outAtMs + _outMs * 0.55) {
      _landed = true;
      if (ms < _outAtMs + _outMs) {
        HapticFeedback.lightImpact().ignore();
      }
    }
    _ms.value = ms;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          _card(context, EnvelopeShape.bleedFor(constraints.biggest)),
    );
  }

  Widget _card(BuildContext context, double bleed) {
    final still = MediaQuery.disableAnimationsOf(context);
    final photos = widget.photos.take(EnvelopeFinale.photoCount).toList();
    return Stack(
      fit: StackFit.expand,
      children: [
        Semantics(
          label: "What a year. Thanks for being here.",
          child: ExcludeSemantics(
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(color: Color(0xFF14C52E)),
                  child: CustomPaint(painter: _WavesPainter()),
                ),
                RewindStage(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 58,
                      child: RewindEntrance(
                        preset: RewindPreset.pop,
                        active: widget.active,
                        delayMs: 60,
                        child: const _Lockup(),
                      ),
                    ),
                    Positioned(
                      left: 20,
                      right: 20,
                      top: 132,
                      child: RewindEntrance(
                        preset: RewindPreset.line,
                        active: widget.active,
                        delayMs: 220,
                        child: const _Headline(),
                      ),
                    ),
                    Positioned.fill(
                      child: ValueListenableBuilder(
                        valueListenable: _ms,
                        builder: (context, ms, _) => _Envelope(
                          photos: photos,
                          ms: still ? _settledMs : ms,
                          bleed: bleed,
                        ),
                      ),
                    ),
                    _sticker(
                      RewindAssets.cameraSticker,
                      16,
                      226,
                      86,
                      0,
                      tiltDeg: -10,
                      idle: RewindIdle.pulse,
                    ),
                    _sticker(RewindAssets.yellowSparkle, 300, 262, 42, 160),
                    _sticker(RewindAssets.yellowSparkle, 90, 472, 34, 320),
                    _sticker(
                      RewindAssets.pinkHeart,
                      250,
                      466,
                      60,
                      480,
                      idle: RewindIdle.pulse,
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
              right: 20,
              top: 598,
              child: IgnorePointer(
                child: RewindEntrance(
                  preset: RewindPreset.line,
                  active: widget.active,
                  delayMs: _actionsDelayMs - 120,
                  child: Text(
                    "Your full Rewind, as a video.",
                    textAlign: TextAlign.center,
                    style: RewindTextStyles.body(
                      16.5,
                      color: RewindColors.ink,
                      weight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 626,
              child: Center(
                child: ValueListenableBuilder(
                  valueListenable: _ms,
                  builder: (context, ms, actions) => IgnorePointer(
                    ignoring:
                        !widget.active || (!still && ms < _actionsDelayMs),
                    child: actions,
                  ),
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

  Widget _sticker(
    String asset,
    double left,
    double top,
    double width,
    int delayMs, {
    double tiltDeg = 0,
    RewindIdle idle = RewindIdle.twinkle,
  }) {
    final atMs = _stickersAtMs + delayMs;
    return Positioned(
      left: left,
      top: top,
      child: RewindEntrance(
        preset: RewindPreset.pop,
        active: widget.active,
        delayMs: atMs,
        child: RewindIdleLoop(
          idle: idle,
          active: widget.active,
          delayMs: atMs + 900,
          child: Transform.rotate(
            angle: tiltDeg * pi / 180,
            child: asset.endsWith(".svg")
                ? SvgPicture.file(RewindAssets.file(asset), width: width)
                : Image.file(RewindAssets.file(asset), width: width),
          ),
        ),
      ),
    );
  }
}

class _Envelope extends StatelessWidget {
  const _Envelope({
    required this.photos,
    required this.ms,
    required this.bleed,
  });

  final List<EnteFile> photos;
  final double ms;
  final double bleed;

  @override
  Widget build(BuildContext context) {
    final lift =
        (1 -
            rewindProgress(
              ms,
              delayMs: _riseAtMs,
              durationMs: _riseMs,
              curve: Curves.easeOutCubic,
            )) *
        460;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Transform.translate(
            offset: Offset(0, lift),
            child: CustomPaint(painter: EnvelopeBackPainter(bleed: bleed)),
          ),
        ),
        if (photos.isEmpty)
          _emerging(
            _duckSlot,
            0,
            lift,
            Image.file(
              RewindAssets.file(RewindAssets.polaroidHugDucky),
              width: _duckSlot.width,
            ),
          )
        else
          for (final (order, slot) in _slotsForCount[photos.length].indexed)
            _emerging(
              _slots[slot],
              order,
              lift,
              EnvelopePhoto(
                key: ValueKey(photos[order].tag),
                photo: photos[order],
                size: Size(_slots[slot].width, _slots[slot].height),
              ),
            ),
        Positioned.fill(
          child: Transform.translate(
            offset: Offset(0, lift),
            child: CustomPaint(painter: EnvelopeFrontPainter(bleed: bleed)),
          ),
        ),
      ],
    );
  }

  Widget _emerging(_Slot slot, int order, double lift, Widget child) {
    final out = rewindProgress(
      ms,
      delayMs: _outAtMs + order * _outEveryMs,
      durationMs: _outMs,
      curve: Curves.easeOutBack,
    );
    final sway = sin(ms / 900 + order * 1.7) * 0.8;
    return Positioned(
      left: slot.left,
      top: slot.top + lift + (1 - out) * (_tuckedTop - slot.top),
      child: Transform.rotate(
        angle: (slot.tiltDeg + sway) * out * pi / 180,
        child: child,
      ),
    );
  }
}

class _Lockup extends StatelessWidget {
  const _Lockup();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const RewindWordmark(color: RewindColors.cream, width: 62),
        const SizedBox(height: 4),
        Image.file(RewindAssets.file(RewindAssets.compactHeader), width: 206),
      ],
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline();

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        "What a year.\nThanks for being here.",
        textAlign: TextAlign.center,
        style: RewindTextStyles.numeral(
          29,
          color: RewindColors.cream,
        ).copyWith(height: 1.08),
      ),
    );
  }
}

class _WavesPainter extends CustomPainter {
  const _WavesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x8C3BD650)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.13;
    for (var band = 0; band < 6; band++) {
      final baseline = size.height * (band * 0.3 - 0.2);
      double wave(double x) => baseline + x * 0.55 + sin(x / 70 + band) * 26;
      final path = Path()..moveTo(-40, wave(-40));
      for (var x = -32.0; x <= size.width + 40; x += 8) {
        path.lineTo(x, wave(x));
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_WavesPainter oldDelegate) => false;
}
