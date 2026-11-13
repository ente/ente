import 'package:ente_ui/theme/colors.dart';
import 'package:ente_ui/theme/ente_theme.dart';
import 'package:flutter/material.dart';

enum GradientButtonType { primary, secondary, critical }

class GradientButton extends StatelessWidget {
  final VoidCallback? onTap;
  final String text;
  final IconData? icon;
  final double paddingValue;
  final GradientButtonType buttonType;

  const GradientButton({
    super.key,
    this.onTap,
    this.text = '',
    this.icon,
    this.paddingValue = 6.0,
    this.buttonType = GradientButtonType.primary,
  });

  static const TextStyle _textStyle = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.w600,
    fontFamily: 'Inter-SemiBold',
    fontSize: 18,
  );

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final bool isEnabled = onTap != null;

    final Color effectiveBackgroundColor = _getBackgroundColor(
      colorScheme,
      isEnabled,
    );
    final Color effectiveTextColor = _getTextColor(colorScheme, isEnabled);

    final TextStyle effectiveTextStyle = _textStyle.copyWith(
      color: effectiveTextColor,
    );

    final Widget textWidget = Text(text, style: effectiveTextStyle);

    final Widget content = (icon != null)
        ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: effectiveTextColor),
              Padding(padding: EdgeInsets.symmetric(horizontal: paddingValue)),
              if (text.isNotEmpty) textWidget,
            ],
          )
        : textWidget;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Material(
        color: effectiveBackgroundColor,
        child: InkWell(
          onTap: onTap,
          splashColor: isEnabled ? null : Colors.transparent,
          highlightColor: isEnabled ? null : Colors.transparent,
          child: SizedBox(height: 56, child: Center(child: content)),
        ),
      ),
    );
  }

  Color _getBackgroundColor(EnteColorScheme colorScheme, bool isEnabled) {
    if (!isEnabled) {
      return colorScheme.fillFaint;
    }
    switch (buttonType) {
      case GradientButtonType.primary:
        return colorScheme.primary700;
      case GradientButtonType.secondary:
        return colorScheme.backdropBase;
      case GradientButtonType.critical:
        return colorScheme.warning700;
    }
  }

  Color _getTextColor(EnteColorScheme colorScheme, bool isEnabled) {
    if (!isEnabled) {
      return colorScheme.textMuted;
    }
    switch (buttonType) {
      case GradientButtonType.primary:
        return Colors.white;
      case GradientButtonType.secondary:
        return colorScheme.textBase;
      case GradientButtonType.critical:
        return Colors.white;
    }
  }
}
