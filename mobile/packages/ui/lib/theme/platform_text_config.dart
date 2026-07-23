import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Platform-specific text scaling configuration to ensure consistent
/// font sizes and appearance across Android and iOS platforms.
class PlatformTextConfig {
  /// Android tends to render fonts slightly larger than iOS, so we apply
  /// a small reduction factor to maintain visual consistency.
  static const double androidFontScaleFactor = 0.95;

  /// iOS uses the default scaling (1.0)
  static const double iosFontScaleFactor = 1.0;

  /// Get the appropriate font scale factor for the current platform
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

  /// Adjust font size based on platform to ensure consistency
  static double adjustFontSize(double baseFontSize) {
    return baseFontSize * getPlatformFontScaleFactor();
  }

  /// Create a TextStyle with platform-adjusted font size
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

  /// Get platform-specific MediaQuery configuration for text scaling
  static MediaQueryData adjustMediaQueryTextScaling(MediaQueryData data) {
    // Clamp text scaling between 0.8 and 1.3 to prevent extreme scaling
    // that can break UI layouts
    final textScaleFactor =
        (data.textScaler.scale(1.0) * getPlatformFontScaleFactor()).clamp(
          0.8,
          1.3,
        );

    return data.copyWith(textScaler: TextScaler.linear(textScaleFactor));
  }
}

/// Extension on BuildContext to easily access platform-adjusted text scaling
extension PlatformTextScaling on BuildContext {
  /// Get MediaQuery with platform-adjusted text scaling
  MediaQueryData get platformAdjustedMediaQuery {
    return PlatformTextConfig.adjustMediaQueryTextScaling(MediaQuery.of(this));
  }
}
