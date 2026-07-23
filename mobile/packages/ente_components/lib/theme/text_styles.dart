import 'package:flutter/material.dart';

/// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=7672-54672&m=dev
/// Section: Text styles
/// Specs: Inter body scale, Outfit display title scale, letter spacing 0.
/// Display-1 32/40, Display-2 24/32, Display-3 20/28; H1 20/28, H2 18/24,
/// body 14/20, mini 12/16, tiny 10/12.
class TextStyles {
  const TextStyles._();

  static const String fontFamily = 'Inter';
  static const String outfitFontFamily = 'Outfit';
  static const String fontPackage = 'ente_components';

  static const display1 = TextStyle(
    fontFamily: outfitFontFamily,
    package: fontPackage,
    fontSize: 32,
    height: 40 / 32,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  static const display2 = TextStyle(
    fontFamily: outfitFontFamily,
    package: fontPackage,
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  static const h1 = TextStyle(
    fontFamily: fontFamily,
    package: fontPackage,
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );

  static const h1Bold = TextStyle(
    fontFamily: fontFamily,
    package: fontPackage,
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  static const h2 = TextStyle(
    fontFamily: fontFamily,
    package: fontPackage,
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  static const large = TextStyle(
    fontFamily: fontFamily,
    package: fontPackage,
    fontSize: 16,
    height: 20 / 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  static const display3 = TextStyle(
    fontFamily: outfitFontFamily,
    package: fontPackage,
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  static const bodyBold = TextStyle(
    fontFamily: fontFamily,
    package: fontPackage,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  static const body = TextStyle(
    fontFamily: fontFamily,
    package: fontPackage,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
  );

  static const bodyLink = TextStyle(
    fontFamily: fontFamily,
    package: fontPackage,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    decoration: TextDecoration.underline,
  );

  static const mini = TextStyle(
    fontFamily: fontFamily,
    package: fontPackage,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
  );

  static const tiny = TextStyle(
    fontFamily: fontFamily,
    package: fontPackage,
    fontSize: 10,
    height: 12 / 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
  );
}
