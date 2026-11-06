import "package:ente_components/theme/text_styles.dart";
import "package:flutter/painting.dart";
import "package:photos/services/rewind/rewind_asset_store.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";

abstract final class RewindTextStyles {
  static TextStyle display(
    double size, {
    Color color = RewindColors.cream,
    double height = 0.95,
    double letterSpacing = 0,
  }) => TextStyle(
    inherit: false,
    fontFamily: RewindAssetStore.lilitaOne,
    fontSize: size,
    height: height,
    letterSpacing: letterSpacing,
    color: color,
    leadingDistribution: TextLeadingDistribution.even,
  );

  static TextStyle body(
    double size, {
    Color color = RewindColors.cream,
    double height = 1.3,
    FontWeight weight = FontWeight.w700,
    double letterSpacing = 0,
  }) => TextStyle(
    fontFamily: TextStyles.outfitFontFamily,
    package: TextStyles.fontPackage,
    fontSize: size,
    height: height,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    color: color,
    leadingDistribution: TextLeadingDistribution.even,
  );

  static TextStyle numeral(double size, {Color color = RewindColors.cream}) =>
      TextStyle(
        inherit: false,
        fontFamily: RewindAssetStore.nunito,
        fontWeight: FontWeight.w900,
        fontSize: size,
        height: 0.95,
        color: color,
        leadingDistribution: TextLeadingDistribution.even,
      );

  static TextStyle tag(double size, {Color color = RewindColors.ink}) =>
      TextStyle(
        inherit: false,
        fontFamily: RewindAssetStore.bagelFatOne,
        fontSize: size,
        height: 1.05,
        color: color,
        leadingDistribution: TextLeadingDistribution.even,
      );

  static TextStyle film(double size, {Color color = const Color(0xD9151515)}) =>
      TextStyle(
        inherit: false,
        fontFamily: RewindAssetStore.courierPrime,
        fontSize: size,
        letterSpacing: 1,
        color: color,
      );
}
