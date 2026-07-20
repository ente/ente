import 'dart:ui';

import 'package:flutter/material.dart';

class EnteColorScheme {
  // Background Colors
  final Color backgroundColour;
  final Color backgroundElevated;
  final Color backgroundElevated2;

  // Backdrop Colors
  final Color backdropBase;
  final Color backdropMuted;
  final Color backdropFaint;

  // Text Colors
  final Color textBase;
  final Color textMuted;
  final Color textFaint;
  final Color blurTextBase;

  // Fill Colors
  final Color fillBase;
  final Color fillBasePressed;
  final Color fillStrong;
  final Color fillMuted;
  final Color fillFaint;
  final Color fillFaintPressed;
  final Color fillBaseGrey;

  // Stroke Colors
  final Color strokeBase;
  final Color strokeMuted;
  final Color strokeFaint;
  final Color strokeFainter;
  final Color blurStrokeBase;
  final Color blurStrokeFaint;
  final Color blurStrokePressed;

  // Fixed Colors
  final Color primary700;
  final Color primary500;
  final Color primary400;
  final Color primary300;

  //warning colors
  final Color warning700;
  final Color warning500;
  final Color warning400;
  final Color warning800;
  final Color caution500;

  //golden colors
  final Color golden700;
  final Color golden500;

  //other colors
  final Color tabIcon;

  // Menu item icon stroke color
  final Color menuItemIconStroke;

  final Color fill;
  final Color fillDark;
  final Color fillDarker;
  final Color fillDarkest;
  final Color fillReverse;

  final Color content;
  final Color contentDark;
  final Color contentDarker;
  final Color contentLight;
  final Color contentLighter;
  final Color contentLightest;
  final Color contentReverse;

  final Color strokeSolid;
  final Color strokeDark;

  final Color greenBase;
  final Color greenDark;
  final Color greenDarker;
  final Color greenLight;
  final Color greenStroke;

  final Color redBase;
  final Color redDark;
  final Color redDarker;
  final Color redLight;

  const EnteColorScheme(
    this.backgroundColour,
    this.backgroundElevated,
    this.backgroundElevated2,
    this.backdropBase,
    this.backdropMuted,
    this.backdropFaint,
    this.textBase,
    this.textMuted,
    this.textFaint,
    this.blurTextBase,
    this.fillBase,
    this.fillBasePressed,
    this.fillStrong,
    this.fillMuted,
    this.fillFaint,
    this.fillFaintPressed,
    this.fillBaseGrey,
    this.strokeBase,
    this.strokeMuted,
    this.strokeFaint,
    this.strokeFainter,
    this.blurStrokeBase,
    this.blurStrokeFaint,
    this.blurStrokePressed,
    this.tabIcon,
    this.menuItemIconStroke,
    this.fill,
    this.fillDark,
    this.fillDarker,
    this.fillDarkest,
    this.fillReverse,
    this.content,
    this.contentDark,
    this.contentDarker,
    this.contentLight,
    this.contentLighter,
    this.contentLightest,
    this.contentReverse,
    this.strokeSolid,
    this.strokeDark,
    this.greenBase,
    this.greenDark,
    this.greenDarker,
    this.greenLight,
    this.greenStroke,
    this.redBase,
    this.redDark,
    this.redDarker,
    this.redLight, {
    this.primary700 = _primary700,
    this.primary500 = _primary500,
    this.primary400 = _primary400,
    this.primary300 = _primary300,
    this.warning800 = _warning800,
    this.warning700 = _warning700,
    this.warning500 = _warning500,
    this.warning400 = _warning400,
    this.caution500 = _caution500,
    this.golden700 = _golden700,
    this.golden500 = _golden500,
  });
}

const EnteColorScheme lightScheme = EnteColorScheme(
  backgroundColorLight,
  backgroundElevatedLight,
  backgroundElevated2Light,
  backdropBaseLight,
  backdropMutedLight,
  backdropFaintLight,
  textBaseLight,
  textMutedLight,
  textFaintLight,
  blurTextBaseLight,
  fillBaseLight,
  fillBasePressedLight,
  fillStrongLight,
  fillMutedLight,
  fillFaintLight,
  fillFaintPressedLight,
  fillBaseGreyLight,
  strokeBaseLight,
  strokeMutedLight,
  strokeFaintLight,
  strokeFainterLight,
  blurStrokeBaseLight,
  blurStrokeFaintLight,
  blurStrokePressedLight,
  tabIconLight,
  menuItemIconStrokeLight,
  fillLight,
  fillDarkLight,
  fillDarkerLight,
  fillDarkestLight,
  fillReverseLight,
  contentLight,
  contentDarkLight,
  contentDarkerLight,
  contentLightLight,
  contentLighterLight,
  contentLightestLight,
  contentReverseLight,
  strokeLight,
  strokeDarkLight,
  green,
  greenDark,
  greenDarker,
  greenLightLight,
  greenStrokeLight,
  red,
  redDark,
  redDarker,
  redLightLight,
);

const EnteColorScheme darkScheme = EnteColorScheme(
  backgroundColorDark,
  backgroundElevatedDark,
  backgroundElevated2Dark,
  backdropBaseDark,
  backdropMutedDark,
  backdropFaintDark,
  textBaseDark,
  textMutedDark,
  textFaintDark,
  blurTextBaseDark,
  fillBaseDark,
  fillBasePressedDark,
  fillStrongDark,
  fillMutedDark,
  fillFaintDark,
  fillFaintPressedDark,
  fillBaseGreyDark,
  strokeBaseDark,
  strokeMutedDark,
  strokeFaintDark,
  strokeFainterDark,
  blurStrokeBaseDark,
  blurStrokeFaintDark,
  blurStrokePressedDark,
  tabIconDark,
  menuItemIconStrokeDark,
  fillDark,
  fillDarkDark,
  fillDarkerDark,
  fillDarkestDark,
  fillReverseDark,
  contentDark,
  contentDarkDark,
  contentDarkerDark,
  contentLightDark,
  contentLighterDark,
  contentLightestDark,
  contentReverseDark,
  strokeDark,
  strokeDarkDark,
  green,
  greenDark,
  greenDarker,
  greenLightDark,
  greenStrokeDark,
  red,
  redDark,
  redDarker,
  redLightDark,
);

// Background
const Color backgroundColorLight = Color.fromRGBO(244, 244, 244, 1);
const Color backgroundColorDark = Color.fromRGBO(22, 22, 22, 1);

const Color backgroundElevatedLight = Color.fromRGBO(255, 255, 255, 1);
const Color backgroundElevated2Light = Color.fromRGBO(251, 251, 251, 1);

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
const Color blurTextBaseLight = Color.fromRGBO(0, 0, 0, 0.65);

const Color textBaseDark = Color.fromRGBO(255, 255, 255, 1);
const Color textMutedDark = Color.fromRGBO(255, 255, 255, 0.7);
const Color textFaintDark = Color.fromRGBO(255, 255, 255, 0.5);
const Color blurTextBaseDark = Color.fromRGBO(255, 255, 255, 0.95);

// Fill Colors
const Color fillBaseLight = Color.fromRGBO(0, 0, 0, 1);
const Color fillBasePressedLight = Color.fromRGBO(0, 0, 0, 0.87);
const Color fillStrongLight = Color.fromRGBO(0, 0, 0, 0.24);
const Color fillMutedLight = Color.fromRGBO(0, 0, 0, 0.12);
const Color fillFaintLight = Color.fromRGBO(0, 0, 0, 0.04);
const Color fillFaintPressedLight = Color.fromRGBO(0, 0, 0, 0.08);
const Color fillBaseGreyLight = Color.fromRGBO(242, 242, 242, 1);

const Color fillBaseDark = Color.fromRGBO(255, 255, 255, 1);
const Color fillBasePressedDark = Color.fromRGBO(255, 255, 255, 0.9);
const Color fillStrongDark = Color.fromRGBO(255, 255, 255, 0.32);
const Color fillMutedDark = Color.fromRGBO(255, 255, 255, 0.16);
const Color fillFaintDark = Color.fromRGBO(255, 255, 255, 0.12);
const Color fillFaintPressedDark = Color.fromRGBO(255, 255, 255, 0.06);
const Color fillBaseGreyDark = Color.fromRGBO(66, 66, 66, 1);

// Stroke Colors
const Color strokeBaseLight = Color.fromRGBO(0, 0, 0, 1);
const Color strokeMutedLight = Color.fromRGBO(0, 0, 0, 0.24);
const Color strokeFaintLight = Color.fromRGBO(0, 0, 0, 0.12);
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

// Other colors
const Color tabIconLight = Color.fromRGBO(0, 0, 0, 0.85);
const Color tabIconDark = Color.fromRGBO(255, 255, 255, 0.80);

// Menu item icon stroke colors
const Color menuItemIconStrokeLight = Color(0xFF979797);
const Color menuItemIconStrokeDark = Color.fromRGBO(255, 255, 255, 1);

// Fixed Colors

const Color fixedStrokeMutedWhite = Color.fromRGBO(255, 255, 255, 0.50);
const Color strokeSolidMutedLight = Color.fromRGBO(147, 147, 147, 1);
const Color strokeSolidFaintLight = Color.fromRGBO(221, 221, 221, 1);

// QR Code specific - always light for scanability
const Color qrBoxColor = Color.fromRGBO(245, 245, 247, 1);

const Color _primary700 = Color.fromRGBO(0, 179, 60, 1);
const Color _primary500 = Color.fromRGBO(29, 185, 84, 1);
const Color _primary400 = Color.fromRGBO(38, 203, 95, 1);
const Color _primary300 = Color.fromRGBO(1, 222, 77, 1);

const Color _warning700 = Color.fromRGBO(234, 63, 63, 1);
const Color _warning500 = Color.fromRGBO(255, 101, 101, 1);
const Color warning500 = Color.fromRGBO(255, 101, 101, 1);
const Color _warning400 = Color.fromRGBO(255, 111, 111, 1);
const Color _warning800 = Color(0xFFF53434);

const Color _caution500 = Color.fromRGBO(255, 194, 71, 1);

const Color _golden700 = Color(0xFFFDB816);
const Color _golden500 = Color(0xFFFFC336);

// Green Colors
const Color green = Color.fromRGBO(8, 194, 37, 1);
const Color greenLightLight = Color.fromRGBO(231, 246, 233, 1);
const Color greenLightDark = Color.fromRGBO(33, 33, 33, 1);
const Color greenDark = Color.fromRGBO(6, 157, 30, 1);
const Color greenDarker = Color.fromRGBO(5, 124, 24, 1);
const Color greenStrokeLight = Color.fromRGBO(186, 236, 194, 1);
const Color greenStrokeDark = Color.fromRGBO(28, 65, 34, 1);

// Red Colors
const Color red = Color.fromRGBO(246, 58, 58, 1);
const Color redLightLight = Color.fromRGBO(250, 235, 235, 1);
const Color redLightDark = Color.fromRGBO(33, 33, 33, 1);
const Color redDark = Color.fromRGBO(221, 52, 52, 1);
const Color redDarker = Color.fromRGBO(197, 46, 46, 1);

// Fill Colors
const Color fillLight = Color.fromRGBO(255, 255, 255, 1);
const Color fillDark = Color.fromRGBO(33, 33, 33, 1);

const Color fillDarkLight = Color.fromRGBO(245, 245, 245, 1);
const Color fillDarkDark = Color.fromRGBO(10, 10, 10, 1);

const Color fillDarkerLight = Color.fromRGBO(233, 233, 233, 1);
const Color fillDarkerDark = Color.fromRGBO(20, 20, 20, 1);

const Color fillDarkestLight = Color.fromRGBO(210, 210, 210, 1);
const Color fillDarkestDark = Color.fromRGBO(41, 41, 41, 1);

const Color fillReverseLight = Color.fromRGBO(0, 0, 0, 1);
const Color fillReverseDark = Color.fromRGBO(255, 255, 255, 1);

// Content Colors
const Color contentLight = Color.fromRGBO(0, 0, 0, 1);
const Color contentDark = Color.fromRGBO(255, 255, 255, 1);

const Color contentDarkLight = Color.fromRGBO(26, 26, 26, 1);
const Color contentDarkDark = Color.fromRGBO(229, 229, 229, 1);

const Color contentDarkerLight = Color.fromRGBO(21, 21, 21, 1);
const Color contentDarkerDark = Color.fromRGBO(204, 204, 204, 1);

const Color contentLightLight = Color.fromRGBO(102, 102, 102, 1);
const Color contentLightDark = Color.fromRGBO(153, 153, 153, 1);

const Color contentLighterLight = Color.fromRGBO(150, 150, 150, 1);
const Color contentLighterDark = Color.fromRGBO(150, 150, 150, 1);

const Color contentLightestLight = Color.fromRGBO(222, 222, 222, 1);
const Color contentLightestDark = Color.fromRGBO(10, 10, 10, 1);

const Color contentReverseLight = Color.fromRGBO(255, 255, 255, 1);
const Color contentReverseDark = Color.fromRGBO(0, 0, 0, 1);

// Stroke Colors
const Color strokeLight = Color.fromRGBO(235, 235, 235, 1);
const Color strokeDark = Color.fromRGBO(20, 20, 20, 1);

const Color strokeDarkLight = Color.fromRGBO(224, 224, 224, 1);
const Color strokeDarkDark = Color.fromRGBO(62, 62, 62, 1);
