import "package:flutter/widgets.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_svg.dart";
import "package:photos/ui/rewind/widgets/rewind_year_duckies.dart";

class OutroPage extends RewindPage {
  const OutroPage();

  static const _hold = Duration(seconds: 3);

  @override
  String get key => "outro";

  @override
  RewindChrome get chrome => const RewindChrome(
    foreground: RewindColors.cream,
    wordmark: Color(0x00FFFFFF),
  );

  @override
  Duration get reelHold => _hold;

  @override
  Duration get clipHold => _hold;

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final launched = isActive || (position < 0 && position > -0.9);
    return _OutroCard(launched: launched);
  }
}

class _OutroCard extends StatelessWidget {
  const _OutroCard({required this.launched});

  final bool launched;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const RewindBackdrop(
          color: RewindColors.green,
          pattern: RewindStripes(Color(0xFF0EBF29)),
        ),
        RewindStage(
          children: [
            const Positioned(
              left: -109.63,
              top: -98.75,
              child: RewindSvg(RewindAssets.finaleRays),
            ),
            Positioned(
              left: 47,
              top: 135.02,
              width: 296,
              child: _enter(
                RewindPreset.rise,
                0,
                Text(
                  "YOUR YEAR.\nYOUR REWIND.",
                  textAlign: TextAlign.center,
                  softWrap: false,
                  style: RewindTextStyles.display(44.233),
                ),
              ),
            ),
            Positioned(
              left: 176,
              top: 219,
              width: 147,
              height: 12,
              child: _enter(
                RewindPreset.line,
                250,
                const RewindSvg(RewindAssets.outroUnderline),
              ),
            ),
            Positioned.fromRect(
              rect: Rect.fromCenter(
                center: const Offset(194.5, 309.5),
                width: 296,
                height: 29,
              ),
              child: _enter(
                RewindPreset.line,
                350,
                Center(
                  child: Text(
                    "Make yours with",
                    softWrap: false,
                    style: RewindTextStyles.body(
                      26,
                      color: RewindColors.outline,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 89,
              top: 340,
              width: 212,
              height: 113,
              child: _enter(
                RewindPreset.pop,
                450,
                const RewindSvg(RewindAssets.outroLockup),
              ),
            ),
            Positioned(
              left: 29.736,
              top: 520,
              child: _enter(
                RewindPreset.line,
                600,
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Image.file(
                      RewindAssets.file(RewindAssets.googlePlayBadge),
                      width: 166.949,
                      height: 49.73,
                    ),
                    const SizedBox(width: 14),
                    const SizedBox(
                      width: 149.58,
                      height: 50,
                      child: RewindSvg(RewindAssets.appStoreBadge),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const RewindYearDuckies(),
      ],
    );
  }

  Widget _enter(RewindPreset preset, int delayMs, Widget child) {
    return RewindEntrance(
      preset: preset,
      active: launched,
      delayMs: delayMs,
      child: child,
    );
  }
}
