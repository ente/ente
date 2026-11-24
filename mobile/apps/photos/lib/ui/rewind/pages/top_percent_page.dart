import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_motion.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_layer.dart";
import "package:photos/ui/rewind/widgets/rewind_numbers.dart";
import "package:photos/ui/rewind/widgets/rewind_rive.dart";
import "package:photos/ui/rewind/widgets/rewind_spread.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

class TopPercentPage extends RewindPage {
  const TopPercentPage({required this.percent, required this.count});

  static const pageKey = "top_percent";

  static const _night = Color(0xFF1A2A8F);
  static const _crowd = Size(390, 540);
  static const _textDelayMs = 900;

  final int percent;
  final int count;

  @override
  String get key => pageKey;

  @override
  Duration? get reelHold =>
      const Duration(milliseconds: 2700 + RewindMotion.reelReadingMs);

  @override
  List<EnteFile> get reelThumbnails => const [];

  ({String trigger, Rect heroes}) get _variant => switch (percent) {
    1 => (trigger: "top1", heroes: const Rect.fromLTRB(134, 142, 260, 251)),
    <= 10 => (trigger: "top10", heroes: const Rect.fromLTRB(68, 137, 314, 266)),
    _ => (trigger: "top25", heroes: const Rect.fromLTRB(68, 100, 314, 267)),
  };

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final small = percent >= 10;
    final variant = _variant;
    return RewindShareable(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final wide = size.aspectRatio > RewindStage.size.aspectRatio;
          return Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: _night),
              RewindStage(
                children: [
                  RewindLayer(
                    rect: Offset.zero & _crowd,
                    position: position,
                    child: RewindSpread(
                      mirror: wide
                          ? const RewindDucky(
                              RewindAssets.topPercent,
                              stateMachine: "Top",
                            )
                          : const SizedBox.shrink(),
                      child: RewindDucky(
                        RewindAssets.topPercent,
                        stateMachine: "Top",
                        play: variant.trigger,
                        active: isActive,
                        tap: (trigger: "tap", area: variant.heroes),
                      ),
                    ),
                  ),
                  RewindLayer(
                    rect: Rect.fromLTWH(25.8, small ? 558 : 564, 244, 30),
                    position: position,
                    child: RewindEntrance(
                      preset: RewindPreset.line,
                      active: isActive,
                      delayMs: _textDelayMs,
                      child: Center(
                        child: RewindVoice(
                          you: "ACROSS ENTE, YOU’RE IN THE",
                          me: "ACROSS ENTE, I’M IN THE",
                          builder: (text) => Text(
                            text,
                            style: RewindTextStyles.display(17, height: 1.05),
                          ),
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
                      delayMs: _textDelayMs + 200,
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
                      delayMs: _textDelayMs + 500,
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
