import 'package:flutter/material.dart';

/// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=57-6281&view=variables
/// Section: Colours / Semantic tokens
/// Specs: Color Tokens collection with light and dark modes.
enum ComponentApp { photos, auth, locker }

class ColorTokens {
  const ColorTokens({
    required this.primaryLight,
    required this.primaryLightHover,
    required this.primaryLightPressed,
    required this.primaryStroke,
    required this.primary,
    required this.primaryDark,
    required this.primaryDarker,
    required this.greenLight,
    required this.greenLightHover,
    required this.greenLightPressed,
    required this.greenStroke,
    required this.green,
    required this.greenDark,
    required this.greenDarker,
    required this.blueLight,
    required this.blueLightHover,
    required this.blueLightPressed,
    required this.blueStroke,
    required this.blue,
    required this.blueDark,
    required this.blueDarker,
    required this.purpleLight,
    required this.purpleLightHover,
    required this.purpleLightPressed,
    required this.purpleStroke,
    required this.purple,
    required this.purpleDark,
    required this.purpleDarker,
    required this.warningLight,
    required this.warning,
    required this.warningDark,
    required this.warningDarker,
    required this.cautionLight,
    required this.caution,
    required this.textLight,
    required this.textBase,
    required this.textDark,
    required this.textDarker,
    required this.textLighter,
    required this.textLightest,
    required this.textReverse,
    required this.iconColor,
    required this.backgroundBase,
    required this.fillLight,
    required this.fillBase,
    required this.fillDark,
    required this.fillDarker,
    required this.fillDarkest,
    required this.strokeDark,
    required this.strokeFaint,
    required this.accentOrangeLight,
    required this.accentPinkLight,
    required this.accentTealLight,
    required this.accentOrange,
    required this.accentPink,
    required this.accentTeal,
    required this.specialContentReverse,
    required this.specialScrim,
    required this.specialWhite,
    required this.specialWhiteOverlay,
  });

  final Color primaryLight;
  final Color primaryLightHover;
  final Color primaryLightPressed;
  final Color primaryStroke;
  final Color primary;
  final Color primaryDark;
  final Color primaryDarker;
  final Color greenLight;
  final Color greenLightHover;
  final Color greenLightPressed;
  final Color greenStroke;
  final Color green;
  final Color greenDark;
  final Color greenDarker;
  final Color blueLight;
  final Color blueLightHover;
  final Color blueLightPressed;
  final Color blueStroke;
  final Color blue;
  final Color blueDark;
  final Color blueDarker;
  final Color purpleLight;
  final Color purpleLightHover;
  final Color purpleLightPressed;
  final Color purpleStroke;
  final Color purple;
  final Color purpleDark;
  final Color purpleDarker;
  final Color warningLight;
  final Color warning;
  final Color warningDark;
  final Color warningDarker;
  final Color cautionLight;
  final Color caution;
  final Color textLight;
  final Color textBase;
  final Color textDark;
  final Color textDarker;
  final Color textLighter;
  final Color textLightest;
  final Color textReverse;
  final Color iconColor;
  final Color backgroundBase;
  final Color fillLight;
  final Color fillBase;
  final Color fillDark;
  final Color fillDarker;
  final Color fillDarkest;
  final Color strokeDark;
  final Color strokeFaint;
  final Color accentOrangeLight;
  final Color accentPinkLight;
  final Color accentTealLight;
  final Color accentOrange;
  final Color accentPink;
  final Color accentTeal;
  final Color specialContentReverse;
  final Color specialScrim;
  final Color specialWhite;
  final Color specialWhiteOverlay;

  static const light = colorTokensLight;
  static const dark = colorTokensDark;

  factory ColorTokens.forApp(
    ComponentApp app, {
    Brightness brightness = Brightness.light,
  }) {
    final base = brightness == Brightness.dark
        ? colorTokensDark
        : colorTokensLight;
    return base.withPrimary(_primaryTokensForApp(app, brightness));
  }

  ColorTokens withPrimary(PrimaryColorTokens primaryTokens) {
    return ColorTokens(
      primaryLight: primaryTokens.primaryLight,
      primaryLightHover: primaryTokens.primaryLightHover,
      primaryLightPressed: primaryTokens.primaryLightPressed,
      primaryStroke: primaryTokens.primaryStroke,
      primary: primaryTokens.primary,
      primaryDark: primaryTokens.primaryDark,
      primaryDarker: primaryTokens.primaryDarker,
      greenLight: greenLight,
      greenLightHover: greenLightHover,
      greenLightPressed: greenLightPressed,
      greenStroke: greenStroke,
      green: green,
      greenDark: greenDark,
      greenDarker: greenDarker,
      blueLight: blueLight,
      blueLightHover: blueLightHover,
      blueLightPressed: blueLightPressed,
      blueStroke: blueStroke,
      blue: blue,
      blueDark: blueDark,
      blueDarker: blueDarker,
      purpleLight: purpleLight,
      purpleLightHover: purpleLightHover,
      purpleLightPressed: purpleLightPressed,
      purpleStroke: purpleStroke,
      purple: purple,
      purpleDark: purpleDark,
      purpleDarker: purpleDarker,
      warningLight: warningLight,
      warning: warning,
      warningDark: warningDark,
      warningDarker: warningDarker,
      cautionLight: cautionLight,
      caution: caution,
      textLight: textLight,
      textBase: textBase,
      textDark: textDark,
      textDarker: textDarker,
      textLighter: textLighter,
      textLightest: textLightest,
      textReverse: textReverse,
      iconColor: iconColor,
      backgroundBase: backgroundBase,
      fillLight: fillLight,
      fillBase: fillBase,
      fillDark: fillDark,
      fillDarker: fillDarker,
      fillDarkest: fillDarkest,
      strokeDark: strokeDark,
      strokeFaint: strokeFaint,
      accentOrangeLight: accentOrangeLight,
      accentPinkLight: accentPinkLight,
      accentTealLight: accentTealLight,
      accentOrange: accentOrange,
      accentPink: accentPink,
      accentTeal: accentTeal,
      specialContentReverse: specialContentReverse,
      specialScrim: specialScrim,
      specialWhite: specialWhite,
      specialWhiteOverlay: specialWhiteOverlay,
    );
  }
}

class PrimaryColorTokens {
  const PrimaryColorTokens({
    required this.primaryLight,
    required this.primaryLightHover,
    required this.primaryLightPressed,
    required this.primaryStroke,
    required this.primary,
    required this.primaryDark,
    required this.primaryDarker,
  });

  final Color primaryLight;
  final Color primaryLightHover;
  final Color primaryLightPressed;
  final Color primaryStroke;
  final Color primary;
  final Color primaryDark;
  final Color primaryDarker;
}

PrimaryColorTokens _primaryTokensForApp(
  ComponentApp app,
  Brightness brightness,
) {
  final dark = brightness == Brightness.dark;
  return switch (app) {
    ComponentApp.photos =>
      dark ? greenPrimaryTokensDark : greenPrimaryTokensLight,
    ComponentApp.auth =>
      dark ? purplePrimaryTokensDark : purplePrimaryTokensLight,
    ComponentApp.locker =>
      dark ? bluePrimaryTokensDark : bluePrimaryTokensLight,
  };
}

const ColorTokens colorTokensLight = ColorTokens(
  primaryLight: greenLightLight,
  primaryLightHover: greenLightHoverLight,
  primaryLightPressed: greenLightPressedLight,
  primaryStroke: greenStrokeLight,
  primary: greenDefaultLight,
  primaryDark: greenDarkLight,
  primaryDarker: greenDarkerLight,
  greenLight: greenLightLight,
  greenLightHover: greenLightHoverLight,
  greenLightPressed: greenLightPressedLight,
  greenStroke: greenStrokeLight,
  green: greenDefaultLight,
  greenDark: greenDarkLight,
  greenDarker: greenDarkerLight,
  blueLight: blueLightLight,
  blueLightHover: blueLightHoverLight,
  blueLightPressed: blueLightPressedLight,
  blueStroke: blueStrokeLight,
  blue: blueDefaultLight,
  blueDark: blueDarkLight,
  blueDarker: blueDarkerLight,
  purpleLight: purpleLightLight,
  purpleLightHover: purpleLightHoverLight,
  purpleLightPressed: purpleLightPressedLight,
  purpleStroke: purpleStrokeLight,
  purple: purpleDefaultLight,
  purpleDark: purpleDarkLight,
  purpleDarker: purpleDarkerLight,
  warningLight: warningLightLight,
  warning: warningDefaultLight,
  warningDark: warningDarkLight,
  warningDarker: warningDarkerLight,
  cautionLight: cautionLightLight,
  caution: cautionDefaultLight,
  textLight: textLightLight,
  textBase: textBaseLight,
  textDark: textDarkLight,
  textDarker: textDarkerLight,
  textLighter: textLighterLight,
  textLightest: textLightestLight,
  textReverse: textReverseLight,
  iconColor: iconColorLight,
  backgroundBase: backgroundBaseLight,
  fillLight: fillLightLight,
  fillBase: fillBaseLight,
  fillDark: fillDarkLight,
  fillDarker: fillDarkerLight,
  fillDarkest: fillDarkestLight,
  strokeDark: strokeDarkLight,
  strokeFaint: strokeFaintLight,
  accentOrangeLight: accentOrangeLightLight,
  accentPinkLight: accentPinkLightLight,
  accentTealLight: accentTealLightLight,
  accentOrange: accentOrangeDefaultLight,
  accentPink: accentPinkDefaultLight,
  accentTeal: accentTealDefaultLight,
  specialContentReverse: specialContentReverseLight,
  specialScrim: specialScrimLight,
  specialWhite: specialWhiteLight,
  specialWhiteOverlay: specialWhiteOverlayLight,
);

const ColorTokens colorTokensDark = ColorTokens(
  primaryLight: greenLightDark,
  primaryLightHover: greenLightHoverDark,
  primaryLightPressed: greenLightPressedDark,
  primaryStroke: greenStrokeDark,
  primary: greenDefaultDark,
  primaryDark: greenDarkDark,
  primaryDarker: greenDarkerDark,
  greenLight: greenLightDark,
  greenLightHover: greenLightHoverDark,
  greenLightPressed: greenLightPressedDark,
  greenStroke: greenStrokeDark,
  green: greenDefaultDark,
  greenDark: greenDarkDark,
  greenDarker: greenDarkerDark,
  blueLight: blueLightDark,
  blueLightHover: blueLightHoverDark,
  blueLightPressed: blueLightPressedDark,
  blueStroke: blueStrokeDark,
  blue: blueDefaultDark,
  blueDark: blueDarkDark,
  blueDarker: blueDarkerDark,
  purpleLight: purpleLightDark,
  purpleLightHover: purpleLightHoverDark,
  purpleLightPressed: purpleLightPressedDark,
  purpleStroke: purpleStrokeDark,
  purple: purpleDefaultDark,
  purpleDark: purpleDarkDark,
  purpleDarker: purpleDarkerDark,
  warningLight: warningLightDark,
  warning: warningDefaultDark,
  warningDark: warningDarkDark,
  warningDarker: warningDarkerDark,
  cautionLight: cautionLightDark,
  caution: cautionDefaultDark,
  textLight: textLightDark,
  textBase: textBaseDark,
  textDark: textDarkDark,
  textDarker: textDarkerDark,
  textLighter: textLighterDark,
  textLightest: textLightestDark,
  textReverse: textReverseDark,
  iconColor: iconColorDark,
  backgroundBase: backgroundBaseDark,
  fillLight: fillLightDark,
  fillBase: fillBaseDark,
  fillDark: fillDarkDark,
  fillDarker: fillDarkerDark,
  fillDarkest: fillDarkestDark,
  strokeDark: strokeDarkDark,
  strokeFaint: strokeFaintDark,
  accentOrangeLight: accentOrangeLightDark,
  accentPinkLight: accentPinkLightDark,
  accentTealLight: accentTealLightDark,
  accentOrange: accentOrangeDefaultDark,
  accentPink: accentPinkDefaultDark,
  accentTeal: accentTealDefaultDark,
  specialContentReverse: specialContentReverseDark,
  specialScrim: specialScrimDark,
  specialWhite: specialWhiteDark,
  specialWhiteOverlay: specialWhiteOverlayDark,
);

const PrimaryColorTokens greenPrimaryTokensLight = PrimaryColorTokens(
  primaryLight: greenLightLight,
  primaryLightHover: greenLightHoverLight,
  primaryLightPressed: greenLightPressedLight,
  primaryStroke: greenStrokeLight,
  primary: greenDefaultLight,
  primaryDark: greenDarkLight,
  primaryDarker: greenDarkerLight,
);

const PrimaryColorTokens greenPrimaryTokensDark = PrimaryColorTokens(
  primaryLight: greenLightDark,
  primaryLightHover: greenLightHoverDark,
  primaryLightPressed: greenLightPressedDark,
  primaryStroke: greenStrokeDark,
  primary: greenDefaultDark,
  primaryDark: greenDarkDark,
  primaryDarker: greenDarkerDark,
);

const PrimaryColorTokens purplePrimaryTokensLight = PrimaryColorTokens(
  primaryLight: purpleLightLight,
  primaryLightHover: purpleLightHoverLight,
  primaryLightPressed: purpleLightPressedLight,
  primaryStroke: purpleStrokeLight,
  primary: purpleDefaultLight,
  primaryDark: purpleDarkLight,
  primaryDarker: purpleDarkerLight,
);

const PrimaryColorTokens purplePrimaryTokensDark = PrimaryColorTokens(
  primaryLight: purpleLightDark,
  primaryLightHover: purpleLightHoverDark,
  primaryLightPressed: purpleLightPressedDark,
  primaryStroke: purpleStrokeDark,
  primary: purpleDefaultDark,
  primaryDark: purpleDarkDark,
  primaryDarker: purpleDarkerDark,
);

const PrimaryColorTokens bluePrimaryTokensLight = PrimaryColorTokens(
  primaryLight: blueLightLight,
  primaryLightHover: blueLightHoverLight,
  primaryLightPressed: blueLightPressedLight,
  primaryStroke: blueStrokeLight,
  primary: blueDefaultLight,
  primaryDark: blueDarkLight,
  primaryDarker: blueDarkerLight,
);

const PrimaryColorTokens bluePrimaryTokensDark = PrimaryColorTokens(
  primaryLight: blueLightDark,
  primaryLightHover: blueLightHoverDark,
  primaryLightPressed: blueLightPressedDark,
  primaryStroke: blueStrokeDark,
  primary: blueDefaultDark,
  primaryDark: blueDarkDark,
  primaryDarker: blueDarkerDark,
);

// Green Colors
const Color greenLightLight = Color.fromRGBO(221, 238, 223, 1);
const Color greenLightDark = Color.fromRGBO(41, 41, 41, 1);

const Color greenLightHoverLight = Color.fromRGBO(205, 229, 208, 1);
const Color greenLightHoverDark = Color.fromRGBO(31, 48, 35, 1);

const Color greenLightPressedLight = Color.fromRGBO(184, 213, 187, 1);
const Color greenLightPressedDark = Color.fromRGBO(44, 66, 50, 1);

const Color greenStrokeLight = Color.fromRGBO(186, 236, 194, 1);
const Color greenStrokeDark = Color.fromRGBO(28, 65, 34, 1);

const Color greenDefaultLight = Color.fromRGBO(8, 194, 37, 1);
const Color greenDefaultDark = Color.fromRGBO(8, 194, 37, 1);

const Color greenDarkLight = Color.fromRGBO(6, 157, 30, 1);
const Color greenDarkDark = Color.fromRGBO(6, 157, 30, 1);

const Color greenDarkerLight = Color.fromRGBO(5, 124, 24, 1);
const Color greenDarkerDark = Color.fromRGBO(5, 124, 24, 1);

// Purple Colors
const Color purpleLightLight = Color.fromRGBO(244, 231, 252, 1);
const Color purpleLightDark = Color.fromRGBO(39, 28, 50, 1);

const Color purpleLightHoverLight = Color.fromRGBO(232, 210, 250, 1);
const Color purpleLightHoverDark = Color.fromRGBO(47, 31, 63, 1);

const Color purpleLightPressedLight = Color.fromRGBO(217, 188, 241, 1);
const Color purpleLightPressedDark = Color.fromRGBO(37, 23, 52, 1);

const Color purpleStrokeLight = Color.fromRGBO(216, 181, 244, 1);
const Color purpleStrokeDark = Color.fromRGBO(61, 27, 92, 1);

const Color purpleDefaultLight = Color.fromRGBO(150, 16, 214, 1);
const Color purpleDefaultDark = Color.fromRGBO(150, 16, 214, 1);

const Color purpleDarkLight = Color.fromRGBO(122, 12, 174, 1);
const Color purpleDarkDark = Color.fromRGBO(122, 12, 174, 1);

const Color purpleDarkerLight = Color.fromRGBO(93, 8, 132, 1);
const Color purpleDarkerDark = Color.fromRGBO(93, 8, 132, 1);

// Blue Colors
const Color blueLightLight = Color.fromRGBO(231, 239, 250, 1);
const Color blueLightDark = Color.fromRGBO(41, 41, 41, 1);

const Color blueLightHoverLight = Color.fromRGBO(216, 228, 244, 1);
const Color blueLightHoverDark = Color.fromRGBO(26, 38, 56, 1);

const Color blueLightPressedLight = Color.fromRGBO(194, 210, 232, 1);
const Color blueLightPressedDark = Color.fromRGBO(17, 30, 49, 1);

const Color blueStrokeLight = Color.fromRGBO(16, 113, 255, 1);
const Color blueStrokeDark = Color.fromRGBO(16, 113, 255, 1);

const Color blueDefaultLight = Color.fromRGBO(16, 113, 255, 1);
const Color blueDefaultDark = Color.fromRGBO(16, 113, 255, 1);

const Color blueDarkLight = Color.fromRGBO(14, 95, 217, 1);
const Color blueDarkDark = Color.fromRGBO(14, 95, 217, 1);

const Color blueDarkerLight = Color.fromRGBO(11, 76, 173, 1);
const Color blueDarkerDark = Color.fromRGBO(11, 76, 173, 1);

// Warning Colors
const Color warningLightLight = Color.fromRGBO(250, 235, 235, 1);
const Color warningLightDark = Color.fromRGBO(41, 41, 41, 1);

const Color warningDefaultLight = Color.fromRGBO(246, 58, 58, 1);
const Color warningDefaultDark = Color.fromRGBO(246, 58, 58, 1);

const Color warningDarkLight = Color.fromRGBO(221, 52, 52, 1);
const Color warningDarkDark = Color.fromRGBO(221, 52, 52, 1);

const Color warningDarkerLight = Color.fromRGBO(197, 46, 46, 1);
const Color warningDarkerDark = Color.fromRGBO(197, 46, 46, 1);

// Caution Colors
const Color cautionLightLight = Color.fromRGBO(250, 244, 235, 1);
const Color cautionLightDark = Color.fromRGBO(41, 41, 41, 1);

const Color cautionDefaultLight = Color.fromRGBO(240, 138, 30, 1);
const Color cautionDefaultDark = Color.fromRGBO(240, 138, 30, 1);

// Text Colors
const Color textLightLight = Color.fromRGBO(102, 102, 102, 1);
const Color textLightDark = Color.fromRGBO(153, 153, 153, 1);

const Color textBaseLight = Color.fromRGBO(0, 0, 0, 1);
const Color textBaseDark = Color.fromRGBO(255, 255, 255, 1);

const Color textDarkLight = Color.fromRGBO(26, 26, 26, 1);
const Color textDarkDark = Color.fromRGBO(229, 229, 229, 1);

const Color textDarkerLight = Color.fromRGBO(21, 21, 21, 1);
const Color textDarkerDark = Color.fromRGBO(204, 204, 204, 1);

const Color textLighterLight = Color.fromRGBO(150, 150, 150, 1);
const Color textLighterDark = Color.fromRGBO(150, 150, 150, 1);

const Color textLightestLight = Color.fromRGBO(214, 214, 214, 1);
const Color textLightestDark = Color.fromRGBO(65, 65, 65, 1);

const Color textReverseLight = Color.fromRGBO(255, 255, 255, 1);
const Color textReverseDark = Color.fromRGBO(0, 0, 0, 1);

// Icon Colors
const Color iconColorLight = Color.fromRGBO(0, 0, 0, 0.75);
const Color iconColorDark = Color.fromRGBO(255, 255, 255, 1);

// Background Colors
const Color backgroundBaseLight = Color.fromRGBO(244, 244, 244, 1);
const Color backgroundBaseDark = Color.fromRGBO(22, 22, 22, 1);

// Fill Colors
const Color fillLightLight = Color.fromRGBO(255, 255, 255, 1);
const Color fillLightDark = Color.fromRGBO(33, 33, 33, 1);

const Color fillBaseLight = Color.fromRGBO(0, 0, 0, 1);
const Color fillBaseDark = Color.fromRGBO(255, 255, 255, 1);

const Color fillDarkLight = Color.fromRGBO(234, 234, 234, 1);
const Color fillDarkDark = Color.fromRGBO(10, 10, 10, 1);

const Color fillDarkerLight = Color.fromRGBO(222, 222, 222, 1);
const Color fillDarkerDark = Color.fromRGBO(20, 20, 20, 1);

const Color fillDarkestLight = Color.fromRGBO(210, 210, 210, 1);
const Color fillDarkestDark = Color.fromRGBO(41, 41, 41, 1);

// Stroke Colors
const Color strokeDarkLight = Color.fromRGBO(224, 224, 224, 1);
const Color strokeDarkDark = Color.fromRGBO(62, 62, 62, 1);

const Color strokeFaintLight = Color.fromRGBO(235, 235, 235, 1);
const Color strokeFaintDark = Color.fromRGBO(42, 42, 42, 1);

// Accent Colors
const Color accentOrangeLightLight = Color.fromRGBO(255, 247, 244, 1);
const Color accentOrangeLightDark = Color.fromRGBO(41, 41, 41, 1);

const Color accentPinkLightLight = Color.fromRGBO(253, 246, 251, 1);
const Color accentPinkLightDark = Color.fromRGBO(41, 41, 41, 1);

const Color accentTealLightLight = Color.fromRGBO(245, 251, 251, 1);
const Color accentTealLightDark = Color.fromRGBO(41, 41, 41, 1);

const Color accentOrangeDefaultLight = Color.fromRGBO(242, 72, 34, 1);
const Color accentOrangeDefaultDark = Color.fromRGBO(242, 72, 34, 1);

const Color accentPinkDefaultLight = Color.fromRGBO(223, 97, 187, 1);
const Color accentPinkDefaultDark = Color.fromRGBO(223, 97, 187, 1);

const Color accentTealDefaultLight = Color.fromRGBO(95, 183, 187, 1);
const Color accentTealDefaultDark = Color.fromRGBO(95, 183, 187, 1);

// Special Colors
const Color specialContentReverseLight = Color.fromRGBO(255, 255, 255, 1);
const Color specialContentReverseDark = Color.fromRGBO(0, 0, 0, 1);

const Color specialScrimLight = Color.fromRGBO(0, 0, 0, 0.4);
const Color specialScrimDark = Color.fromRGBO(0, 0, 0, 0.4);

const Color specialWhiteLight = Color.fromRGBO(255, 255, 255, 1);
const Color specialWhiteDark = Color.fromRGBO(255, 255, 255, 1);

const Color specialWhiteOverlayLight = Color.fromRGBO(255, 255, 255, 0.14);
const Color specialWhiteOverlayDark = Color.fromRGBO(255, 255, 255, 0.14);

const Color avatarCyan = Color.fromRGBO(0, 184, 212, 1);

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
