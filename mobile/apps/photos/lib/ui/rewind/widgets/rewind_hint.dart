import "package:flutter/widgets.dart";
import "package:photos/ui/rewind/shell/rewind_page_scope.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_elapsed.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";

class RewindHintTag extends StatelessWidget {
  const RewindHintTag(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return RewindIdleLoop(
      idle: RewindIdle.pulse,
      active: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 5),
        decoration: BoxDecoration(
          color: RewindColors.hotPink,
          border: Border.all(color: RewindColors.ink, width: 2.5),
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(color: RewindColors.ink, offset: Offset(2.5, 3.5)),
          ],
        ),
        child: Text(text, style: RewindTextStyles.display(13, height: 1.1)),
      ),
    );
  }
}

class RewindHint extends StatelessWidget {
  const RewindHint(
    this.text, {
    required this.centerY,
    required this.active,
    required this.position,
    this.delayMs = 2400,
    this.showMs = 4600,
    super.key,
  });

  final String text;
  final double centerY;
  final bool active;
  final double position;
  final int delayMs;
  final int showMs;

  @override
  Widget build(BuildContext context) {
    if (RewindPageScope.reelOf(context)) return const SizedBox.shrink();
    return IgnorePointer(
      child: RewindElapsed(
        active: active,
        stillMs: 0,
        builder: (context, ms) {
          final shown = ((ms - delayMs) / 260).clamp(0.0, 1.0);
          final leaving = ((delayMs + showMs - ms) / 420).clamp(0.0, 1.0);
          final opacity = active ? shown * leaving : 0.0;
          if (opacity <= 0) return const SizedBox.shrink();
          return RewindStage(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: centerY - 16,
                child: RewindLeave(
                  position: position,
                  centerY: centerY,
                  child: Opacity(
                    opacity: opacity,
                    child: Center(
                      child: Transform.scale(
                        scale: 0.86 + 0.14 * shown,
                        child: RewindHintTag(text),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
