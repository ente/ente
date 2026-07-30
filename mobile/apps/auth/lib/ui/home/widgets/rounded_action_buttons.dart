import 'package:ente_auth/theme/colors.dart';
import 'package:ente_auth/theme/ente_theme.dart';
import 'package:flutter/material.dart';

enum RoundedButtonType { primary, secondary, primaryInverse, secondaryInverse }

class RoundedButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final double? width;
  final RoundedButtonType type;

  const RoundedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.width,
    this.type = RoundedButtonType.primary,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    final colorScheme = getEnteColorScheme(context);
    final isDarkTheme = !colorScheme.isLightTheme;

    final (backgroundColor, textColor) = switch (type) {
      RoundedButtonType.primary => (accentColor, Colors.white),
      RoundedButtonType.secondary => (
        isDarkTheme ? const Color(0x29A75CFF) : const Color(0x0AA75CFF),
        colorScheme.textBase,
      ),
      RoundedButtonType.primaryInverse => (Colors.white, accentColor),
      RoundedButtonType.secondaryInverse => (
        Colors.white.withValues(alpha: 0.2),
        Colors.white,
      ),
    };

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: width,
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
        decoration: ShapeDecoration(
          color: backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: textTheme.small.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
