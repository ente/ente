import "package:flutter/widgets.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

List<Widget> rewindCaption({
  required String label,
  required String title,
  required String body,
  ({String label, String title, String body})? me,
  required double position,
  required bool active,
  int delayMs = 0,
  double top = 597,
  Color ink = RewindColors.cream,
  double titleSize = 46,
}) => [
  RewindRevealLayer(
    left: 28,
    top: top,
    maxWidth: 316,
    height: 18,
    position: position,
    active: active,
    delayMs: delayMs,
    child: RewindVoice(
      you: label,
      me: me?.label ?? label,
      builder: (text) => Text(
        text,
        style: RewindTextStyles.display(17, color: ink, height: 1.05),
      ),
    ),
  ),
  RewindRevealLayer(
    left: 28,
    top: top + 30,
    height: 40,
    position: position,
    active: active,
    preset: RewindPreset.slap,
    delayMs: delayMs + 200,
    origin: Alignment.centerLeft,
    child: RewindFitWidth(
      width: 322,
      child: RewindVoice(
        you: title,
        me: me?.title ?? title,
        builder: (text) => RewindOutlinedText(
          text,
          style: RewindTextStyles.display(
            titleSize,
            color: RewindColors.white,
            height: 0.84,
            letterSpacing: -0.012 * titleSize,
          ).copyWith(wordSpacing: 0.1 * titleSize),
          shadow: Offset(0.037 * titleSize, 0.044 * titleSize),
        ),
      ),
    ),
  ),
  RewindRevealLayer(
    left: 28,
    top: top + 91,
    width: 334,
    height: 44,
    position: position,
    active: active,
    delayMs: delayMs + 500,
    child: RewindVoice(
      you: body,
      me: me?.body ?? body,
      builder: (text) =>
          Text(text, style: RewindTextStyles.body(17, color: ink)),
    ),
  ),
];

class RewindRevealLayer extends StatelessWidget {
  const RewindRevealLayer({
    required this.left,
    required this.top,
    required this.position,
    required this.active,
    required this.child,
    this.width,
    this.maxWidth,
    this.height = 0,
    this.preset = RewindPreset.line,
    this.delayMs = 0,
    this.origin,
    super.key,
  });

  final double left;
  final double top;
  final double? width;
  final double? maxWidth;
  final double height;
  final double position;
  final bool active;
  final RewindPreset preset;
  final int delayMs;
  final Alignment? origin;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final maxWidth = this.maxWidth;
    return Positioned(
      left: left,
      top: top,
      width: width,
      child: RewindLeave(
        position: position,
        centerY: top + height / 2,
        child: RewindEntrance(
          preset: preset,
          active: active,
          delayMs: delayMs,
          origin: origin,
          child: maxWidth == null
              ? child
              : ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: FittedBox(fit: BoxFit.scaleDown, child: child),
                ),
        ),
      ),
    );
  }
}
