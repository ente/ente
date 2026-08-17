import 'package:ente_auth/theme/colors.dart';
import 'package:flutter/material.dart';

const FontWeight _regularWeight = FontWeight.w500;
const FontWeight _boldWeight = FontWeight.w600;
const String _fontFamily = 'Inter';

const TextStyle brandStyleSmall = TextStyle(
  fontWeight: FontWeight.bold,
  fontFamily: 'Montserrat',
  fontSize: 21,
);

const TextStyle brandStyleMedium = TextStyle(
  fontWeight: FontWeight.bold,
  fontFamily: 'Montserrat',
  fontSize: 24,
);

const TextStyle h1 = TextStyle(
  fontSize: 48,
  height: 48 / 28,
  fontWeight: _regularWeight,
  fontFamily: _fontFamily,
);
const TextStyle h2 = TextStyle(
  fontSize: 32,
  height: 39 / 32.0,
  fontWeight: _regularWeight,
  fontFamily: _fontFamily,
);
const TextStyle h3 = TextStyle(
  fontSize: 24,
  height: 29 / 24.0,
  fontWeight: _regularWeight,
  fontFamily: _fontFamily,
);
const TextStyle large = TextStyle(
  fontSize: 18,
  height: 22 / 18.0,
  fontWeight: _regularWeight,
  fontFamily: _fontFamily,
);
const TextStyle body = TextStyle(
  fontSize: 16,
  height: 20 / 16.0,
  fontWeight: _regularWeight,
  fontFamily: _fontFamily,
);
const TextStyle small = TextStyle(
  fontSize: 14,
  height: 17 / 14.0,
  fontWeight: _regularWeight,
  fontFamily: _fontFamily,
);
const TextStyle mini = TextStyle(
  fontSize: 12,
  height: 15 / 12.0,
  fontWeight: _regularWeight,
  fontFamily: _fontFamily,
);
const TextStyle tiny = TextStyle(
  fontSize: 10,
  height: 12 / 10.0,
  fontWeight: _regularWeight,
  fontFamily: _fontFamily,
);

class EnteTextTheme {
  final TextStyle h1;
  final TextStyle h1Bold;
  final TextStyle h2;
  final TextStyle h2Bold;
  final TextStyle h3;
  final TextStyle h3Bold;
  final TextStyle large;
  final TextStyle largeBold;
  final TextStyle body;
  final TextStyle bodyBold;
  final TextStyle small;
  final TextStyle smallBold;
  final TextStyle mini;
  final TextStyle miniBold;
  final TextStyle tiny;
  final TextStyle tinyBold;
  final TextStyle brandSmall;
  final TextStyle brandMedium;

  final TextStyle h1Muted;
  final TextStyle h2Muted;
  final TextStyle h3Muted;
  final TextStyle largeMuted;
  final TextStyle bodyMuted;
  final TextStyle smallMuted;
  final TextStyle miniMuted;
  final TextStyle miniBoldMuted;
  final TextStyle tinyMuted;

  final TextStyle h1Faint;
  final TextStyle h2Faint;
  final TextStyle h3Faint;
  final TextStyle largeFaint;
  final TextStyle bodyFaint;
  final TextStyle smallFaint;
  final TextStyle miniFaint;
  final TextStyle tinyFaint;

  const EnteTextTheme({
    required this.h1,
    required this.h1Bold,
    required this.h2,
    required this.h2Bold,
    required this.h3,
    required this.h3Bold,
    required this.large,
    required this.largeBold,
    required this.body,
    required this.bodyBold,
    required this.small,
    required this.smallBold,
    required this.mini,
    required this.miniBold,
    required this.tiny,
    required this.tinyBold,
    required this.brandSmall,
    required this.brandMedium,
    required this.h1Muted,
    required this.h2Muted,
    required this.h3Muted,
    required this.largeMuted,
    required this.bodyMuted,
    required this.smallMuted,
    required this.miniMuted,
    required this.miniBoldMuted,
    required this.tinyMuted,
    required this.h1Faint,
    required this.h2Faint,
    required this.h3Faint,
    required this.largeFaint,
    required this.bodyFaint,
    required this.smallFaint,
    required this.miniFaint,
    required this.tinyFaint,
  });
}

EnteTextTheme lightTextTheme = _buildEnteTextStyle(
  textBaseLight,
  textMutedLight,
  textFaintLight,
);

EnteTextTheme darkTextTheme = _buildEnteTextStyle(
  textBaseDark,
  textMutedDark,
  textFaintDark,
);

EnteTextTheme _buildEnteTextStyle(
  Color color,
  Color textMuted,
  Color textFaint,
) {
  return EnteTextTheme(
    h1: h1.copyWith(color: color),
    h1Bold: h1.copyWith(color: color, fontWeight: _boldWeight),
    h2: h2.copyWith(color: color),
    h2Bold: h2.copyWith(color: color, fontWeight: _boldWeight),
    h3: h3.copyWith(color: color),
    h3Bold: h3.copyWith(color: color, fontWeight: _boldWeight),
    large: large.copyWith(color: color),
    largeBold: large.copyWith(color: color, fontWeight: _boldWeight),
    body: body.copyWith(color: color),
    bodyBold: body.copyWith(color: color, fontWeight: _boldWeight),
    small: small.copyWith(color: color),
    smallBold: small.copyWith(color: color, fontWeight: _boldWeight),
    mini: mini.copyWith(color: color),
    miniBold: mini.copyWith(color: color, fontWeight: _boldWeight),
    tiny: tiny.copyWith(color: color),
    tinyBold: tiny.copyWith(color: color, fontWeight: _boldWeight),
    brandSmall: brandStyleSmall.copyWith(color: color),
    brandMedium: brandStyleMedium.copyWith(color: color),
    h1Muted: h1.copyWith(color: textMuted),
    h2Muted: h2.copyWith(color: textMuted),
    h3Muted: h3.copyWith(color: textMuted),
    largeMuted: large.copyWith(color: textMuted),
    bodyMuted: body.copyWith(color: textMuted),
    smallMuted: small.copyWith(color: textMuted),
    miniMuted: mini.copyWith(color: textMuted),
    miniBoldMuted: mini.copyWith(color: textMuted, fontWeight: _boldWeight),
    tinyMuted: tiny.copyWith(color: textMuted),
    h1Faint: h1.copyWith(color: textFaint),
    h2Faint: h2.copyWith(color: textFaint),
    h3Faint: h3.copyWith(color: textFaint),
    largeFaint: large.copyWith(color: textFaint),
    bodyFaint: body.copyWith(color: textFaint),
    smallFaint: small.copyWith(color: textFaint),
    miniFaint: mini.copyWith(color: textFaint),
    tinyFaint: tiny.copyWith(color: textFaint),
  );
}
