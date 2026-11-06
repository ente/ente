import "package:flutter/material.dart";
import "package:photos/ui/rewind/widgets/rewind_keyframes.dart";

class RewindSwapIn extends StatelessWidget {
  const RewindSwapIn({
    required this.text,
    required this.child,
    this.alignment = Alignment.center,
    super.key,
  });

  final String text;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RewindKeyframes(
      active: true,
      replay: text,
      durationMs: 320,
      curve: const Cubic(0.2, 0.9, 0.3, 1.25),
      origin: alignment,
      poses: const [
        RewindPose(0, dy: 10, scale: 0.94, opacity: 0),
        RewindPose(1),
      ],
      child: child,
    );
  }
}
