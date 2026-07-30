import 'package:ente_components/theme/colors.dart';
import 'package:ente_components/theme/text_styles.dart';
import 'package:flutter/material.dart';

/// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=57-6281&m=dev
/// Section: Design system / Theme helpers
/// Specs: Light and dark theme mapping for Ente component tokens.
class ComponentTheme {
  const ComponentTheme._();

  static ComponentApp _currentApp = ComponentApp.photos;

  static void configure({required ComponentApp app}) {
    _currentApp = app;
  }

  static ColorTokens colorsOf(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<ComponentColorTokens>()?.colors ??
        colorsForApp(_currentApp, brightness: theme.brightness);
  }

  static ColorTokens colorsForApp(
    ComponentApp app, {
    Brightness brightness = Brightness.light,
  }) {
    return ColorTokens.forApp(app, brightness: brightness);
  }

  static ThemeData lightTheme({ComponentApp app = ComponentApp.photos}) {
    return _theme(colorsForApp(app), Brightness.light);
  }

  static ThemeData darkTheme({ComponentApp app = ComponentApp.photos}) {
    return _theme(
      colorsForApp(app, brightness: Brightness.dark),
      Brightness.dark,
    );
  }

  static ThemeData themeForApp(
    ComponentApp app, {
    Brightness brightness = Brightness.light,
  }) {
    return brightness == Brightness.dark
        ? darkTheme(app: app)
        : lightTheme(app: app);
  }

  static ThemeData _theme(ColorTokens colors, Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: colors.backgroundBase,
      colorScheme: ColorScheme.fromSeed(
        seedColor: colors.primary,
        brightness: brightness,
        primary: colors.primary,
        error: colors.warning,
        surface: colors.backgroundBase,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyles.h1,
        headlineMedium: TextStyles.h2,
        titleLarge: TextStyles.large,
        bodyLarge: TextStyles.body,
        bodyMedium: TextStyles.body,
        labelLarge: TextStyles.bodyBold,
        labelMedium: TextStyles.mini,
        labelSmall: TextStyles.tiny,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.fillLight,
        surfaceTintColor: Colors.transparent,
      ),
      extensions: [ComponentColorTokens(colors)],
    );
  }
}

@immutable
class ComponentColorTokens extends ThemeExtension<ComponentColorTokens> {
  const ComponentColorTokens(this.colors);

  final ColorTokens colors;

  @override
  ComponentColorTokens copyWith({ColorTokens? colors}) {
    return ComponentColorTokens(colors ?? this.colors);
  }

  @override
  ComponentColorTokens lerp(
    ThemeExtension<ComponentColorTokens>? other,
    double t,
  ) {
    if (other is! ComponentColorTokens) {
      return this;
    }
    return t < 0.5 ? this : other;
  }
}

extension ThemeContext on BuildContext {
  ColorTokens get componentColors => ComponentTheme.colorsOf(this);
}
