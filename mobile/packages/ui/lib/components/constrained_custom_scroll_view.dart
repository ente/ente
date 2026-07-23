import 'package:flutter/material.dart';

/// A CustomScrollView that is horizontally centered and constrained to a maximum width.
///
/// This widget is useful for creating responsive layouts that look good on both
/// mobile and wider screens (tablets, desktop).
class ConstrainedCustomScrollView extends StatelessWidget {
  final List<Widget> slivers;
  final double maxWidth;
  final bool primary;

  const ConstrainedCustomScrollView({
    required this.slivers,
    this.maxWidth = 700,
    this.primary = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: CustomScrollView(primary: primary, slivers: slivers),
      ),
    );
  }
}
