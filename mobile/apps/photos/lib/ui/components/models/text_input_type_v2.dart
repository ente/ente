import 'package:flutter/material.dart';
import 'package:photos/theme/colors.dart';

enum TextInputMessageType { guide, error, alert, success }

class TextInputTheme {
  final Color defaultBg;
  final Color focusedBg;
  final Color disabledBg;
  final Color errorBg;

  final Color defaultBorder;
  final Color focusedBorder;
  final Color errorBorder;
  final Color successBorder;

  final Color textColor;
  final Color hintColor;
  final Color disabledTextColor;
  final Color labelColor;
  final Color iconColor;

  final Color errorColor;
  final Color successColor;

  const TextInputTheme({
    required this.defaultBg,
    required this.focusedBg,
    required this.disabledBg,
    required this.errorBg,
    required this.defaultBorder,
    required this.focusedBorder,
    required this.errorBorder,
    required this.successBorder,
    required this.textColor,
    required this.hintColor,
    required this.disabledTextColor,
    required this.labelColor,
    required this.iconColor,
    required this.errorColor,
    required this.successColor,
  });

  TextInputColors resolve({
    required bool enableFillColor,
    required bool isDisabled,
    required bool isFocused,
    required bool isError,
    required bool isSuccess,
    required TextInputMessageType messageType,
  }) {
    final Color backgroundColor;
    if (!enableFillColor) {
      backgroundColor = Colors.transparent;
    } else if (isDisabled) {
      backgroundColor = disabledBg;
    } else if (isError) {
      backgroundColor = errorBg;
    } else if (isFocused) {
      backgroundColor = focusedBg;
    } else {
      backgroundColor = defaultBg;
    }

    final Color borderColor;
    if (isError) {
      borderColor = errorBorder;
    } else if (isSuccess) {
      borderColor = successBorder;
    } else if (isDisabled) {
      borderColor = defaultBorder;
    } else if (isFocused) {
      borderColor = focusedBorder;
    } else {
      borderColor = defaultBorder;
    }

    final Color resolvedTextColor = isDisabled ? disabledTextColor : textColor;
    final Color resolvedHintColor = isDisabled ? disabledTextColor : hintColor;
    final Color resolvedIconColor = isDisabled ? disabledTextColor : iconColor;

    final Color messageColor = switch (messageType) {
      TextInputMessageType.error || TextInputMessageType.alert => errorColor,
      TextInputMessageType.success => successColor,
      TextInputMessageType.guide => hintColor,
    };

    return TextInputColors(
      backgroundColor: backgroundColor,
      borderColor: borderColor,
      textColor: resolvedTextColor,
      hintColor: resolvedHintColor,
      labelColor: labelColor,
      iconColor: resolvedIconColor,
      messageColor: messageColor,
    );
  }
}

class TextInputColors {
  final Color backgroundColor;
  final Color borderColor;
  final Color textColor;
  final Color hintColor;
  final Color labelColor;
  final Color iconColor;
  final Color messageColor;

  const TextInputColors({
    required this.backgroundColor,
    required this.borderColor,
    required this.textColor,
    required this.hintColor,
    required this.labelColor,
    required this.iconColor,
    required this.messageColor,
  });
}

TextInputTheme buildTextInputTheme(EnteColorScheme colorScheme) {
  return TextInputTheme(
    defaultBg: colorScheme.fill,
    focusedBg: colorScheme.fill,
    disabledBg: colorScheme.fill,
    errorBg: colorScheme.fill,
    defaultBorder: colorScheme.strokeSolid,
    focusedBorder: colorScheme.greenBase,
    errorBorder: colorScheme.redBase,
    successBorder: colorScheme.greenBase,
    textColor: colorScheme.content,
    hintColor: colorScheme.contentLighter,
    disabledTextColor: colorScheme.contentLightest,
    labelColor: colorScheme.content,
    iconColor: colorScheme.contentLighter,
    errorColor: colorScheme.redBase,
    successColor: colorScheme.greenBase,
  );
}
