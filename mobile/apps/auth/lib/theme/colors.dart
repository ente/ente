import 'package:flutter/material.dart';

class EnteColorScheme {
  // Background Colors
  final Color backgroundBase;
  final Color backgroundElevated;
  final Color backgroundElevated2;

  // Backdrop Colors
  final Color backdropBase;
  final Color backdropBaseMute;
  final Color backdropFaint;

  // Text Colors
  final Color textBase;
  final Color textMuted;
  final Color textFaint;

  // Fill Colors
  final Color fillBase;
  final Color fillBasePressed;
  final Color fillMuted;
  final Color fillFaint;
  final Color fillFaintPressed;

  // Stroke Colors
  final Color strokeBase;
  final Color strokeMuted;
  final Color strokeFaint;
  final Color strokeFainter;
  final Color blurStrokeBase;
  final Color blurStrokeFaint;
  final Color blurStrokePressed;

  // Fixed Colors
  final Color primaryGreen;
  final Color primary700;
  final Color primary500;
  final Color primary400;
  final Color primary300;

  final Color iconButtonColor;

  final Color warning700;
  final Color warning500;
  final Color warning400;
  final Color warning800;

  final Color caution500;
  final List<Color> avatarColors;

  // Tags
  final Color tagChipSelectedColor;
  final Color tagChipUnselectedColor;
  final List<Color> tagChipSelectedGradient;
  final List<Color> tagChipUnselectedGradient;
  final Color tagTextUnselectedColor;
  final Color deleteTagIconColor;
  final Color deleteTagTextColor;

  // Code Widget
  final Color errorCodeProgressColor;
  final Color infoIconColor;
  final Color errorCardTextColor;
  final Color deleteCodeTextColor;
  final List<BoxShadow> pinnedCardBoxShadow;
  final Color pinnedBgColor;

  // Gradient Button
  final Color gradientButtonBgColor;
  final List<Color> gradientButtonBgColors;

  bool get isLightTheme => backgroundBase == backgroundBaseLight;

  const EnteColorScheme(
    this.backgroundBase,
    this.backgroundElevated,
    this.backgroundElevated2,
    this.backdropBase,
    this.backdropBaseMute,
    this.backdropFaint,
    this.textBase,
    this.textMuted,
    this.textFaint,
    this.fillBase,
    this.fillBasePressed,
    this.fillMuted,
    this.fillFaint,
    this.fillFaintPressed,
    this.strokeBase,
    this.strokeMuted,
    this.strokeFaint,
    this.strokeFainter,
    this.blurStrokeBase,
    this.blurStrokeFaint,
    this.blurStrokePressed,
    this.avatarColors,
    this.iconButtonColor,
    this.tagChipUnselectedColor,
    this.tagChipSelectedGradient,
    this.tagChipUnselectedGradient,
    this.pinnedBgColor, {
    this.tagChipSelectedColor = _tagChipSelectedColor,
    this.tagTextUnselectedColor = _tagTextUnselectedColor,
    this.deleteTagIconColor = _deleteTagIconColor,
    this.deleteTagTextColor = _deleteTagTextColor,
    this.errorCodeProgressColor = _errorCodeProgressColor,
    this.infoIconColor = _infoIconColor,
    this.errorCardTextColor = _errorCardTextColor,
    this.deleteCodeTextColor = _deleteCodeTextColor,
    this.pinnedCardBoxShadow = _pinnedCardBoxShadow,
    this.gradientButtonBgColor = _gradientButtonBgColor,
    this.gradientButtonBgColors = _gradientButtonBgColors,
    this.primaryGreen = _primaryGreen,
    this.primary700 = _primary700,
    this.primary500 = _primary500,
    this.primary400 = _primary400,
    this.primary300 = _primary300,
    this.warning700 = _warning700,
    this.warning800 = _warning800,
    this.warning500 = _warning500,
    this.warning400 = _warning700,
    this.caution500 = _caution500,
  });
}

const EnteColorScheme lightScheme = EnteColorScheme(
  backgroundBaseLight,
  backgroundElevatedLight,
  backgroundElevated2Light,
  backdropBaseLight,
  backdropMutedLight,
  backdropFaintLight,
  textBaseLight,
  textMutedLight,
  textFaintLight,
  fillBaseLight,
  fillBasePressedLight,
  fillMutedLight,
  fillFaintLight,
  fillFaintPressedLight,
  strokeBaseLight,
  strokeMutedLight,
  strokeFaintLight,
  strokeFainterLight,
  blurStrokeBaseLight,
  blurStrokeFaintLight,
  blurStrokePressedLight,
  avatarLight,
  _iconButtonBrightColor,
  _tagChipUnselectedColorLight,
  _tagChipSelectedGradientLight,
  _tagChipUnselectedGradientLight,
  _pinnedBgColorLight,
);

const EnteColorScheme darkScheme = EnteColorScheme(
  backgroundBaseDark,
  backgroundElevatedDark,
  backgroundElevated2Dark,
  backdropBaseDark,
  backdropMutedDark,
  backdropFaintDark,
  textBaseDark,
  textMutedDark,
  textFaintDark,
  fillBaseDark,
  fillBasePressedDark,
  fillMutedDark,
  fillFaintDark,
  fillFaintPressedDark,
  strokeBaseDark,
  strokeMutedDark,
  strokeFaintDark,
  strokeFainterDark,
  blurStrokeBaseDark,
  blurStrokeFaintDark,
  blurStrokePressedDark,
  avatarDark,
  _iconButtonDarkColor,
  _tagChipUnselectedColorDark,
  _tagChipSelectedGradientDark,
  _tagChipUnselectedGradientDark,
  _pinnedBgColorDark,
);

const accentColor = Color(0xFF8F33D6);

// QR code container background
const Color qrBoxColor = Color.fromRGBO(245, 245, 247, 1);

// Background Colors
const Color backgroundBaseLight = Color.fromRGBO(255, 255, 255, 1);
const Color backgroundElevatedLight = Color.fromRGBO(255, 255, 255, 1);
const Color backgroundElevated2Light = Color.fromRGBO(251, 251, 251, 1);

const Color backgroundBaseDark = Color.fromRGBO(0, 0, 0, 1);
const Color backgroundElevatedDark = Color.fromRGBO(27, 27, 27, 1);
const Color backgroundElevated2Dark = Color.fromRGBO(37, 37, 37, 1);

// Backdrop Colors
const Color backdropBaseLight = Color.fromRGBO(255, 255, 255, 0.92);
const Color backdropMutedLight = Color.fromRGBO(255, 255, 255, 0.75);
const Color backdropFaintLight = Color.fromRGBO(255, 255, 255, 0.30);

const Color backdropBaseDark = Color.fromRGBO(0, 0, 0, 0.90);
const Color backdropMutedDark = Color.fromRGBO(0, 0, 0, 0.65);
const Color backdropFaintDark = Color.fromRGBO(0, 0, 0, 0.20);

// Text Colors
const Color textBaseLight = Color.fromRGBO(0, 0, 0, 1);
const Color textMutedLight = Color.fromRGBO(0, 0, 0, 0.6);
const Color textFaintLight = Color.fromRGBO(0, 0, 0, 0.5);

const Color textBaseDark = Color.fromRGBO(255, 255, 255, 1);
const Color textMutedDark = Color.fromRGBO(255, 255, 255, 0.7);
const Color textFaintDark = Color.fromRGBO(255, 255, 255, 0.5);

// Fill Colors
const Color fillBaseLight = Color.fromRGBO(0, 0, 0, 1);
const Color fillBasePressedLight = Color.fromRGBO(0, 0, 0, 0.87);
const Color fillMutedLight = Color.fromRGBO(0, 0, 0, 0.12);
const Color fillFaintLight = Color.fromRGBO(0, 0, 0, 0.04);
const Color fillFaintPressedLight = Color.fromRGBO(0, 0, 0, 0.08);

const Color fillBaseDark = Color.fromRGBO(255, 255, 255, 1);
const Color fillBasePressedDark = Color.fromRGBO(255, 255, 255, 0.9);
const Color fillMutedDark = Color.fromRGBO(255, 255, 255, 0.16);
const Color fillFaintDark = Color.fromRGBO(255, 255, 255, 0.12);
const Color fillFaintPressedDark = Color.fromRGBO(255, 255, 255, 0.06);

// Stroke Colors
const Color strokeBaseLight = Color.fromRGBO(0, 0, 0, 1);
const Color strokeMutedLight = Color.fromRGBO(0, 0, 0, 0.24);
const Color strokeFaintLight = Color.fromRGBO(0, 0, 0, 0.04);
const Color strokeFainterLight = Color.fromRGBO(0, 0, 0, 0.06);
const Color blurStrokeBaseLight = Color.fromRGBO(0, 0, 0, 0.65);
const Color blurStrokeFaintLight = Color.fromRGBO(0, 0, 0, 0.08);
const Color blurStrokePressedLight = Color.fromRGBO(0, 0, 0, 0.50);

const Color strokeBaseDark = Color.fromRGBO(255, 255, 255, 1);
const Color strokeMutedDark = Color.fromRGBO(255, 255, 255, 0.24);
const Color strokeFaintDark = Color.fromRGBO(255, 255, 255, 0.16);
const Color strokeFainterDark = Color.fromRGBO(255, 255, 255, 0.08);
const Color blurStrokeBaseDark = Color.fromRGBO(255, 255, 255, 0.90);
const Color blurStrokeFaintDark = Color.fromRGBO(255, 255, 255, 0.06);
const Color blurStrokePressedDark = Color.fromRGBO(255, 255, 255, 0.50);

// Fixed Colors

const Color _primaryGreen = Color.fromRGBO(29, 185, 84, 1);

const Color _primary700 = Color(0xFF722ED1);
const Color _primary500 = accentColor;
const Color _primary400 = Color(0xFF7A29C1);
const Color _primary300 = Color(0xFF984DF4);

const Color _iconButtonBrightColor = Color.fromRGBO(130, 50, 225, 1);
const Color _iconButtonDarkColor = Color.fromRGBO(255, 150, 16, 1);

const Color _warning700 = Color.fromRGBO(245, 52, 52, 1);
const Color _warning500 = Color.fromRGBO(255, 101, 101, 1);
const Color _warning800 = Color(0xFFF53434);
const Color warning500 = Color.fromRGBO(255, 101, 101, 1);
// ignore: unused_element
const Color _warning400 = Color.fromRGBO(255, 111, 111, 1);

const Color _caution500 = Color.fromRGBO(255, 194, 71, 1);

const List<Color> avatarLight = [
  Color.fromRGBO(118, 84, 154, 1),
  Color.fromRGBO(223, 120, 97, 1),
  Color.fromRGBO(148, 180, 159, 1),
  Color.fromRGBO(135, 162, 251, 1),
  Color.fromRGBO(198, 137, 198, 1),
  Color.fromRGBO(198, 137, 198, 1),
  Color.fromRGBO(50, 82, 136, 1),
  Color.fromRGBO(133, 180, 224, 1),
  Color.fromRGBO(193, 163, 163, 1),
  Color.fromRGBO(193, 163, 163, 1),
  Color.fromRGBO(66, 97, 101, 1),
  Color.fromRGBO(66, 97, 101, 1),
  Color.fromRGBO(66, 97, 101, 1),
  Color.fromRGBO(221, 157, 226, 1),
  Color.fromRGBO(130, 171, 139, 1),
  Color.fromRGBO(155, 187, 232, 1),
  Color.fromRGBO(143, 190, 190, 1),
  Color.fromRGBO(138, 195, 161, 1),
  Color.fromRGBO(168, 176, 242, 1),
  Color.fromRGBO(176, 198, 149, 1),
  Color.fromRGBO(233, 154, 173, 1),
  Color.fromRGBO(209, 132, 132, 1),
  Color.fromRGBO(120, 181, 167, 1),
];

const List<Color> avatarDark = [
  Color.fromRGBO(118, 84, 154, 1),
  Color.fromRGBO(223, 120, 97, 1),
  Color.fromRGBO(148, 180, 159, 1),
  Color.fromRGBO(135, 162, 251, 1),
  Color.fromRGBO(198, 137, 198, 1),
  Color.fromRGBO(147, 125, 194, 1),
  Color.fromRGBO(50, 82, 136, 1),
  Color.fromRGBO(133, 180, 224, 1),
  Color.fromRGBO(193, 163, 163, 1),
  Color.fromRGBO(225, 160, 89, 1),
  Color.fromRGBO(66, 97, 101, 1),
  Color.fromRGBO(107, 119, 178, 1),
  Color.fromRGBO(149, 127, 239, 1),
  Color.fromRGBO(221, 157, 226, 1),
  Color.fromRGBO(130, 171, 139, 1),
  Color.fromRGBO(155, 187, 232, 1),
  Color.fromRGBO(143, 190, 190, 1),
  Color.fromRGBO(138, 195, 161, 1),
  Color.fromRGBO(168, 176, 242, 1),
  Color.fromRGBO(176, 198, 149, 1),
  Color.fromRGBO(233, 154, 173, 1),
  Color.fromRGBO(209, 132, 132, 1),
  Color.fromRGBO(120, 181, 167, 1),
];

// Tags
const Color _tagChipUnselectedColorLight = Color(0xFFFCF5FF);
const Color _tagChipUnselectedColorDark = Color(0xFF1C0F22);
const List<Color> _tagChipUnselectedGradientLight = [
  Color(0x33AD00FF),
  Color(0x338609C2),
];
const List<Color> _tagChipUnselectedGradientDark = [
  Color(0xFFAD00FF),
  Color(0x87A269BD),
];
const Color _tagChipSelectedColor = Color(0xFF722ED1);
const List<Color> _tagChipSelectedGradientLight = [
  Color(0xFFB37FEB),
  Color(0xFFAE40E3),
];
const List<Color> _tagChipSelectedGradientDark = [
  Color(0xFFB37FEB),
  Color(0x87AE40E3),
];
const Color _tagTextUnselectedColor = Color(0xFF8232E1);
const Color _deleteTagIconColor = Color(0xFFF53434);
const Color _deleteTagTextColor = Color(0xFFF53434);

// Code Widget
const Color _pinnedBgColorLight = Color(0xFFF9ECFF);
const Color _pinnedBgColorDark = Color(0xFF390C4F);
const Color _errorCodeProgressColor = Color(0xFFF53434);
const Color _infoIconColor = Color(0xFFF53434);
const Color _errorCardTextColor = Color(0xFFF53434);
const Color _deleteCodeTextColor = Color(0xFFFE4A49);
const List<BoxShadow> _pinnedCardBoxShadow = [
  BoxShadow(color: Color(0x08000000), blurRadius: 2, offset: Offset(0, 7)),
  BoxShadow(color: Color(0x17000000), blurRadius: 2, offset: Offset(0, 4)),
  BoxShadow(color: Color(0x29000000), blurRadius: 1, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x2E000000), blurRadius: 1, offset: Offset(0, 0)),
];

// Gradient Button
const Color _gradientButtonBgColor = Color(0xFF531DAB);
const List<Color> _gradientButtonBgColors = [
  Color(0xFFB37FEB),
  Color(0xFF22075E),
];
