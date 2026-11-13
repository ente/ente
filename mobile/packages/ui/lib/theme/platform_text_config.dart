import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PlatformTextConfig {
  // Android renders fonts slightly larger than iOS at the same nominal size.
  static const double androidFontScaleFactor = 0.95;

  static const double iosFontScaleFactor = 1.0;

  static double getPlatformFontScaleFactor() {
    if (kIsWeb) return 1.0;

    switch (Platform.operatingSystem) {
      case 'android':
        return androidFontScaleFactor;
      case 'ios':
        return iosFontScaleFactor;
      default:
        return 1.0;
    }
  }

  static double adjustFontSize(double baseFontSize) {
    return baseFontSize * getPlatformFontScaleFactor();
  }

  static TextStyle createTextStyle({
    required double fontSize,
    FontWeight? fontWeight,
    String? fontFamily,
    Color? color,
    double? height,
    TextDecoration? decoration,
  }) {
    return TextStyle(
      fontSize: adjustFontSize(fontSize),
      fontWeight: fontWeight,
      fontFamily: fontFamily,
      color: color,
      height: height,
      decoration: decoration,
    );
  }

  static MediaQueryData adjustMediaQueryTextScaling(MediaQueryData data) {
    // Avoid layout breakage at extreme text scales.
    final textScaleFactor =
        (data.textScaler.scale(1.0) * getPlatformFontScaleFactor()).clamp(
          0.8,
          1.3,
        );

    return data.copyWith(textScaler: TextScaler.linear(textScaleFactor));
  }
}

extension PlatformTextScaling on BuildContext {
  MediaQueryData get platformAdjustedMediaQuery {
    return PlatformTextConfig.adjustMediaQueryTextScaling(MediaQuery.of(this));
  }
}
