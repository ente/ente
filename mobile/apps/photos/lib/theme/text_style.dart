import 'package:ente_components/theme/text_styles.dart' as component;
import 'package:flutter/material.dart';
import 'package:photos/theme/colors.dart';

const FontWeight _regularWeight = FontWeight.w500;
const FontWeight _boldWeight = FontWeight.w600;
const String _fontFamily = 'Inter';

// h1-h3 stay on the legacy Photos scale because ente_components does not
// define matching 48/32/24 styles yet.
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
const TextStyle h4 = component.TextStyles.h1Bold;
const TextStyle large = component.TextStyles.h2;
const TextStyle body = component.TextStyles.large;
const TextStyle small = component.TextStyles.body;
const TextStyle mini = component.TextStyles.mini;
const TextStyle tiny = component.TextStyles.tiny;

const TextStyle _h4Bold = component.TextStyles.h1;
const TextStyle _smallBold = component.TextStyles.bodyBold;

class EnteTextTheme {
  final TextStyle h1;
  final TextStyle h1Bold;
  final TextStyle h2;
  final TextStyle h2Bold;
  final TextStyle h3;
  final TextStyle h3Bold;
  final TextStyle h4;
  final TextStyle h4Bold;
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
  // textMuted variants
  final TextStyle h1Muted;
  final TextStyle h2Muted;
  final TextStyle h3Muted;
  final TextStyle h4Muted;
  final TextStyle largeMuted;
  final TextStyle bodyMuted;
  final TextStyle smallMuted;
  final TextStyle miniMuted;
  final TextStyle miniBoldMuted;
  final TextStyle tinyMuted;

  // textFaint variants
  final TextStyle h1Faint;
  final TextStyle h2Faint;
  final TextStyle h3Faint;
  final TextStyle h4Faint;
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
    required this.h4,
    required this.h4Bold,
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
    required this.h1Muted,
    required this.h2Muted,
    required this.h3Muted,
    required this.h4Muted,
    required this.largeMuted,
    required this.bodyMuted,
    required this.smallMuted,
    required this.miniMuted,
    required this.miniBoldMuted,
    required this.tinyMuted,
    required this.h1Faint,
    required this.h2Faint,
    required this.h3Faint,
    required this.h4Faint,
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
  // Text colors still come from the legacy Photos color tokens; this adapter
  // only sources the matching typography styles from ente_components.
  return EnteTextTheme(
    h1: h1.copyWith(color: color),
    h1Bold: h1.copyWith(color: color, fontWeight: _boldWeight),
    h2: h2.copyWith(color: color),
    h2Bold: h2.copyWith(color: color, fontWeight: _boldWeight),
    h3: h3.copyWith(color: color),
    h3Bold: h3.copyWith(color: color, fontWeight: _boldWeight),
    h4: h4.copyWith(color: color),
    h4Bold: _h4Bold.copyWith(color: color),
    large: large.copyWith(color: color),
    largeBold: large.copyWith(color: color, fontWeight: _boldWeight),
    body: body.copyWith(color: color),
    bodyBold: body.copyWith(color: color, fontWeight: _boldWeight),
    small: small.copyWith(color: color),
    smallBold: _smallBold.copyWith(color: color),
    mini: mini.copyWith(color: color),
    miniBold: mini.copyWith(color: color, fontWeight: _boldWeight),
    tiny: tiny.copyWith(color: color),
    tinyBold: tiny.copyWith(color: color, fontWeight: _boldWeight),
    h1Muted: h1.copyWith(color: textMuted),
    h2Muted: h2.copyWith(color: textMuted),
    h3Muted: h3.copyWith(color: textMuted),
    h4Muted: h4.copyWith(color: textMuted),
    largeMuted: large.copyWith(color: textMuted),
    bodyMuted: body.copyWith(color: textMuted),
    smallMuted: small.copyWith(color: textMuted),
    miniMuted: mini.copyWith(color: textMuted),
    miniBoldMuted: mini.copyWith(color: textMuted, fontWeight: _boldWeight),
    tinyMuted: tiny.copyWith(color: textMuted),
    h1Faint: h1.copyWith(color: textFaint),
    h2Faint: h2.copyWith(color: textFaint),
    h3Faint: h3.copyWith(color: textFaint),
    h4Faint: h4.copyWith(color: textFaint),
    largeFaint: large.copyWith(color: textFaint),
    bodyFaint: body.copyWith(color: textFaint),
    smallFaint: small.copyWith(color: textFaint),
    miniFaint: mini.copyWith(color: textFaint),
    tinyFaint: tiny.copyWith(color: textFaint),
  );
}
