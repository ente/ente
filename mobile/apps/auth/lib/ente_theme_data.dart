import 'package:ente_auth/theme/colors.dart';
import 'package:ente_auth/theme/ente_theme.dart';
import 'package:flutter/material.dart';

final lightThemeData = ThemeData(
  fontFamily: 'Inter',
  brightness: Brightness.light,
  dividerTheme: const DividerThemeData(color: Colors.black12),
  hintColor: const Color.fromRGBO(158, 158, 158, 1),
  primaryColor: const Color.fromRGBO(255, 110, 64, 1),
  primaryColorLight: const Color.fromRGBO(0, 0, 0, 0.541),
  iconTheme: const IconThemeData(color: Colors.black),
  primaryIconTheme: const IconThemeData(
    color: Colors.red,
    opacity: 1.0,
    size: 50.0,
  ),
  buttonTheme: const ButtonThemeData(),
  outlinedButtonTheme: buildOutlinedButtonThemeData(
    bgDisabled: const Color.fromRGBO(158, 158, 158, 1),
    bgEnabled: const Color.fromRGBO(0, 0, 0, 1),
    fgDisabled: const Color.fromRGBO(255, 255, 255, 1),
    fgEnabled: const Color.fromRGBO(255, 255, 255, 1),
  ),
  elevatedButtonTheme: buildElevatedButtonThemeData(
    onPrimary: const Color.fromRGBO(255, 255, 255, 1),
    primary: const Color.fromRGBO(0, 0, 0, 1),
  ),
  scaffoldBackgroundColor: const Color.fromRGBO(255, 255, 255, 1),
  appBarTheme: const AppBarTheme().copyWith(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    iconTheme: const IconThemeData(color: Colors.black),
    elevation: 0,
  ),
  //https://api.flutter.dev/flutter/material/TextTheme-class.html
  textTheme: _buildTextTheme(const Color.fromRGBO(0, 0, 0, 1)),
  primaryTextTheme: const TextTheme().copyWith(
    bodyMedium: const TextStyle(color: Colors.yellow),
    bodyLarge: const TextStyle(color: Colors.orange),
  ),
  cardColor: const Color.fromRGBO(250, 250, 250, 1.0),
  dialogTheme: const DialogThemeData().copyWith(
    backgroundColor: const Color.fromRGBO(250, 250, 250, 1.0), //
    titleTextStyle: const TextStyle(
      color: Colors.black,
      fontSize: 24,
      fontWeight: FontWeight.w600,
    ),
    contentTextStyle: const TextStyle(
      fontFamily: 'Inter-Medium',
      color: Colors.black,
      fontSize: 16,
      fontWeight: FontWeight.w500,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ),
  inputDecorationTheme: const InputDecorationTheme().copyWith(
    focusedBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: Color.fromARGB(255, 152, 77, 244)),
    ),
  ),
  checkboxTheme: CheckboxThemeData(
    side: const BorderSide(color: Colors.black, width: 2),
    fillColor: WidgetStateProperty.resolveWith((states) {
      return states.contains(WidgetState.selected)
          ? const Color.fromRGBO(0, 0, 0, 1)
          : const Color.fromRGBO(255, 255, 255, 1);
    }),
    checkColor: WidgetStateProperty.resolveWith((states) {
      return states.contains(WidgetState.selected)
          ? const Color.fromRGBO(255, 255, 255, 1)
          : const Color.fromRGBO(0, 0, 0, 1);
    }),
  ),

  radioTheme: RadioThemeData(
    fillColor: WidgetStateProperty.resolveWith<Color?>((
      Set<WidgetState> states,
    ) {
      if (states.contains(WidgetState.disabled)) {
        return null;
      }
      if (states.contains(WidgetState.selected)) {
        return const Color.fromRGBO(102, 187, 106, 1);
      }
      return null;
    }),
  ),
  switchTheme: SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith<Color?>((
      Set<WidgetState> states,
    ) {
      if (states.contains(WidgetState.disabled)) {
        return null;
      }
      if (states.contains(WidgetState.selected)) {
        return const Color.fromRGBO(102, 187, 106, 1);
      }
      return null;
    }),
    trackColor: WidgetStateProperty.resolveWith<Color?>((
      Set<WidgetState> states,
    ) {
      if (states.contains(WidgetState.disabled)) {
        return null;
      }
      if (states.contains(WidgetState.selected)) {
        return const Color.fromRGBO(102, 187, 106, 1);
      }
      return null;
    }),
  ),
  colorScheme: const ColorScheme.light(
    primary: Colors.black,
    secondary: Color.fromARGB(255, 163, 163, 163),
  ).copyWith(surface: const Color.fromRGBO(255, 255, 255, 1)),
);

final darkThemeData = ThemeData(
  fontFamily: 'Inter',
  brightness: Brightness.dark,
  dividerTheme: const DividerThemeData(color: Colors.white12),
  primaryColorLight: const Color.fromRGBO(255, 255, 255, 0.702),
  iconTheme: const IconThemeData(color: Colors.white),
  primaryIconTheme: const IconThemeData(
    color: Colors.red,
    opacity: 1.0,
    size: 50.0,
  ),
  hintColor: const Color.fromRGBO(158, 158, 158, 1),
  buttonTheme: const ButtonThemeData().copyWith(
    buttonColor: const Color.fromRGBO(45, 194, 98, 1.0),
    height: 56,
  ),
  textTheme: _buildTextTheme(const Color.fromRGBO(255, 255, 255, 1)),
  outlinedButtonTheme: buildOutlinedButtonThemeData(
    bgDisabled: const Color.fromRGBO(158, 158, 158, 1),
    bgEnabled: const Color.fromRGBO(255, 255, 255, 1),
    fgDisabled: const Color.fromRGBO(255, 255, 255, 1),
    fgEnabled: const Color.fromRGBO(0, 0, 0, 1),
  ),
  elevatedButtonTheme: buildElevatedButtonThemeData(
    onPrimary: const Color.fromRGBO(0, 0, 0, 1),
    primary: const Color.fromRGBO(255, 255, 255, 1),
  ),
  scaffoldBackgroundColor: const Color.fromRGBO(0, 0, 0, 1),
  appBarTheme: const AppBarTheme().copyWith(
    backgroundColor: Colors.black,
    elevation: 0,
  ),
  cardColor: const Color.fromRGBO(10, 15, 15, 1.0),
  dialogTheme: const DialogThemeData().copyWith(
    backgroundColor: const Color.fromRGBO(15, 15, 15, 1.0),
    titleTextStyle: const TextStyle(
      color: Colors.white,
      fontSize: 24,
      fontWeight: FontWeight.w600,
    ),
    contentTextStyle: const TextStyle(
      fontFamily: 'Inter-Medium',
      color: Colors.white,
      fontSize: 16,
      fontWeight: FontWeight.w500,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ),
  checkboxTheme: CheckboxThemeData(
    side: const BorderSide(color: Colors.grey, width: 2),
    fillColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return const Color.fromRGBO(158, 158, 158, 1);
      } else {
        return const Color.fromRGBO(0, 0, 0, 1);
      }
    }),
    checkColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return const Color.fromRGBO(0, 0, 0, 1);
      } else {
        return const Color.fromRGBO(158, 158, 158, 1);
      }
    }),
  ),
  radioTheme: RadioThemeData(
    fillColor: WidgetStateProperty.resolveWith<Color?>((
      Set<WidgetState> states,
    ) {
      if (states.contains(WidgetState.disabled)) {
        return null;
      }
      if (states.contains(WidgetState.selected)) {
        return const Color.fromRGBO(102, 187, 106, 1);
      }
      return null;
    }),
  ),
  switchTheme: SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith<Color?>((
      Set<WidgetState> states,
    ) {
      if (states.contains(WidgetState.disabled)) {
        return null;
      }
      if (states.contains(WidgetState.selected)) {
        return const Color.fromRGBO(102, 187, 106, 1);
      }
      return null;
    }),
    trackColor: WidgetStateProperty.resolveWith<Color?>((
      Set<WidgetState> states,
    ) {
      if (states.contains(WidgetState.disabled)) {
        return null;
      }
      if (states.contains(WidgetState.selected)) {
        return const Color.fromRGBO(102, 187, 106, 1);
      }
      return null;
    }),
  ),
  colorScheme: const ColorScheme.dark(
    primary: Colors.white,
  ).copyWith(surface: const Color.fromRGBO(0, 0, 0, 1)),
);

TextTheme _buildTextTheme(Color textColor) {
  return const TextTheme().copyWith(
    headlineMedium: TextStyle(
      color: textColor,
      fontSize: 32,
      fontWeight: FontWeight.w600,
      fontFamily: 'Inter',
    ),
    headlineSmall: TextStyle(
      color: textColor,
      fontSize: 24,
      fontWeight: FontWeight.w600,
      fontFamily: 'Inter',
    ),
    titleLarge: TextStyle(
      color: textColor,
      fontSize: 18,
      fontFamily: 'Inter',
      fontWeight: FontWeight.w600,
    ),
    titleMedium: TextStyle(
      color: textColor,
      fontFamily: 'Inter',
      fontSize: 16,
      fontWeight: FontWeight.w500,
    ),
    titleSmall: TextStyle(
      color: textColor,
      fontFamily: 'Inter',
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
    bodyLarge: TextStyle(
      fontFamily: 'Inter',
      color: textColor,
      fontSize: 16,
      fontWeight: FontWeight.w500,
    ),
    bodyMedium: TextStyle(
      fontFamily: 'Inter',
      color: textColor,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
    bodySmall: TextStyle(
      color: textColor.withValues(alpha: 0.4),
      fontSize: 10,
      fontWeight: FontWeight.w500,
    ),
    labelSmall: TextStyle(
      fontFamily: 'Inter',
      color: textColor,
      fontSize: 14,
      fontWeight: FontWeight.w500,
      decoration: TextDecoration.underline,
    ),
  );
}

extension CustomColorScheme on ColorScheme {
  Color get defaultBackgroundColor =>
      brightness == Brightness.light ? backgroundBaseLight : backgroundBaseDark;

  Color get inverseBackgroundColor =>
      brightness != Brightness.light ? backgroundBaseLight : backgroundBaseDark;

  Color get fabForegroundColor => brightness == Brightness.light
      ? const Color.fromRGBO(255, 255, 255, 1)
      : const Color.fromRGBO(40, 40, 40, 1);

  Color get fabBackgroundColor => brightness != Brightness.light
      ? const Color.fromRGBO(255, 255, 255, 1)
      : const Color.fromRGBO(40, 40, 40, 1);

  Color get defaultTextColor =>
      brightness == Brightness.light ? textBaseLight : textBaseDark;

  Color get inverseTextColor =>
      brightness != Brightness.light ? textBaseLight : textBaseDark;

  Color get boxSelectColor => brightness == Brightness.light
      ? const Color.fromRGBO(67, 186, 108, 1)
      : const Color.fromRGBO(16, 32, 32, 1);

  Color get boxUnSelectColor => brightness == Brightness.light
      ? const Color.fromRGBO(240, 240, 240, 1)
      : const Color.fromRGBO(8, 18, 18, 0.4);

  Color get alternativeColor => const Color.fromARGB(255, 152, 77, 244);

  Color get dynamicFABBackgroundColor => brightness == Brightness.light
      ? const Color.fromRGBO(0, 0, 0, 1)
      : const Color.fromRGBO(48, 48, 48, 1);

  Color get dynamicFABTextColor =>
      const Color.fromRGBO(255, 255, 255, 1); //same for both themes

  // todo: use brightness == Brightness.light for changing color for dark/light theme
  ButtonStyle? get optionalActionButtonStyle => buildElevatedButtonThemeData(
    onPrimary: const Color(0xFF777777),
    primary: const Color(0xFFF0F0F0),
    elevation: 0,
  ).style;

  Color get recoveryKeyBoxColor => brightness == Brightness.light
      ? const Color.fromARGB(51, 150, 0, 220)
      : const Color.fromARGB(255, 174, 56, 247);

  Color get frostyBlurBackdropFilterColor => brightness == Brightness.light
      ? const Color.fromRGBO(238, 238, 238, 0.5)
      : const Color.fromRGBO(48, 48, 48, 0.5);

  Color get iconColor => brightness == Brightness.light
      ? const Color.fromRGBO(0, 0, 0, 1).withValues(alpha: 0.75)
      : const Color.fromRGBO(255, 255, 255, 1);

  Color get bgColorForQuestions => brightness == Brightness.light
      ? const Color.fromRGBO(255, 255, 255, 1)
      : const Color.fromRGBO(10, 15, 15, 1.0);

  Color get greenText => const Color.fromARGB(255, 40, 190, 113);

  Color get cupertinoPickerTopColor => brightness == Brightness.light
      ? const Color.fromARGB(255, 238, 238, 238)
      : const Color.fromRGBO(255, 255, 255, 1).withValues(alpha: 0.1);

  Color get stepProgressUnselectedColor => brightness == Brightness.light
      ? const Color.fromRGBO(196, 196, 196, 0.6)
      : const Color.fromRGBO(255, 255, 255, 0.7);

  Color get gNavBackgroundColor => brightness == Brightness.light
      ? const Color.fromRGBO(196, 196, 196, 0.6)
      : const Color.fromRGBO(40, 40, 40, 0.6);

  Color get gNavBarActiveColor => brightness == Brightness.light
      ? const Color.fromRGBO(255, 255, 255, 0.6)
      : const Color.fromRGBO(255, 255, 255, 0.9);

  Color get gNavIconColor => brightness == Brightness.light
      ? const Color.fromRGBO(0, 0, 0, 0.8)
      : const Color.fromRGBO(255, 255, 255, 0.8);

  Color get gNavActiveIconColor => brightness == Brightness.light
      ? const Color.fromRGBO(0, 0, 0, 0.8)
      : const Color.fromRGBO(0, 0, 0, 0.8);

  Color get galleryThumbBackgroundColor => brightness == Brightness.light
      ? const Color.fromRGBO(240, 240, 240, 1)
      : const Color.fromRGBO(20, 20, 20, 1);

  Color get galleryThumbDrawColor => brightness == Brightness.light
      ? const Color.fromRGBO(0, 0, 0, 1).withValues(alpha: 0.8)
      : const Color.fromRGBO(255, 255, 255, 1).withValues(alpha: 0.5);

  Color get backupEnabledBgColor => brightness == Brightness.light
      ? const Color.fromRGBO(230, 230, 230, 0.95)
      : const Color.fromRGBO(10, 40, 40, 0.3);

  Color get dotsIndicatorActiveColor => brightness == Brightness.light
      ? const Color.fromRGBO(0, 0, 0, 1).withValues(alpha: 0.5)
      : const Color.fromRGBO(255, 255, 255, 1).withValues(alpha: 0.5);

  Color get dotsIndicatorInactiveColor => brightness == Brightness.light
      ? const Color.fromRGBO(0, 0, 0, 1).withValues(alpha: 0.12)
      : const Color.fromRGBO(255, 255, 255, 1).withValues(alpha: 0.12);

  Color get toastTextColor => brightness == Brightness.light
      ? const Color.fromRGBO(255, 255, 255, 1)
      : const Color.fromRGBO(0, 0, 0, 1);

  Color get toastBackgroundColor => brightness == Brightness.light
      ? const Color.fromRGBO(24, 24, 24, 0.95)
      : const Color.fromRGBO(255, 255, 255, 0.95);

  Color get subTextColor => brightness == Brightness.light
      ? const Color.fromRGBO(180, 180, 180, 1)
      : const Color.fromRGBO(100, 100, 100, 1);

  Color get themeSwitchInactiveIconColor => brightness == Brightness.light
      ? const Color.fromRGBO(0, 0, 0, 1).withValues(alpha: 0.5)
      : const Color.fromRGBO(255, 255, 255, 1).withValues(alpha: 0.5);

  Color get searchResultsColor => brightness == Brightness.light
      ? const Color.fromRGBO(245, 245, 245, 1.0)
      : const Color.fromRGBO(30, 30, 30, 1.0);

  Color get mutedTextColor => brightness == Brightness.light
      ? const Color.fromRGBO(80, 80, 80, 1)
      : const Color.fromRGBO(150, 150, 150, 1);

  Color get searchResultsBackgroundColor => brightness == Brightness.light
      ? Colors.black.withValues(alpha: 0.32)
      : Colors.black.withValues(alpha: 0.64);

  Color get codeCardBackgroundColor => brightness == Brightness.light
      ? const Color.fromRGBO(246, 246, 246, 1)
      : const Color.fromRGBO(40, 40, 40, 0.6);

  Color get primaryColor => brightness == Brightness.light
      ? const Color(0xFF9610D6)
      : const Color(0xFF9610D6);

  EnteTheme get enteTheme =>
      brightness == Brightness.light ? lightTheme : darkTheme;

  EnteTheme get inverseEnteTheme =>
      brightness == Brightness.light ? darkTheme : lightTheme;
}

OutlinedButtonThemeData buildOutlinedButtonThemeData({
  required Color bgDisabled,
  required Color bgEnabled,
  required Color fgDisabled,
  required Color fgEnabled,
}) {
  return OutlinedButtonThemeData(
    style:
        OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          fixedSize: const Size.fromHeight(56),
          alignment: Alignment.center,
          padding: const EdgeInsets.fromLTRB(50, 16, 50, 16),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter-SemiBold',
            fontSize: 18,
          ),
        ).copyWith(
          backgroundColor: WidgetStateProperty.resolveWith<Color>((
            Set<WidgetState> states,
          ) {
            if (states.contains(WidgetState.disabled)) {
              return bgDisabled;
            }
            return bgEnabled;
          }),
          foregroundColor: WidgetStateProperty.resolveWith<Color>((
            Set<WidgetState> states,
          ) {
            if (states.contains(WidgetState.disabled)) {
              return fgDisabled;
            }
            return fgEnabled;
          }),
          alignment: Alignment.center,
        ),
  );
}

ElevatedButtonThemeData buildElevatedButtonThemeData({
  required Color onPrimary, // text button color
  required Color primary,
  double elevation = 2, // background color of button
}) {
  return ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      foregroundColor: onPrimary,
      backgroundColor: primary,
      elevation: elevation,
      alignment: Alignment.center,
      textStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        fontFamily: 'Inter-SemiBold',
        fontSize: 18,
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
    ),
  );
}
