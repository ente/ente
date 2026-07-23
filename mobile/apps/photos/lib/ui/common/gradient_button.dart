import 'package:flutter/material.dart';
import 'package:photos/theme/ente_theme.dart';

class GradientButton extends StatelessWidget {
  final List<Color> linearGradientColors;
  final Function? onTap;

  // text is ignored if child is specified
  final String text;

  // nullable
  final IconData? iconData;

  // padding between the text and icon
  final double paddingValue;

  const GradientButton({
    super.key,
    this.linearGradientColors = const [Color(0xFF2CD267), Color(0xFF1DB954)],
    this.onTap,
    this.text = '',
    this.iconData,
    this.paddingValue = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    Widget buttonContent;
    if (iconData == null) {
      buttonContent = Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter-SemiBold',
          fontSize: 18,
        ),
      );
    } else {
      buttonContent = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(iconData, size: 20, color: Colors.white),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 6)),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontFamily: 'Inter-SemiBold',
              fontSize: 18,
            ),
          ),
        ],
      );
    }
    return InkWell(
      onTap: onTap as void Function()?,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: const Alignment(0.1, -0.9),
            end: const Alignment(-0.6, 0.9),
            colors: onTap != null
                ? linearGradientColors
                : [
                    getEnteColorScheme(context).fillMuted,
                    getEnteColorScheme(context).fillMuted,
                  ],
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(child: buttonContent),
      ),
    );
  }
}
