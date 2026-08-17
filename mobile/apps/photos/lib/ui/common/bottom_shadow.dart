import 'package:flutter/material.dart';

class BottomShadowWidget extends StatelessWidget {
  final double offsetDy;
  final Color? shadowColor;
  const BottomShadowWidget({this.offsetDy = 28, this.shadowColor, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: Colors.transparent,
        boxShadow: [
          BoxShadow(
            color: shadowColor ?? Theme.of(context).colorScheme.surface,
            spreadRadius: 42,
            blurRadius: 42,
            offset: Offset(0, offsetDy),
          ),
        ],
      ),
    );
  }
}
