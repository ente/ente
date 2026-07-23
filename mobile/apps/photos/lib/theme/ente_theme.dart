import 'package:flutter/material.dart';
import 'package:photos/ente_theme_data.dart';
import 'package:photos/theme/colors.dart';
import 'package:photos/theme/effects.dart';
import 'package:photos/theme/text_style.dart';

class EnteTheme {
  final EnteTextTheme textTheme;
  final EnteColorScheme colorScheme;
  final List<BoxShadow> shadowFloat;
  final List<BoxShadow> shadowMenu;
  final List<BoxShadow> shadowButton;

  const EnteTheme(
    this.textTheme,
    this.colorScheme, {
    required this.shadowFloat,
    required this.shadowMenu,
    required this.shadowButton,
  });

  static bool isDark(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }
}

EnteTheme lightTheme = EnteTheme(
  lightTextTheme,
  lightScheme,
  shadowFloat: shadowFloatLight,
  shadowMenu: shadowMenuLight,
  shadowButton: shadowButtonLight,
);

EnteTheme darkTheme = EnteTheme(
  darkTextTheme,
  darkScheme,
  shadowFloat: shadowFloatDark,
  shadowMenu: shadowMenuDark,
  shadowButton: shadowButtonDark,
);

EnteColorScheme getEnteColorScheme(
  BuildContext context, {
  bool inverse = false,
}) {
  return inverse
      ? Theme.of(context).colorScheme.inverseEnteTheme.colorScheme
      : Theme.of(context).colorScheme.enteTheme.colorScheme;
}

EnteTextTheme getEnteTextTheme(BuildContext context, {bool inverse = false}) {
  return inverse
      ? Theme.of(context).colorScheme.inverseEnteTheme.textTheme
      : Theme.of(context).colorScheme.enteTheme.textTheme;
}
