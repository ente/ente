import "package:ente_ui/theme/theme_config.dart";
import 'package:flutter/material.dart';

/// This color scheme provides all the colors needed for a modern Flutter app,
/// including background, text, fill, stroke, and accent colors for both light
/// and dark themes.
///
/// Apps can easily customize the primary colors using the factory constructors:
///
/// ```dart
/// // Create a light theme with custom primary colors
/// final customLightScheme = EnteColorScheme.light(
///   primary700: Color(0xFF1976D2),
///   primary500: Color(0xFF2196F3),
///   primary400: Color(0xFF42A5F5),
///   primary300: Color(0xFF64B5F6),
/// );
///
/// // Create a dark theme with custom primary colors
/// final customDarkScheme = EnteColorScheme.dark(
///   primary700: Color(0xFF1976D2),
///   primary500: Color(0xFF2196F3),
///   primary400: Color(0xFF42A5F5),
///   primary300: Color(0xFF64B5F6),
/// );
/// ```
class EnteColorScheme extends ThemeExtension<EnteColorScheme> {
  factory EnteColorScheme.fromApp(
    EnteApp app, {
    Brightness brightness = Brightness.light,
  }) {
    final appColors = switch (app) {
      EnteApp.auth => (
        primary700: const Color(0xFF722ED1),
        primary500: const Color(0xFF8F33D6),
        primary400: const Color(0xFF7A29C1),
        primary300: const Color(0xFF984DF4),
        gradientButtonBgColor: const Color(0xFF722ED1),
        gradientButtonBgColors: const [Color(0xFF722ED1), Color(0xFF8F33D6)],
      ),
      EnteApp.locker => (
        primary700: const Color.fromRGBO(16, 113, 255, 1),
        primary500: const Color.fromARGB(255, 102, 178, 255),
        primary400: const Color.fromARGB(255, 52, 152, 255),
        primary300: const Color.fromARGB(255, 236, 242, 250),
        gradientButtonBgColor: const Color.fromRGBO(0, 122, 255, 1),
        gradientButtonBgColors: const [
          Color.fromRGBO(0, 122, 255, 1),
          Color.fromRGBO(52, 152, 255, 1),
        ],
      ),
      EnteApp.photos => (
        primary700: const Color.fromRGBO(8, 194, 37, 1),
        primary500: const Color.fromRGBO(8, 194, 37, 1),
        primary400: const Color.fromRGBO(6, 157, 30, 1),
        primary300: const Color.fromRGBO(5, 124, 24, 1),
        gradientButtonBgColor: const Color.fromRGBO(8, 194, 37, 1),
        gradientButtonBgColors: const [
          Color.fromRGBO(8, 194, 37, 1),
          Color.fromRGBO(6, 157, 30, 1),
        ],
      ),
    };

    return brightness == Brightness.light
        ? EnteColorScheme.light(
            primary700: appColors.primary700,
            primary500: appColors.primary500,
            primary400: appColors.primary400,
            primary300: appColors.primary300,
            gradientButtonBgColor: appColors.gradientButtonBgColor,
            gradientButtonBgColors: appColors.gradientButtonBgColors,
          )
        : EnteColorScheme.dark(
            primary700: appColors.primary700,
            primary500: appColors.primary500,
            primary400: appColors.primary400,
            primary300: appColors.primary300,
            gradientButtonBgColor: appColors.gradientButtonBgColor,
            gradientButtonBgColors: appColors.gradientButtonBgColors,
          );
  }

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

  // Gradient Button
  final Color gradientButtonBgColor;
  final List<Color> gradientButtonBgColors;

  // Additional colors from ente_theme_data
  final Color fabForegroundColor;
  final Color fabBackgroundColor;
  final Color boxSelectColor;
  final Color boxUnSelectColor;
  final Color alternativeColor;
  final Color dynamicFABBackgroundColor;
  final Color dynamicFABTextColor;
  final Color recoveryKeyBoxColor;
  final Color frostyBlurBackdropFilterColor;
  final Color iconColor;
  final Color bgColorForQuestions;
  final Color greenText;
  final Color cupertinoPickerTopColor;
  final Color stepProgressUnselectedColor;
  final Color gNavBackgroundColor;
  final Color gNavBarActiveColor;
  final Color gNavIconColor;
  final Color gNavActiveIconColor;
  final Color galleryThumbBackgroundColor;
  final Color galleryThumbDrawColor;
  final Color backupEnabledBgColor;
  final Color dotsIndicatorActiveColor;
  final Color dotsIndicatorInactiveColor;
  final Color toastTextColor;
  final Color toastBackgroundColor;
  final Color subTextColor;
  final Color themeSwitchInactiveIconColor;
  final Color searchResultsColor;
  final Color mutedTextColor;
  final Color searchResultsBackgroundColor;
  final Color codeCardBackgroundColor;
  final Color primaryColor;
  final Color surface;

  //other colors
  final List<Color> avatarColors;

  //golden colors
  final Color golden700;
  final Color golden500;

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
    this.iconButtonColor,
    this.gradientButtonBgColor,
    this.gradientButtonBgColors,
    this.primary700,
    this.primary500,
    this.primary400,
    this.primary300,
    this.avatarColors, {
    this.warning700 = _warning700,
    this.warning800 = _warning800,
    this.warning500 = _warning500,
    this.warning400 = _warning700,
    this.caution500 = _caution500,
    this.fabForegroundColor = _defaultFabForegroundColor,
    this.fabBackgroundColor = _defaultFabBackgroundColor,
    this.boxSelectColor = _defaultBoxSelectColor,
    this.boxUnSelectColor = _defaultBoxUnSelectColor,
    this.alternativeColor = _defaultAlternativeColor,
    this.dynamicFABBackgroundColor = _defaultDynamicFABBackgroundColor,
    this.dynamicFABTextColor = _defaultDynamicFABTextColor,
    this.recoveryKeyBoxColor = _defaultRecoveryKeyBoxColor,
    this.frostyBlurBackdropFilterColor = _defaultFrostyBlurBackdropFilterColor,
    this.iconColor = _defaultIconColor,
    this.bgColorForQuestions = _defaultBgColorForQuestions,
    this.greenText = _defaultGreenText,
    this.cupertinoPickerTopColor = _defaultCupertinoPickerTopColor,
    this.stepProgressUnselectedColor = _defaultStepProgressUnselectedColor,
    this.gNavBackgroundColor = _defaultGNavBackgroundColor,
    this.gNavBarActiveColor = _defaultGNavBarActiveColor,
    this.gNavIconColor = _defaultGNavIconColor,
    this.gNavActiveIconColor = _defaultGNavActiveIconColor,
    this.galleryThumbBackgroundColor = _defaultGalleryThumbBackgroundColor,
    this.galleryThumbDrawColor = _defaultGalleryThumbDrawColor,
    this.backupEnabledBgColor = _defaultBackupEnabledBgColor,
    this.dotsIndicatorActiveColor = _defaultDotsIndicatorActiveColor,
    this.dotsIndicatorInactiveColor = _defaultDotsIndicatorInactiveColor,
    this.toastTextColor = _defaultToastTextColor,
    this.toastBackgroundColor = _defaultToastBackgroundColor,
    this.subTextColor = _defaultSubTextColor,
    this.themeSwitchInactiveIconColor = _defaultThemeSwitchInactiveIconColor,
    this.searchResultsColor = _defaultSearchResultsColor,
    this.mutedTextColor = _defaultMutedTextColor,
    this.searchResultsBackgroundColor = _defaultSearchResultsBackgroundColor,
    this.codeCardBackgroundColor = _defaultCodeCardBackgroundColor,
    this.primaryColor = _defaultPrimaryColor,
    this.surface = _defaultPrimaryColor,
    this.golden700 = _golden700,
    this.golden500 = _golden500,
  });

  /// Factory constructor for light theme with customizable primary colors
  factory EnteColorScheme.light({
    Color? primary700,
    Color? primary500,
    Color? primary400,
    Color? primary300,
    Color? iconButtonColor,
    Color? gradientButtonBgColor,
    List<Color>? gradientButtonBgColors,
    Color? warning700,
    Color? warning500,
    Color? warning400,
    Color? warning800,
    Color? caution500,
  }) {
    return EnteColorScheme(
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
      iconButtonColor ?? _defaultIconButtonColor,
      gradientButtonBgColor ?? _defaultGradientButtonBgColor,
      gradientButtonBgColors ?? _defaultGradientButtonBgColors,
      primary700 ?? _defaultPrimary700,
      primary500 ?? _defaultPrimary500,
      primary400 ?? _defaultPrimary400,
      primary300 ?? _defaultPrimary300,
      avatarLight,
      alternativeColor: primary400 ?? _defaultAlternativeColor,
      warning700: warning700 ?? _warning700,
      warning800: warning800 ?? _warning800,
      warning500: warning500 ?? _warning500,
      warning400: warning400 ?? _warning700,
      caution500: caution500 ?? _caution500,
    );
  }

  /// Factory constructor for dark theme with customizable primary colors
  factory EnteColorScheme.dark({
    Color? primary700,
    Color? primary500,
    Color? primary400,
    Color? primary300,
    Color? iconButtonColor,
    Color? gradientButtonBgColor,
    List<Color>? gradientButtonBgColors,
    Color? warning700,
    Color? warning500,
    Color? warning400,
    Color? warning800,
    Color? caution500,
  }) {
    return EnteColorScheme(
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
      iconButtonColor ?? _defaultIconButtonColor,
      gradientButtonBgColor ?? _defaultGradientButtonBgColor,
      gradientButtonBgColors ?? _defaultGradientButtonBgColors,
      primary700 ?? _defaultPrimary700,
      primary500 ?? _defaultPrimary500,
      primary400 ?? _defaultPrimary400,
      primary300 ?? _defaultPrimary300,
      avatarDark,
      alternativeColor: primary400 ?? _defaultAlternativeColor,
      warning700: warning700 ?? _warning700,
      warning800: warning800 ?? _warning800,
      warning500: warning500 ?? _warning500,
      warning400: warning400 ?? _warning700,
      caution500: caution500 ?? _caution500,
    );
  }

  Null get inverseEnteTheme => null;

  @override
  EnteColorScheme copyWith({
    Color? backgroundBase,
    Color? backgroundElevated,
    Color? backgroundElevated2,
    Color? backdropBase,
    Color? backdropBaseMute,
    Color? backdropFaint,
    Color? textBase,
    Color? textMuted,
    Color? textFaint,
    Color? fillBase,
    Color? fillBasePressed,
    Color? fillMuted,
    Color? fillFaint,
    Color? fillFaintPressed,
    Color? strokeBase,
    Color? strokeMuted,
    Color? strokeFaint,
    Color? strokeFainter,
    Color? blurStrokeBase,
    Color? blurStrokeFaint,
    Color? blurStrokePressed,
    Color? primary700,
    Color? primary500,
    Color? primary400,
    Color? primary300,
    Color? iconButtonColor,
    Color? warning700,
    Color? warning500,
    Color? warning400,
    Color? warning800,
    Color? caution500,
    Color? gradientButtonBgColor,
    List<Color>? gradientButtonBgColors,
    Color? fabForegroundColor,
    Color? fabBackgroundColor,
    Color? boxSelectColor,
    Color? boxUnSelectColor,
    Color? alternativeColor,
    Color? dynamicFABBackgroundColor,
    Color? dynamicFABTextColor,
    Color? recoveryKeyBoxColor,
    Color? frostyBlurBackdropFilterColor,
    Color? iconColor,
    Color? bgColorForQuestions,
    Color? greenText,
    Color? cupertinoPickerTopColor,
    Color? stepProgressUnselectedColor,
    Color? gNavBackgroundColor,
    Color? gNavBarActiveColor,
    Color? gNavIconColor,
    Color? gNavActiveIconColor,
    Color? galleryThumbBackgroundColor,
    Color? galleryThumbDrawColor,
    Color? backupEnabledBgColor,
    Color? dotsIndicatorActiveColor,
    Color? dotsIndicatorInactiveColor,
    Color? toastTextColor,
    Color? toastBackgroundColor,
    Color? subTextColor,
    Color? themeSwitchInactiveIconColor,
    Color? searchResultsColor,
    Color? mutedTextColor,
    Color? searchResultsBackgroundColor,
    Color? codeCardBackgroundColor,
    Color? primaryColor,
    List<Color>? avatarColors,
  }) {
    return EnteColorScheme(
      backgroundBase ?? this.backgroundBase,
      backgroundElevated ?? this.backgroundElevated,
      backgroundElevated2 ?? this.backgroundElevated2,
      backdropBase ?? this.backdropBase,
      backdropBaseMute ?? this.backdropBaseMute,
      backdropFaint ?? this.backdropFaint,
      textBase ?? this.textBase,
      textMuted ?? this.textMuted,
      textFaint ?? this.textFaint,
      fillBase ?? this.fillBase,
      fillBasePressed ?? this.fillBasePressed,
      fillMuted ?? this.fillMuted,
      fillFaint ?? this.fillFaint,
      fillFaintPressed ?? this.fillFaintPressed,
      strokeBase ?? this.strokeBase,
      strokeMuted ?? this.strokeMuted,
      strokeFaint ?? this.strokeFaint,
      strokeFainter ?? this.strokeFainter,
      blurStrokeBase ?? this.blurStrokeBase,
      blurStrokeFaint ?? this.blurStrokeFaint,
      blurStrokePressed ?? this.blurStrokePressed,
      iconButtonColor ?? this.iconButtonColor,
      gradientButtonBgColor ?? this.gradientButtonBgColor,
      gradientButtonBgColors ?? this.gradientButtonBgColors,
      primary700 ?? this.primary700,
      primary500 ?? this.primary500,
      primary400 ?? this.primary400,
      primary300 ?? this.primary300,
      avatarColors ?? this.avatarColors,
      warning700: warning700 ?? this.warning700,
      warning800: warning800 ?? this.warning800,
      warning500: warning500 ?? this.warning500,
      warning400: warning400 ?? this.warning400,
      caution500: caution500 ?? this.caution500,
      fabForegroundColor: fabForegroundColor ?? this.fabForegroundColor,
      fabBackgroundColor: fabBackgroundColor ?? this.fabBackgroundColor,
      boxSelectColor: boxSelectColor ?? this.boxSelectColor,
      boxUnSelectColor: boxUnSelectColor ?? this.boxUnSelectColor,
      alternativeColor: alternativeColor ?? this.alternativeColor,
      dynamicFABBackgroundColor:
          dynamicFABBackgroundColor ?? this.dynamicFABBackgroundColor,
      dynamicFABTextColor: dynamicFABTextColor ?? this.dynamicFABTextColor,
      recoveryKeyBoxColor: recoveryKeyBoxColor ?? this.recoveryKeyBoxColor,
      frostyBlurBackdropFilterColor:
          frostyBlurBackdropFilterColor ?? this.frostyBlurBackdropFilterColor,
      iconColor: iconColor ?? this.iconColor,
      bgColorForQuestions: bgColorForQuestions ?? this.bgColorForQuestions,
      greenText: greenText ?? this.greenText,
      cupertinoPickerTopColor:
          cupertinoPickerTopColor ?? this.cupertinoPickerTopColor,
      stepProgressUnselectedColor:
          stepProgressUnselectedColor ?? this.stepProgressUnselectedColor,
      gNavBackgroundColor: gNavBackgroundColor ?? this.gNavBackgroundColor,
      gNavBarActiveColor: gNavBarActiveColor ?? this.gNavBarActiveColor,
      gNavIconColor: gNavIconColor ?? this.gNavIconColor,
      gNavActiveIconColor: gNavActiveIconColor ?? this.gNavActiveIconColor,
      galleryThumbBackgroundColor:
          galleryThumbBackgroundColor ?? this.galleryThumbBackgroundColor,
      galleryThumbDrawColor:
          galleryThumbDrawColor ?? this.galleryThumbDrawColor,
      backupEnabledBgColor: backupEnabledBgColor ?? this.backupEnabledBgColor,
      dotsIndicatorActiveColor:
          dotsIndicatorActiveColor ?? this.dotsIndicatorActiveColor,
      dotsIndicatorInactiveColor:
          dotsIndicatorInactiveColor ?? this.dotsIndicatorInactiveColor,
      toastTextColor: toastTextColor ?? this.toastTextColor,
      toastBackgroundColor: toastBackgroundColor ?? this.toastBackgroundColor,
      subTextColor: subTextColor ?? this.subTextColor,
      themeSwitchInactiveIconColor:
          themeSwitchInactiveIconColor ?? this.themeSwitchInactiveIconColor,
      searchResultsColor: searchResultsColor ?? this.searchResultsColor,
      mutedTextColor: mutedTextColor ?? this.mutedTextColor,
      searchResultsBackgroundColor:
          searchResultsBackgroundColor ?? this.searchResultsBackgroundColor,
      codeCardBackgroundColor:
          codeCardBackgroundColor ?? this.codeCardBackgroundColor,
      primaryColor: primaryColor ?? this.primaryColor,
    );
  }

  @override
  EnteColorScheme lerp(ThemeExtension<EnteColorScheme>? other, double t) {
    if (other is! EnteColorScheme) {
      return this;
    }

    return EnteColorScheme(
      Color.lerp(backgroundBase, other.backgroundBase, t)!,
      Color.lerp(backgroundElevated, other.backgroundElevated, t)!,
      Color.lerp(backgroundElevated2, other.backgroundElevated2, t)!,
      Color.lerp(backdropBase, other.backdropBase, t)!,
      Color.lerp(backdropBaseMute, other.backdropBaseMute, t)!,
      Color.lerp(backdropFaint, other.backdropFaint, t)!,
      Color.lerp(textBase, other.textBase, t)!,
      Color.lerp(textMuted, other.textMuted, t)!,
      Color.lerp(textFaint, other.textFaint, t)!,
      Color.lerp(fillBase, other.fillBase, t)!,
      Color.lerp(fillBasePressed, other.fillBasePressed, t)!,
      Color.lerp(fillMuted, other.fillMuted, t)!,
      Color.lerp(fillFaint, other.fillFaint, t)!,
      Color.lerp(fillFaintPressed, other.fillFaintPressed, t)!,
      Color.lerp(strokeBase, other.strokeBase, t)!,
      Color.lerp(strokeMuted, other.strokeMuted, t)!,
      Color.lerp(strokeFaint, other.strokeFaint, t)!,
      Color.lerp(strokeFainter, other.strokeFainter, t)!,
      Color.lerp(blurStrokeBase, other.blurStrokeBase, t)!,
      Color.lerp(blurStrokeFaint, other.blurStrokeFaint, t)!,
      Color.lerp(blurStrokePressed, other.blurStrokePressed, t)!,
      Color.lerp(iconButtonColor, other.iconButtonColor, t)!,
      Color.lerp(gradientButtonBgColor, other.gradientButtonBgColor, t)!,
      _lerpColorList(gradientButtonBgColors, other.gradientButtonBgColors, t),
      Color.lerp(primary700, other.primary700, t)!,
      Color.lerp(primary500, other.primary500, t)!,
      Color.lerp(primary400, other.primary400, t)!,
      Color.lerp(primary300, other.primary300, t)!,
      _lerpColorList(avatarColors, other.avatarColors, t),
      warning700: Color.lerp(warning700, other.warning700, t)!,
      warning800: Color.lerp(warning800, other.warning800, t)!,
      warning500: Color.lerp(warning500, other.warning500, t)!,
      warning400: Color.lerp(warning400, other.warning400, t)!,
      caution500: Color.lerp(caution500, other.caution500, t)!,
    );
  }

  /// Helper method to lerp between two color lists
  List<Color> _lerpColorList(List<Color> a, List<Color> b, double t) {
    if (a.length != b.length) {
      return t < 0.5 ? a : b;
    }
    return List.generate(
      a.length,
      (index) => Color.lerp(a[index], b[index], t)!,
    );
  }
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
  _defaultIconButtonColor,
  _defaultGradientButtonBgColor,
  _defaultGradientButtonBgColors,
  _defaultPrimary700,
  _defaultPrimary500,
  _defaultPrimary400,
  _defaultPrimary300,
  avatarLight,
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
  _defaultIconButtonColor,
  _defaultGradientButtonBgColor,
  _defaultGradientButtonBgColors,
  _defaultPrimary700,
  _defaultPrimary500,
  _defaultPrimary400,
  _defaultPrimary300,
  avatarDark,
);

// Background Colors
const Color backgroundBaseLight = Color.fromRGBO(250, 250, 250, 1);
const Color backgroundElevatedLight = Color.fromRGBO(0, 0, 0, 0.04);
const Color backgroundElevated2Light = Color.fromRGBO(250, 250, 250, 1);

const Color backgroundBaseDark = Color.fromRGBO(0, 0, 0, 1);
const Color backgroundElevatedDark = Color.fromRGBO(255, 255, 255, 0.04);
const Color backgroundElevated2Dark = Color.fromRGBO(26, 26, 26, 1);

// Backdrop Colors
const Color backdropBaseLight = Color.fromRGBO(255, 255, 255, 0.92);
const Color backdropMutedLight = Color.fromRGBO(255, 255, 255, 0.75);
const Color backdropFaintLight = Color.fromRGBO(255, 255, 255, 0.30);

const Color backdropBaseDark = Color.fromRGBO(33, 33, 33, 1);
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

// Default Primary Colors
const Color _defaultPrimary700 = Color.fromRGBO(0, 122, 255, 1);
const Color _defaultPrimary500 = Color.fromRGBO(52, 152, 255, 1);
const Color _defaultPrimary400 = Color.fromRGBO(102, 178, 255, 1);
const Color _defaultPrimary300 = Color.fromRGBO(153, 204, 255, 1);

// Default Gradient Colors
const Color _defaultGradientButtonBgColor = Color.fromRGBO(0, 122, 255, 1);
const List<Color> _defaultGradientButtonBgColors = [
  Color.fromRGBO(0, 122, 255, 1),
  Color.fromRGBO(52, 152, 255, 1),
];

// Default Icon Button Color
const Color _defaultIconButtonColor = Color.fromRGBO(0, 122, 255, 1);

// Warning Colors
const Color _warning700 = Color.fromRGBO(245, 52, 52, 1);
const Color _warning500 = Color.fromRGBO(255, 101, 101, 1);
const Color _warning800 = Color(0xFFF53434);
const Color warning500 = Color.fromRGBO(255, 101, 101, 1);
// ignore: unused_element
const Color _warning400 = Color.fromRGBO(255, 111, 111, 1);

// Caution Colors
const Color _caution500 = Color.fromRGBO(255, 194, 71, 1);

// Additional default colors from ente_theme_data
const Color _defaultPrimaryColor = Color(0xFF9610D6);

// FAB Colors - based on brightness-dependent logic from ente_theme_data
const Color _defaultFabForegroundColor = Color.fromRGBO(255, 255, 255, 1);
const Color _defaultFabBackgroundColor = Color.fromRGBO(40, 40, 40, 1);

// Box selection colors
const Color _defaultBoxSelectColor = Color.fromRGBO(67, 186, 108, 1);
const Color _defaultBoxUnSelectColor = Color.fromRGBO(240, 240, 240, 1);

// Alternative color
const Color _defaultAlternativeColor = Color.fromARGB(255, 152, 77, 244);

// Dynamic FAB colors
const Color _defaultDynamicFABBackgroundColor = Color.fromRGBO(0, 0, 0, 1);
const Color _defaultDynamicFABTextColor = Color.fromRGBO(255, 255, 255, 1);

// Recovery key box color
const Color _defaultRecoveryKeyBoxColor = Color.fromARGB(51, 150, 0, 220);

// Frosty blur backdrop filter color
const Color _defaultFrostyBlurBackdropFilterColor = Color.fromRGBO(
  238,
  238,
  238,
  0.5,
);

// Default Icon Color
const Color _defaultIconColor = Color.fromRGBO(0, 0, 0, 0.75);

// Default Background Color For Questions
const Color _defaultBgColorForQuestions = Color.fromRGBO(255, 255, 255, 1);

// Default Green Text Color
const Color _defaultGreenText = Color.fromARGB(255, 40, 190, 113);

// Default Cupertino Picker Top Color
const Color _defaultCupertinoPickerTopColor = Color.fromARGB(
  255,
  238,
  238,
  238,
);

// Default Step Progress Unselected Color
const Color _defaultStepProgressUnselectedColor = Color.fromRGBO(
  196,
  196,
  196,
  0.6,
);

// Default Navigation Colors
const Color _defaultGNavBackgroundColor = Color.fromRGBO(196, 196, 196, 0.6);
const Color _defaultGNavBarActiveColor = Color.fromRGBO(255, 255, 255, 0.6);
const Color _defaultGNavIconColor = Color.fromRGBO(0, 0, 0, 0.8);
const Color _defaultGNavActiveIconColor = Color.fromRGBO(0, 0, 0, 0.8);

// Default Gallery Thumb Colors
const Color _defaultGalleryThumbBackgroundColor = Color.fromRGBO(
  240,
  240,
  240,
  1,
);
const Color _defaultGalleryThumbDrawColor = Color.fromRGBO(0, 0, 0, 0.8);

// Default Backup Enabled Background Color
const Color _defaultBackupEnabledBgColor = Color.fromRGBO(230, 230, 230, 0.95);

// Default Dots Indicator Colors
const Color _defaultDotsIndicatorActiveColor = Color.fromRGBO(0, 0, 0, 0.5);
const Color _defaultDotsIndicatorInactiveColor = Color.fromRGBO(0, 0, 0, 0.12);

// Default Toast Colors
const Color _defaultToastTextColor = Color.fromRGBO(255, 255, 255, 1);
const Color _defaultToastBackgroundColor = Color.fromRGBO(24, 24, 24, 0.95);

// Default Sub Text Color
const Color _defaultSubTextColor = Color.fromRGBO(180, 180, 180, 1);

// Default Theme Switch Inactive Icon Color
const Color _defaultThemeSwitchInactiveIconColor = Color.fromRGBO(0, 0, 0, 0.5);

// Default Search Results Colors
const Color _defaultSearchResultsColor = Color.fromRGBO(245, 245, 245, 1.0);
const Color _defaultMutedTextColor = Color.fromRGBO(80, 80, 80, 1);
const Color _defaultSearchResultsBackgroundColor = Color.fromRGBO(
  0,
  0,
  0,
  0.32,
);

// Default Code Card Background Color
const Color _defaultCodeCardBackgroundColor = Color.fromRGBO(246, 246, 246, 1);

const Color _golden700 = Color(0xFFFDB816);
const Color _golden500 = Color(0xFFFFC336);

/// Utility class to help apps create custom color schemes with their brand colors.
///
/// This class provides convenient methods to generate complete color schemes
/// from a base primary color, automatically calculating the different shades
/// and variations needed for the app.
class ColorSchemeBuilder {
  /// Creates light and dark color schemes from a single primary color.
  ///
  /// The primary color is used as the base (primary500), and other shades
  /// are automatically calculated:
  /// - primary700: Darker shade for emphasis
  /// - primary400: Lighter shade for secondary elements
  /// - primary300: Lightest shade for subtle accents
  ///
  /// Example:
  /// ```dart
  /// final schemes = ColorSchemeBuilder.fromPrimaryColor(
  ///   Color(0xFF2196F3), // Material Blue
  /// );
  /// final lightScheme = schemes.light;
  /// final darkScheme = schemes.dark;
  /// ```
  static ({EnteColorScheme light, EnteColorScheme dark}) fromPrimaryColor(
    Color primaryColor,
  ) {
    // Calculate different shades of the primary color
    final HSLColor hsl = HSLColor.fromColor(primaryColor);

    final primary700 = hsl
        .withLightness((hsl.lightness - 0.1).clamp(0.0, 1.0))
        .toColor();
    final primary500 = primaryColor;
    final primary400 = hsl
        .withLightness((hsl.lightness + 0.1).clamp(0.0, 1.0))
        .toColor();
    final primary300 = hsl
        .withLightness((hsl.lightness + 0.2).clamp(0.0, 1.0))
        .toColor();

    // Create gradient colors from the primary color
    final gradientColors = [primary700, primary500];

    final lightScheme = EnteColorScheme.light(
      primary700: primary700,
      primary500: primary500,
      primary400: primary400,
      primary300: primary300,
      iconButtonColor: primary500,
      gradientButtonBgColor: primary500,
      gradientButtonBgColors: gradientColors,
    );

    final darkScheme = EnteColorScheme.dark(
      primary700: primary700,
      primary500: primary500,
      primary400: primary400,
      primary300: primary300,
      iconButtonColor: primary500,
      gradientButtonBgColor: primary500,
      gradientButtonBgColors: gradientColors,
    );

    return (light: lightScheme, dark: darkScheme);
  }

  /// Creates light and dark color schemes with fully custom primary colors.
  ///
  /// Use this method when you need complete control over all primary color shades.
  ///
  /// Example:
  /// ```dart
  /// final schemes = ColorSchemeBuilder.fromCustomColors(
  ///   primary700: Color(0xFF1565C0),
  ///   primary500: Color(0xFF2196F3),
  ///   primary400: Color(0xFF42A5F5),
  ///   primary300: Color(0xFF90CAF9),
  /// );
  /// ```
  static ({EnteColorScheme light, EnteColorScheme dark}) fromCustomColors({
    required Color primary700,
    required Color primary500,
    required Color primary400,
    required Color primary300,
    Color? iconButtonColor,
    Color? gradientButtonBgColor,
    List<Color>? gradientButtonBgColors,
  }) {
    final effectiveIconButtonColor = iconButtonColor ?? primary500;
    final effectiveGradientBgColor = gradientButtonBgColor ?? primary500;
    final effectiveGradientColors =
        gradientButtonBgColors ?? [primary700, primary500];

    final lightScheme = EnteColorScheme.light(
      primary700: primary700,
      primary500: primary500,
      primary400: primary400,
      primary300: primary300,
      iconButtonColor: effectiveIconButtonColor,
      gradientButtonBgColor: effectiveGradientBgColor,
      gradientButtonBgColors: effectiveGradientColors,
    );

    final darkScheme = EnteColorScheme.dark(
      primary700: primary700,
      primary500: primary500,
      primary400: primary400,
      primary300: primary300,
      iconButtonColor: effectiveIconButtonColor,
      gradientButtonBgColor: effectiveGradientBgColor,
      gradientButtonBgColors: effectiveGradientColors,
    );

    return (light: lightScheme, dark: darkScheme);
  }
}

const List<Color> avatarLight = [
  Color.fromRGBO(118, 84, 154, 1),
  Color.fromRGBO(223, 120, 97, 1),
  Color.fromRGBO(148, 180, 159, 1),
  Color.fromRGBO(135, 162, 251, 1),
  Color.fromRGBO(198, 137, 198, 1),
  Color.fromRGBO(147, 125, 194, 1), // Fixed duplicate
  Color.fromRGBO(50, 82, 136, 1),
  Color.fromRGBO(133, 180, 224, 1),
  Color.fromRGBO(193, 163, 163, 1),
  Color.fromRGBO(225, 160, 89, 1), // Fixed duplicate
  Color.fromRGBO(66, 97, 101, 1),
  Color.fromRGBO(107, 119, 178, 1), // Fixed duplicate
  Color.fromRGBO(149, 127, 239, 1), // Fixed duplicate
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
