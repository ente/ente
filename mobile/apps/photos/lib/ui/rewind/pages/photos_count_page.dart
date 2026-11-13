import "dart:math";

import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:photos/models/file/file.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_motion.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_count_up.dart";
import "package:photos/ui/rewind/widgets/rewind_elapsed.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_keyframes.dart";
import "package:photos/ui/rewind/widgets/rewind_layer.dart";
import "package:photos/ui/rewind/widgets/rewind_numbers.dart";
import "package:photos/ui/rewind/widgets/rewind_photo.dart";
import "package:photos/ui/rewind/widgets/rewind_photo_frames.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

class PhotosCountPage extends RewindPage {
  const PhotosCountPage(this.count, this.photos);

  static const pageKey = "photos_count";
  static const maxPhotos = 24;
  static const _minimumPhotos = 8;

  static const _ducky = Rect.fromLTWH(90, 191, 210, 234);
  static const _burstPivot = Offset(195, 457);
  static const _cloud = Color(0xFFFFF4DC);

  final int count;
  final List<EnteFile> photos;

  @override
  String get key => pageKey;

  @override
  RewindChrome get chrome => const RewindChrome(
    foreground: RewindColors.cream,
    wordmark: Color(0xFF32302E),
  );

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final number = RewindTextStyles.display(
      95.144,
      color: RewindColors.hotPink,
      height: 0.84,
    );
    Widget big(String text) => RewindOutlinedText(
      text,
      style: number,
      outline: 2.8,
      shadow: const Offset(3.5, 4.2),
    );

    return RewindShareable(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RewindBackdrop(
            color: Color(0xFFF64595),
            pattern: RewindRays(
              Color(0xFFF84F9D),
              center: Offset(207, 623),
              wedge: 10,
              step: 20,
            ),
            grain: 0,
          ),
          RewindStage(
            children: [
              RewindLayer(
                rect: const Rect.fromLTWH(0, 458, 390, 236),
                position: position,
                child: RewindEntrance(
                  preset: RewindPreset.cloud,
                  active: isActive,
                  child: Image.file(
                    RewindAssets.file(RewindAssets.cloudsBack),
                    fit: BoxFit.fill,
                  ),
                ),
              ),
              if (photos.length >= _minimumPhotos)
                Positioned.fill(
                  child: RewindLeave(
                    position: position,
                    centerY: 420,
                    child: _Popcorn(photos: photos, active: isActive),
                  ),
                ),
              RewindLayer(
                rect: _ducky,
                position: position,
                child: RewindKeyframes(
                  active: isActive,
                  delayMs: 850,
                  durationMs: 1050,
                  curve: RewindMotion.hop,
                  hiddenBeforeStart: true,
                  origin: Alignment(
                    (_burstPivot.dx - _ducky.left) / _ducky.width * 2 - 1,
                    (_burstPivot.dy - _ducky.top) / _ducky.height * 2 - 1,
                  ),
                  poses: const [
                    RewindPose(0, dy: 340, sx: 0.94, sy: 1.08),
                    RewindPose(0.5, dy: -46, sx: 0.96, sy: 1.06),
                    RewindPose(0.74, dy: 10, sx: 1.05, sy: 0.95),
                    RewindPose(0.88, dy: -3, sx: 0.99, sy: 1.01),
                    RewindPose(1),
                  ],
                  child: Image.file(
                    RewindAssets.file(RewindAssets.heroDucky),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              RewindLayer(
                rect: const Rect.fromLTWH(0, 511, 390, 333),
                position: position,
                child: RewindEntrance(
                  preset: RewindPreset.cloud,
                  active: isActive,
                  delayMs: 90,
                  child: Stack(
                    clipBehavior: Clip.none,
                    fit: StackFit.expand,
                    children: [
                      Image.file(
                        RewindAssets.file(RewindAssets.cloudsFront),
                        fit: BoxFit.fill,
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 332,
                        height: RewindStage.size.height,
                        child: const ColoredBox(color: _cloud),
                      ),
                    ],
                  ),
                ),
              ),
              RewindLayer(
                rect: const Rect.fromLTWH(41, 79, 320.5, 110),
                position: position,
                child: RewindEntrance(
                  preset: RewindPreset.rise,
                  active: isActive,
                  delayMs: 150,
                  child: Transform.rotate(
                    angle: -3.31 * pi / 180,
                    child: RewindFitWidth(
                      width: 316,
                      alignment: Alignment.center,
                      child: RewindOutlinedText(
                        "YOU SAID\n\"ONE MORE PHOTO\"\nA LOT THIS YEAR.",
                        style: RewindTextStyles.display(
                          34.638,
                          color: RewindColors.white,
                          height: 0.84,
                        ),
                        outline: 2,
                        shadow: const Offset(1.273, 1.528),
                      ),
                    ),
                  ),
                ),
              ),
              RewindLayer(
                rect: const Rect.fromLTWH(0, 589, 390, 21),
                position: position,
                child: RewindEntrance(
                  preset: RewindPreset.line,
                  active: isActive,
                  delayMs: 1250,
                  child: Center(
                    child: Text(
                      "IN ${RewindEdition.year}, YOU CLICKED",
                      style: RewindTextStyles.display(
                        22,
                        color: RewindColors.ink,
                        letterSpacing: -0.88,
                      ),
                    ),
                  ),
                ),
              ),
              RewindLayer(
                rect: const Rect.fromLTWH(40, 612, 310, 140),
                position: position,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: RewindFitWidth(
                    width: 310,
                    alignment: Alignment.topCenter,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 6, right: 7),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 170),
                            child: RewindEntrance(
                              preset: RewindPreset.slap,
                              active: isActive,
                              delayMs: 1400,
                              child: Stack(
                                alignment: Alignment.centerRight,
                                children: [
                                  Opacity(
                                    opacity: 0,
                                    child: big(rewindCount(count)),
                                  ),
                                  RewindCountUp(
                                    value: count,
                                    active: isActive,
                                    delayMs: 1450,
                                    builder: (context, text) => big(text),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 66,
                          child: RewindEntrance(
                            preset: RewindPreset.pop,
                            active: isActive,
                            delayMs: 1700,
                            child: Transform.rotate(
                              angle: -1.7 * pi / 180,
                              child: RewindOutlinedText(
                                count == 1 ? "memory" : "memories",
                                style: RewindTextStyles.display(
                                  44.228,
                                  color: RewindColors.white,
                                  letterSpacing: -1.77,
                                ),
                                outline: 4,
                                ink: const Color(0xFF0A0A0A),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _sparkle(
                const Rect.fromLTWH(51, 577, 32.6, 32.6),
                21.9,
                1850,
                position,
                isActive,
              ),
              _sparkle(
                const Rect.fromLTWH(344, 664, 19.7, 19.7),
                65.7,
                1950,
                position,
                isActive,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sparkle(
    Rect rect,
    double turn,
    int delayMs,
    double position,
    bool isActive,
  ) {
    return RewindLayer(
      rect: rect,
      position: position,
      child: RewindEntrance(
        preset: RewindPreset.twinkle,
        active: isActive,
        delayMs: delayMs,
        child: RewindIdleLoop(
          idle: RewindIdle.twinkle,
          active: isActive,
          delayMs: delayMs + 700,
          child: Transform.rotate(
            angle: turn * pi / 180,
            child: SvgPicture.file(
              RewindAssets.file(RewindAssets.whiteSparkle),
            ),
          ),
        ),
      ),
    );
  }
}

class _Popcorn extends StatelessWidget {
  const _Popcorn({required this.photos, required this.active});

  static const _launchY = 650.0;
  static const _flightMs = 1750.0;
  static const _burstFromMs = 1420.0;
  static const _burstMs = 1400.0;
  static const _burstCount = 16;
  static const _belted = 5;
  static const _firstBelted = _burstCount - _belted;
  static const _width = 74.0;
  static const _beltY = 472.0;
  static const _beltLeft = 54.0;
  static const _pitch = 78.0;
  static const _beltSpeed = 0.04;
  static const _landMs = 280.0;

  static final List<double> _burst = [
    for (var k = 0; k < _burstCount; k++)
      _burstFromMs +
          _burstMs * (1 - pow(1 - k / _burstCount, 1 / 3).toDouble()),
  ];

  static final _beltFromMs = _burst[_firstBelted] + _flightMs;

  final List<EnteFile> photos;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final prints = [
      for (final file in photos)
        RewindPolaroid(
          width: _width,
          photo: RewindPhoto(
            file,
            placeholder: const Color(0x1F151515),
            zoomable: false,
          ),
        ),
    ];
    return IgnorePointer(
      child: RewindElapsed(
        active: active,
        stillMs: 5200,
        builder: (context, ms) => Stack(
          clipBehavior: Clip.none,
          children: [
            for (final slot in _beltSlots(ms))
              _onBelt(prints[(_firstBelted + slot) % prints.length], slot, ms),
            for (var k = 0; k < _burstCount; k++)
              if (_burst[k] <= ms && ms < _burst[k] + _flightMs)
                _flight(prints[k % prints.length], k, ms),
          ],
        ),
      ),
    );
  }

  double _beltX(int slot, double ms) =>
      _beltLeft + slot * _pitch - _beltSpeed * (ms - _beltFromMs);

  Offset _beltAt(int slot, double ms) {
    final x = _beltX(slot, ms);
    return Offset(x, _beltY + 4 * sin(x / 128 * 2 * pi));
  }

  double _beltTilt(double x) => 3.5 * cos(x / 128 * 2 * pi) + 1.5;

  Iterable<int> _beltSlots(double ms) sync* {
    final first = max(
      0,
      ((_beltSpeed * (ms - _beltFromMs) - _beltLeft - _width) / _pitch).ceil(),
    );
    for (var slot = first; ; slot++) {
      if (_beltX(slot, ms) - _width > RewindStage.size.width) return;
      final landed = slot >= _belted || ms >= _landingMs(slot);
      if (landed) yield slot;
    }
  }

  double _landingMs(int slot) => _burst[_firstBelted + slot] + _flightMs;

  Widget _onBelt(Widget print, int slot, double ms) {
    final at = _beltAt(slot, ms);
    final since = slot < _belted ? ms - _landingMs(slot) : _landMs;
    final squash = since < _landMs ? sin(since / _landMs * pi) : 0.0;
    return _placed(
      print,
      launch: slot + 1000,
      at: at,
      turn: _beltTilt(at.dx),
      sx: 1 + 0.06 * squash,
      sy: 1 - 0.09 * squash,
    );
  }

  Widget _flight(Widget print, int launch, double ms) {
    final u = (ms - _burst[launch]) / _flightMs;
    final lane = (launch * 0.381966 + 0.13) % 1;
    final side = lane < 0.5 ? -1 : 1;
    final from = Offset(195 + (lane - 0.5) * 140, _launchY);
    final slot = launch - _firstBelted;
    final belted = slot >= 0;
    final to = belted
        ? _beltAt(slot, _landingMs(slot))
        : from + Offset(side * (70 + 90 * _unit(launch)), 0);
    final apex = 195 + 150 * _unit(launch + 7);
    final mid = (from.dy + to.dy) / 2;
    final q = belted ? Curves.easeOut.transform(u) : u;
    final x = from.dx + (to.dx - from.dx) * q;
    final y = from.dy + (to.dy - from.dy) * u - 4 * (mid - apex) * u * (1 - u);
    final spin = side * (8 + 50 * _unit(launch + 11)) + (lane - 0.5) * 30;
    final scale = 0.84 + 0.26 * _unit(launch + 3);
    return _placed(
      print,
      launch: belted ? 1000 + slot : launch,
      at: Offset(x, y),
      turn: belted ? spin + (_beltTilt(to.dx) - spin) * u : spin * u,
      sx: belted ? scale + (1 - scale) * u : scale,
      sy: belted ? scale + (1 - scale) * u : scale,
    );
  }

  Widget _placed(
    Widget print, {
    required int launch,
    required Offset at,
    required double turn,
    required double sx,
    required double sy,
  }) {
    return Positioned(
      key: ValueKey(launch),
      left: at.dx - _width / 2,
      top: at.dy - _width * 0.6,
      child: Transform(
        alignment: Alignment.bottomCenter,
        transform: Matrix4.identity()
          ..rotateZ(turn * pi / 180)
          ..scaleByDouble(sx, sy, 1, 1),
        child: print,
      ),
    );
  }

  static double _unit(int n) {
    final v = sin(n * 12.9898 + 78.233) * 43758.5453;
    return v - v.floorToDouble();
  }
}
