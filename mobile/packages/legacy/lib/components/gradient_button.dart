import 'package:ente_ui/theme/ente_theme.dart';
import 'package:flutter/material.dart';

class GradientButton extends StatelessWidget {
  final VoidCallback? onTap;
  final String text;
  final IconData? icon;
  final double paddingValue;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? disabledTextColor;
  final double height;
  final TextStyle? textStyle;

  const GradientButton({
    super.key,
    this.onTap,
    this.text = '',
    this.icon,
    this.paddingValue = 6.0,
    this.backgroundColor,
    this.textColor,
    this.disabledTextColor,
    this.height = 56,
    this.textStyle,
  });

  static const TextStyle _textStyle = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.w600,
    fontFamily: 'Inter-SemiBold',
    fontSize: 18.0,
  );

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final bool isEnabled = onTap != null;
    final Color effectiveBackgroundColor =
        backgroundColor ??
        (isEnabled ? colorScheme.primary700 : colorScheme.fillFaint);
    final TextStyle effectiveTextStyle = (textStyle ?? _textStyle).copyWith(
      color: isEnabled
          ? (textColor ?? Colors.white)
          : (disabledTextColor ?? colorScheme.textMuted),
    );

    final Widget textWidget = Text(text, style: effectiveTextStyle);

    final Widget content = (icon != null)
        ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isEnabled
                    ? (textColor ?? Colors.white)
                    : (disabledTextColor ?? colorScheme.textMuted),
              ),
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
          child: SizedBox(
            height: height,
            child: Center(child: content),
          ),
        ),
      ),
    );
  }
}
