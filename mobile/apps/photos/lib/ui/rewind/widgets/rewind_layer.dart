import "package:flutter/widgets.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";

class RewindLayer extends StatelessWidget {
  const RewindLayer({
    required this.rect,
    required this.position,
    required this.child,
    super.key,
  });

  final Rect rect;
  final double position;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned.fromRect(
      rect: rect,
      child: RewindLeave(
        position: position,
        centerY: rect.center.dy,
        child: child,
      ),
    );
  }
}
