import "package:flutter/material.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_motion.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_keyframes.dart";
import "package:photos/ui/rewind/widgets/rewind_layer.dart";
import "package:photos/ui/rewind/widgets/rewind_numbers.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

class TopPercentPage extends RewindPage {
  const TopPercentPage({required this.percent, required this.count});

  static const pageKey = "top_percent";

  static const _base = Color(0xFF5666CC);
  static const _night = Color(0xFF1A2A8F);

  final int percent;
  final int count;

  @override
  String get key => pageKey;

  _Crowd get _crowd => percent <= 1 ? _Crowd.top1 : _Crowd.wide;

  List<(String, Rect)> get _heroes => switch (percent) {
    <= 1 => const [
      (RewindAssets.crowdHeroTop1, Rect.fromLTWH(141, 152, 113, 118)),
    ],
    <= 10 => const [
      (RewindAssets.crowdHeroLeft, Rect.fromLTWH(78, 188, 82, 112)),
      (RewindAssets.crowdHeroMiddle, Rect.fromLTWH(139, 188, 98, 112)),
      (RewindAssets.crowdHeroRight, Rect.fromLTWH(223, 183, 88, 113)),
    ],
    _ => const [
      (RewindAssets.crowdHeroBackLeft, Rect.fromLTWH(111, 138, 99, 110)),
      (RewindAssets.crowdHeroBackRight, Rect.fromLTWH(190, 138, 93, 112)),
      (RewindAssets.crowdHeroLeft, Rect.fromLTWH(78, 188, 82, 112)),
      (RewindAssets.crowdHeroMiddle, Rect.fromLTWH(139, 188, 98, 112)),
      (RewindAssets.crowdHeroRight, Rect.fromLTWH(223, 183, 88, 113)),
    ],
  };

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final crowd = _crowd;
    final heroes = _heroes;
    final textDelay = 950 + 175 * (heroes.length - 1);
    final small = percent > 1;
    return RewindShareable(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final night =
              RewindStage.originFor(size).dy + 420 * RewindStage.scaleFor(size);
          return Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: _base),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: night,
                child: RewindLeave(
                  position: position,
                  centerY: 200,
                  child: const ColoredBox(color: _night),
                ),
              ),
              RewindStage(
                children: [
                  RewindLayer(
                    rect: crowd.back,
                    position: position,
                    child: Image.file(
                      RewindAssets.file(crowd.backAsset),
                      fit: BoxFit.fill,
                    ),
                  ),
                  for (final (i, (asset, rect)) in heroes.indexed)
                    RewindLayer(
                      rect: rect,
                      position: position,
                      child: RewindKeyframes(
                        active: isActive,
                        delayMs: 350 + 300 * i,
                        durationMs: 780,
                        curve: RewindMotion.hop,
                        hiddenBeforeStart: true,
                        origin: Alignment.bottomCenter,
                        poses: const [
                          RewindPose(0, dy: 84, sx: 0.94, sy: 1.06),
                          RewindPose(0.5, dy: -16, sx: 0.97, sy: 1.04),
                          RewindPose(0.72, dy: 5, sx: 1.04, sy: 0.96),
                          RewindPose(0.88, dy: -2),
                          RewindPose(1),
                        ],
                        child: Image.file(
                          RewindAssets.file(asset),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  RewindLayer(
                    rect: crowd.front,
                    position: position,
                    child: Image.file(
                      RewindAssets.file(crowd.frontAsset),
                      fit: BoxFit.fill,
                    ),
                  ),
                  Positioned.fromRect(
                    rect: Rect.fromLTWH(0, crowd.front.bottom - 193, 390, 206),
                    child: RewindLeave(
                      position: position,
                      centerY: 440,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: [0.012, 0.953],
                            colors: [Color(0x001A2A8F), _base],
                          ),
                        ),
                      ),
                    ),
                  ),
                  RewindLayer(
                    rect: Rect.fromLTWH(25.8, small ? 558 : 564, 244, 30),
                    position: position,
                    child: RewindEntrance(
                      preset: RewindPreset.line,
                      active: isActive,
                      delayMs: textDelay,
                      child: Center(
                        child: Text(
                          "ACROSS ENTE, YOU’RE IN THE",
                          style: RewindTextStyles.display(17, height: 1.05),
                        ),
                      ),
                    ),
                  ),
                  RewindLayer(
                    rect: Rect.fromLTWH(26, small ? 612 : 602, 340, 82),
                    position: position,
                    child: RewindEntrance(
                      preset: RewindPreset.slap,
                      active: isActive,
                      delayMs: textDelay + 200,
                      origin: Alignment.centerLeft,
                      child: RewindFitWidth(
                        width: 340,
                        child: RewindOutlinedText(
                          "TOP $percent%",
                          style: RewindTextStyles.display(
                            small ? 85 : 95.144,
                            color: const Color(0xFFFFD525),
                            height: 0.84,
                          ),
                          outline: 2.8,
                          shadow: const Offset(3.5, 4.2),
                        ),
                      ),
                    ),
                  ),
                  RewindLayer(
                    rect: Rect.fromLTWH(28, small ? 714 : 700, 316, 52),
                    position: position,
                    child: RewindEntrance(
                      preset: RewindPreset.line,
                      active: isActive,
                      delayMs: textDelay + 500,
                      child: Text(
                        "${rewindCounted(count, "memory", "memories")} saved, "
                        "and counting!",
                        style: RewindTextStyles.body(19, height: 1.32),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _Crowd {
  top1(
    RewindAssets.crowdBackTop1,
    Rect.fromLTWH(0, 0, 390, 296),
    RewindAssets.crowdFrontTop1,
    Rect.fromLTWH(0, 185, 390, 345),
  ),
  wide(
    RewindAssets.crowdBack,
    Rect.fromLTWH(0, 0, 390, 304),
    RewindAssets.crowdFront,
    Rect.fromLTWH(0, 218, 390, 341),
  );

  const _Crowd(this.backAsset, this.back, this.frontAsset, this.front);

  final String backAsset;
  final Rect back;
  final String frontAsset;
  final Rect front;
}
