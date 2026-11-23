import "dart:math";

import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_page_scope.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_motion.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_count_up.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_keyframes.dart";
import "package:photos/ui/rewind/widgets/rewind_layer.dart";
import "package:photos/ui/rewind/widgets/rewind_numbers.dart";
import "package:photos/ui/rewind/widgets/rewind_rive.dart";
import "package:photos/ui/rewind/widgets/rewind_spread.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

class PhotosCountPage extends RewindPage {
  const PhotosCountPage(this.count);

  static const pageKey = "photos_count";

  static const _ducky = Rect.fromLTWH(49, 174.5, 288.3, 290.2);
  static const _duckyPivot = Offset(195, 457);
  static const _cloud = Color(0xFFFFF4DC);

  final int count;

  @override
  String get key => pageKey;

  @override
  Duration? get reelHold =>
      const Duration(milliseconds: 2800 + RewindMotion.reelReadingMs);

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
    final covered = RewindPageScope.coveredOf(context);
    final playing = isActive && !covered;
    final launched =
        (isActive || (position < 0 && position > -0.9)) && !covered;

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
                  active: launched,
                  child: RewindSpread(
                    child: Image.file(
                      RewindAssets.file(RewindAssets.cloudsBack),
                      fit: BoxFit.fill,
                    ),
                  ),
                ),
              ),
              RewindLayer(
                rect: _ducky,
                position: position,
                child: RewindKeyframes(
                  active: launched,
                  delayMs: 380,
                  durationMs: 1350,
                  curve: RewindMotion.hop,
                  hiddenBeforeStart: true,
                  origin: Alignment(
                    (_duckyPivot.dx - _ducky.left) / _ducky.width * 2 - 1,
                    (_duckyPivot.dy - _ducky.top) / _ducky.height * 2 - 1,
                  ),
                  poses: const [
                    RewindPose(0, dy: 340, sx: 0.94, sy: 1.08),
                    RewindPose(0.5, dy: -46, sx: 0.96, sy: 1.06),
                    RewindPose(0.74, dy: 10, sx: 1.05, sy: 0.95),
                    RewindPose(0.88, dy: -3, sx: 0.99, sy: 1.01),
                    RewindPose(1),
                  ],
                  child: const RewindDucky(RewindAssets.superheroDucky),
                ),
              ),
              RewindLayer(
                rect: const Rect.fromLTWH(0, 511, 390, 333),
                position: position,
                child: RewindEntrance(
                  preset: RewindPreset.cloud,
                  active: launched,
                  delayMs: 90,
                  child: Stack(
                    clipBehavior: Clip.none,
                    fit: StackFit.expand,
                    children: [
                      RewindSpread(
                        child: Image.file(
                          RewindAssets.file(RewindAssets.cloudsFront),
                          fit: BoxFit.fill,
                        ),
                      ),
                      Positioned(
                        left: -RewindStage.size.width,
                        right: -RewindStage.size.width,
                        top: 332,
                        height: RewindStage.size.height,
                        child: const ColoredBox(color: _cloud),
                      ),
                    ],
                  ),
                ),
              ),
              RewindLayer(
                rect: const Rect.fromLTWH(0, 589, 390, 21),
                position: position,
                child: RewindEntrance(
                  preset: RewindPreset.line,
                  active: isActive,
                  delayMs: 700,
                  child: Center(
                    child: RewindVoice(
                      you: "IN ${RewindEdition.year}, YOU CLICKED",
                      me: "IN ${RewindEdition.year}, I CLICKED",
                      builder: (text) => Text(
                        text,
                        style: RewindTextStyles.display(
                          22,
                          color: RewindColors.ink,
                          letterSpacing: -0.88,
                        ),
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
                              delayMs: 850,
                              child: Stack(
                                alignment: Alignment.centerRight,
                                children: [
                                  Opacity(
                                    opacity: 0,
                                    child: big(rewindCount(count)),
                                  ),
                                  RewindCountUp(
                                    value: count,
                                    active: playing,
                                    delayMs: 900,
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
                            delayMs: 1150,
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
