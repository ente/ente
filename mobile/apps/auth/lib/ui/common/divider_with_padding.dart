import 'package:flutter/material.dart';

class DividerWithPadding extends StatelessWidget {
  final double left, top, right, bottom, thinckness;
  const DividerWithPadding({
    super.key,
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
    this.thinckness = 0.5,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(left, top, right, bottom),
      child: Divider(thickness: thinckness),
    );
  }
}
