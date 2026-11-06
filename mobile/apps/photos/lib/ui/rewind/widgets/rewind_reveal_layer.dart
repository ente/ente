import "package:flutter/widgets.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";

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
