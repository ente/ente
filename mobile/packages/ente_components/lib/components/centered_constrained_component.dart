import 'package:flutter/widgets.dart';

class CenteredConstrainedComponent extends StatelessWidget {
  const CenteredConstrainedComponent({
    required this.child,
    this.maxWidth = 700,
    super.key,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
