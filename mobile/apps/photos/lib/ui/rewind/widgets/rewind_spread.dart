import "package:flutter/widgets.dart";

class RewindSpread extends StatelessWidget {
  const RewindSpread({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        for (final side in const [-1.0, 1.0])
          Positioned.fill(
            child: FractionalTranslation(
              translation: Offset(side, 0),
              child: Transform.flip(flipX: true, child: child),
            ),
          ),
        child,
      ],
    );
  }
}
