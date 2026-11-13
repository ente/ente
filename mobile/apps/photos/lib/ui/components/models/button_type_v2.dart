import 'package:flutter/material.dart';
import 'package:photos/theme/colors.dart';

enum ButtonSizeV2 { small, large }

enum ButtonTypeV2 {
  primary,
  secondary,
  neutral,
  critical,
  tertiaryCritical,
  link;

  ButtonTheme getColorPalette(EnteColorScheme colorScheme) {
    switch (this) {
      case ButtonTypeV2.primary:
        return _primaryPalette(colorScheme);
      case ButtonTypeV2.critical:
        return _criticalPalette(colorScheme);
      case ButtonTypeV2.secondary:
        return _secondaryPalette(colorScheme);
      case ButtonTypeV2.neutral:
        return _neutralPalette(colorScheme);
      case ButtonTypeV2.tertiaryCritical:
        return _tertiaryCriticalPalette(colorScheme);
      case ButtonTypeV2.link:
        return _linkPalette(colorScheme);
    }
  }
}

ButtonTheme _primaryPalette(EnteColorScheme c) => ButtonTheme(
  defaultBg: c.greenBase,
  hoverBg: c.greenDark,
  pressedBg: c.greenDarker,
  disabledBg: c.fillDark,
  foreground: Colors.white,
  disabledForeground: c.contentLighter,
);

ButtonTheme _criticalPalette(EnteColorScheme c) => ButtonTheme(
  defaultBg: c.redBase,
  hoverBg: c.redDark,
  pressedBg: c.redDarker,
  disabledBg: c.fillDark,
  foreground: Colors.white,
  disabledForeground: c.contentLighter,
);

ButtonTheme _secondaryPalette(EnteColorScheme c) => ButtonTheme(
  defaultBg: c.greenLight,
  hoverBg: c.fillDarker,
  pressedBg: c.fillDarkest,
  disabledBg: c.fillDark,
  foreground: c.greenBase,
  disabledForeground: c.contentLighter,
  iconColor: c.content,
  disabledIconColor: c.contentLighter,
  checkmarkColor: c.content,
);

ButtonTheme _neutralPalette(EnteColorScheme c) => ButtonTheme(
  defaultBg: c.fillReverse,
  hoverBg: c.fillReverse,
  pressedBg: c.fillReverse,
  disabledBg: c.fillDark,
  foreground: c.contentReverse,
  disabledForeground: c.contentLighter,
  iconColor: c.contentReverse,
  disabledIconColor: c.contentLighter,
  checkmarkColor: c.contentReverse,
);

ButtonTheme _tertiaryCriticalPalette(EnteColorScheme c) => ButtonTheme(
  defaultBg: Colors.transparent,
  hoverBg: Colors.transparent,
  pressedBg: Colors.transparent,
  disabledBg: Colors.transparent,
  foreground: c.redBase,
  hoverForeground: c.redDark,
  pressedForeground: c.redDarker,
  disabledForeground: c.contentLighter,
  disabledIconColor: c.contentLighter,
);

ButtonTheme _linkPalette(EnteColorScheme c) => ButtonTheme(
  defaultBg: Colors.transparent,
  hoverBg: Colors.transparent,
  pressedBg: Colors.transparent,
  disabledBg: Colors.transparent,
  foreground: c.greenBase,
  hoverForeground: c.greenDark,
  pressedForeground: c.greenDarker,
  disabledForeground: c.contentLighter,
  disabledIconColor: c.contentLighter,
);

class ButtonTheme {
  final Color defaultBg;
  final Color hoverBg;
  final Color pressedBg;
  final Color disabledBg;
  final Color foreground;
  final Color? hoverForeground;
  final Color? pressedForeground;
  final Color disabledForeground;
  final Color? iconColor;
  final Color? disabledIconColor;
  final Color? checkmarkColor;
  final Color? defaultBorder;
  final Color? disabledBorder;

  const ButtonTheme({
    required this.defaultBg,
    required this.hoverBg,
    required this.pressedBg,
    required this.disabledBg,
    required this.foreground,
    this.hoverForeground,
    this.pressedForeground,
    required this.disabledForeground,
    this.iconColor,
    this.disabledIconColor,
    this.checkmarkColor,
    this.defaultBorder,
    this.disabledBorder,
  });

  ButtonColors resolve({
    required bool isDisabled,
    required bool isPressed,
    required bool isHovered,
    required bool isLoading,
    required bool isSuccess,
    Color? iconColorOverride,
  }) {
    if (isDisabled) {
      return ButtonColors(
        backgroundColor: disabledBg,
        borderColor: disabledBorder,
        textColor: disabledForeground,
        iconColor: iconColorOverride ?? disabledIconColor ?? disabledForeground,
        spinnerColor: disabledIconColor ?? disabledForeground,
        checkmarkColor: disabledIconColor ?? disabledForeground,
      );
    }

    if (isLoading) {
      return ButtonColors(
        backgroundColor: pressedBg,
        borderColor: defaultBorder,
        textColor: pressedForeground ?? foreground,
        iconColor:
            iconColorOverride ?? iconColor ?? pressedForeground ?? foreground,
        spinnerColor: iconColor ?? pressedForeground ?? foreground,
        checkmarkColor: checkmarkColor ?? iconColor ?? foreground,
      );
    }

    if (isSuccess) {
      return ButtonColors(
        backgroundColor: defaultBg,
        borderColor: defaultBorder,
        textColor: foreground,
        iconColor: iconColorOverride ?? iconColor ?? foreground,
        spinnerColor: iconColor ?? foreground,
        checkmarkColor: checkmarkColor ?? iconColor ?? foreground,
      );
    }

    final Color bg;
    final Color fg;
    if (isPressed) {
      bg = pressedBg;
      fg = pressedForeground ?? foreground;
    } else if (isHovered) {
      bg = hoverBg;
      fg = hoverForeground ?? foreground;
    } else {
      bg = defaultBg;
      fg = foreground;
    }

    return ButtonColors(
      backgroundColor: bg,
      borderColor: defaultBorder,
      textColor: fg,
      iconColor: iconColorOverride ?? iconColor ?? fg,
      spinnerColor: iconColor ?? fg,
      checkmarkColor: checkmarkColor ?? iconColor ?? fg,
    );
  }
}

class ButtonColors {
  final Color backgroundColor;
  final Color? borderColor;
  final Color textColor;
  final Color iconColor;
  final Color spinnerColor;
  final Color checkmarkColor;

  const ButtonColors({
    required this.backgroundColor,
    this.borderColor,
    required this.textColor,
    required this.iconColor,
    required this.spinnerColor,
    required this.checkmarkColor,
  });
}
