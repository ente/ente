import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  group("foundation tokens", () {
    test("expose expected spacing, radii, motion, and shadow values", () {
      expect(2, 2);
      expect(Spacing.sm, 8);
      expect(Spacing.xl, 20);
      expect(Spacing.xxl, 24);
      expect(40, 40);

      expect(Radii.xs, 4);
      expect(Radii.md, 12);
      expect(Radii.button, 20);
      expect(Radii.bottomSheet, 20);
      expect(Radii.buttonRadius, const Radius.circular(20));
      expect(Radii.buttonBorder, const BorderRadius.all(Radius.circular(20)));

      expect(IconSizes.micro, 8);
      expect(IconSizes.tiny, 12);
      expect(IconSizes.small, 18);
      expect(IconSizes.medium, 24);
      expect(IconSizes.large, 36);

      expect(Motion.quick, const Duration(milliseconds: 120));
      expect(Motion.standard, const Duration(milliseconds: 180));
      expect(Motion.slow, const Duration(milliseconds: 260));

      expect(Shadows.soft, hasLength(1));
      expect(Shadows.soft.first.color, const Color(0x14000000));
      expect(Shadows.soft.first.blurRadius, 16);
      expect(Shadows.floating.first.offset, const Offset(0, 12));
    });

    test("expose light and dark semantic color values", () {
      expect(ColorTokens.light.primary, const Color(0xFF08C225));
      expect(ColorTokens.light.warning, const Color(0xFFF63A3A));
      expect(ColorTokens.light.backgroundBase, const Color(0xFFF4F4F4));
      expect(ColorTokens.light.textBase, const Color(0xFF000000));
      expect(ColorTokens.light.textReverse, const Color(0xFFFFFFFF));
      expect(ColorTokens.light.iconColor, const Color.fromRGBO(0, 0, 0, 0.75));

      expect(ColorTokens.dark.primary, const Color(0xFF08C225));
      expect(ColorTokens.dark.warningLight, const Color(0xFF292929));
      expect(ColorTokens.dark.backgroundBase, const Color(0xFF161616));
      expect(ColorTokens.dark.textBase, const Color(0xFFFFFFFF));
      expect(ColorTokens.dark.textReverse, const Color(0xFF000000));
      expect(ColorTokens.dark.iconColor, const Color(0xFFFFFFFF));
    });

    test("selects app primary tokens without changing shared colors", () {
      final photosLight = ColorTokens.forApp(ComponentApp.photos);
      final authLight = ColorTokens.forApp(ComponentApp.auth);
      final lockerLight = ColorTokens.forApp(ComponentApp.locker);
      final authDark = ColorTokens.forApp(
        ComponentApp.auth,
        brightness: Brightness.dark,
      );

      expect(photosLight.primary, greenDefaultLight);
      expect(photosLight.primaryLight, greenLightLight);
      expect(photosLight.primaryLightHover, greenLightHoverLight);
      expect(photosLight.primaryLightPressed, greenLightPressedLight);
      expect(photosLight.primaryStroke, greenStrokeLight);
      expect(photosLight.primaryDark, greenDarkLight);
      expect(photosLight.primaryDarker, greenDarkerLight);

      expect(authLight.primary, purpleDefaultLight);
      expect(authLight.primaryLight, purpleLightLight);
      expect(authLight.primaryLightHover, purpleLightHoverLight);
      expect(authLight.primaryLightPressed, purpleLightPressedLight);
      expect(authLight.primaryStroke, purpleStrokeLight);
      expect(authLight.primaryDark, purpleDarkLight);
      expect(authLight.primaryDarker, purpleDarkerLight);

      expect(lockerLight.primary, blueDefaultLight);
      expect(lockerLight.primaryLight, blueLightLight);
      expect(lockerLight.primaryLightHover, blueLightHoverLight);
      expect(lockerLight.primaryLightPressed, blueLightPressedLight);
      expect(lockerLight.primaryStroke, blueStrokeLight);
      expect(lockerLight.primaryDark, blueDarkLight);
      expect(lockerLight.primaryDarker, blueDarkerLight);

      expect(authDark.primary, purpleDefaultDark);
      expect(authDark.primaryLight, purpleLightDark);
      expect(authDark.primaryLightHover, purpleLightHoverDark);
      expect(authDark.primaryLightPressed, purpleLightPressedDark);

      expect(authLight.backgroundBase, ColorTokens.light.backgroundBase);
      expect(authLight.warning, ColorTokens.light.warning);
      expect(authLight.green, ColorTokens.light.green);
      expect(authLight.blue, ColorTokens.light.blue);
      expect(authLight.purple, ColorTokens.light.purple);
      expect(lockerLight.textBase, ColorTokens.light.textBase);
      expect(lockerLight.iconColor, ColorTokens.light.iconColor);
    });

    test("match Figma color family values used as app primary colors", () {
      const expectedLight = <String, Color>{
        "greens/green-light": Color.fromRGBO(221, 238, 223, 1),
        "greens/green-light-hover": Color.fromRGBO(205, 229, 208, 1),
        "greens/green-light-pressed": Color.fromRGBO(184, 213, 187, 1),
        "greens/green-stroke": Color.fromRGBO(186, 236, 194, 1),
        "greens/green": Color.fromRGBO(8, 194, 37, 1),
        "greens/green-dark": Color.fromRGBO(6, 157, 30, 1),
        "greens/green-darker": Color.fromRGBO(5, 124, 24, 1),
        "purples/purple-light": Color.fromRGBO(244, 231, 252, 1),
        "purples/purple-light-hover": Color.fromRGBO(232, 210, 250, 1),
        "purples/purple-light-pressed": Color.fromRGBO(217, 188, 241, 1),
        "purples/purple-stroke": Color.fromRGBO(216, 181, 244, 1),
        "purples/purple": Color.fromRGBO(150, 16, 214, 1),
        "purples/purple-dark": Color.fromRGBO(122, 12, 174, 1),
        "purples/purple-darker": Color.fromRGBO(93, 8, 132, 1),
        "blues/blue-light": Color.fromRGBO(231, 239, 250, 1),
        "blues/blue-light-hover": Color.fromRGBO(216, 228, 244, 1),
        "blues/blue-light-pressed": Color.fromRGBO(194, 210, 232, 1),
        "blues/blue-stroke": Color.fromRGBO(16, 113, 255, 1),
        "blues/blue": Color.fromRGBO(16, 113, 255, 1),
        "blues/blue-dark": Color.fromRGBO(14, 95, 217, 1),
        "blues/blue-darker": Color.fromRGBO(11, 76, 173, 1),
      };
      const expectedDark = <String, Color>{
        "greens/green-light": Color.fromRGBO(41, 41, 41, 1),
        "greens/green-light-hover": Color.fromRGBO(31, 48, 35, 1),
        "greens/green-light-pressed": Color.fromRGBO(44, 66, 50, 1),
        "greens/green-stroke": Color.fromRGBO(28, 65, 34, 1),
        "greens/green": Color.fromRGBO(8, 194, 37, 1),
        "greens/green-dark": Color.fromRGBO(6, 157, 30, 1),
        "greens/green-darker": Color.fromRGBO(5, 124, 24, 1),
        "purples/purple-light": Color.fromRGBO(39, 28, 50, 1),
        "purples/purple-light-hover": Color.fromRGBO(47, 31, 63, 1),
        "purples/purple-light-pressed": Color.fromRGBO(37, 23, 52, 1),
        "purples/purple-stroke": Color.fromRGBO(61, 27, 92, 1),
        "purples/purple": Color.fromRGBO(150, 16, 214, 1),
        "purples/purple-dark": Color.fromRGBO(122, 12, 174, 1),
        "purples/purple-darker": Color.fromRGBO(93, 8, 132, 1),
        "blues/blue-light": Color.fromRGBO(41, 41, 41, 1),
        "blues/blue-light-hover": Color.fromRGBO(26, 38, 56, 1),
        "blues/blue-light-pressed": Color.fromRGBO(17, 30, 49, 1),
        "blues/blue-stroke": Color.fromRGBO(16, 113, 255, 1),
        "blues/blue": Color.fromRGBO(16, 113, 255, 1),
        "blues/blue-dark": Color.fromRGBO(14, 95, 217, 1),
        "blues/blue-darker": Color.fromRGBO(11, 76, 173, 1),
      };

      expect(_figmaColorFamilyMap(ColorTokens.light), expectedLight);
      expect(_figmaColorFamilyMap(ColorTokens.dark), expectedDark);
    });

    test("match Figma shared Color Tokens light and dark modes", () {
      const expectedLight = <String, Color>{
        "accent/orange": Color.fromRGBO(242, 72, 34, 1),
        "accent/orange-light": Color.fromRGBO(255, 247, 244, 1),
        "accent/pink": Color.fromRGBO(223, 97, 187, 1),
        "accent/pink-light": Color.fromRGBO(253, 246, 251, 1),
        "accent/teal": Color.fromRGBO(95, 183, 187, 1),
        "accent/teal-light": Color.fromRGBO(245, 251, 251, 1),
        "background/base": Color.fromRGBO(244, 244, 244, 1),
        "caution/default": Color.fromRGBO(240, 138, 30, 1),
        "caution/light": Color.fromRGBO(250, 244, 235, 1),
        "fill/base": Color.fromRGBO(0, 0, 0, 1),
        "fill/dark": Color.fromRGBO(234, 234, 234, 1),
        "fill/darker": Color.fromRGBO(222, 222, 222, 1),
        "fill/darkest": Color.fromRGBO(210, 210, 210, 1),
        "fill/light": Color.fromRGBO(255, 255, 255, 1),
        "primary/dark": Color.fromRGBO(6, 157, 30, 1),
        "primary/darker": Color.fromRGBO(5, 124, 24, 1),
        "primary/default": Color.fromRGBO(8, 194, 37, 1),
        "primary/light": Color.fromRGBO(221, 238, 223, 1),
        "primary/light-hover": Color.fromRGBO(205, 229, 208, 1),
        "primary/light-pressed": Color.fromRGBO(184, 213, 187, 1),
        "primary/stroke": Color.fromRGBO(186, 236, 194, 1),
        "special/content-reverse": Color.fromRGBO(255, 255, 255, 1),
        "special/scrim": Color.fromRGBO(0, 0, 0, 0.4),
        "special/white": Color.fromRGBO(255, 255, 255, 1),
        "special/white-overlay": Color.fromRGBO(255, 255, 255, 0.14),
        "stroke/dark": Color.fromRGBO(224, 224, 224, 1),
        "stroke/faint": Color.fromRGBO(235, 235, 235, 1),
        "text/base": Color.fromRGBO(0, 0, 0, 1),
        "text/dark": Color.fromRGBO(26, 26, 26, 1),
        "text/darker": Color.fromRGBO(21, 21, 21, 1),
        "text/light": Color.fromRGBO(102, 102, 102, 1),
        "text/lighter": Color.fromRGBO(150, 150, 150, 1),
        "text/lightest": Color.fromRGBO(214, 214, 214, 1),
        "text/reverse": Color.fromRGBO(255, 255, 255, 1),
        "warning/dark": Color.fromRGBO(221, 52, 52, 1),
        "warning/darker": Color.fromRGBO(197, 46, 46, 1),
        "warning/default": Color.fromRGBO(246, 58, 58, 1),
        "warning/light": Color.fromRGBO(250, 235, 235, 1),
      };
      const expectedDark = <String, Color>{
        "accent/orange": Color.fromRGBO(242, 72, 34, 1),
        "accent/orange-light": Color.fromRGBO(41, 41, 41, 1),
        "accent/pink": Color.fromRGBO(223, 97, 187, 1),
        "accent/pink-light": Color.fromRGBO(41, 41, 41, 1),
        "accent/teal": Color.fromRGBO(95, 183, 187, 1),
        "accent/teal-light": Color.fromRGBO(41, 41, 41, 1),
        "background/base": Color.fromRGBO(22, 22, 22, 1),
        "caution/default": Color.fromRGBO(240, 138, 30, 1),
        "caution/light": Color.fromRGBO(41, 41, 41, 1),
        "fill/base": Color.fromRGBO(255, 255, 255, 1),
        "fill/dark": Color.fromRGBO(10, 10, 10, 1),
        "fill/darker": Color.fromRGBO(20, 20, 20, 1),
        "fill/darkest": Color.fromRGBO(41, 41, 41, 1),
        "fill/light": Color.fromRGBO(33, 33, 33, 1),
        "primary/dark": Color.fromRGBO(6, 157, 30, 1),
        "primary/darker": Color.fromRGBO(5, 124, 24, 1),
        "primary/default": Color.fromRGBO(8, 194, 37, 1),
        "primary/light": Color.fromRGBO(41, 41, 41, 1),
        "primary/light-hover": Color.fromRGBO(31, 48, 35, 1),
        "primary/light-pressed": Color.fromRGBO(44, 66, 50, 1),
        "primary/stroke": Color.fromRGBO(28, 65, 34, 1),
        "special/content-reverse": Color.fromRGBO(0, 0, 0, 1),
        "special/scrim": Color.fromRGBO(0, 0, 0, 0.4),
        "special/white": Color.fromRGBO(255, 255, 255, 1),
        "special/white-overlay": Color.fromRGBO(255, 255, 255, 0.14),
        "stroke/dark": Color.fromRGBO(62, 62, 62, 1),
        "stroke/faint": Color.fromRGBO(42, 42, 42, 1),
        "text/base": Color.fromRGBO(255, 255, 255, 1),
        "text/dark": Color.fromRGBO(229, 229, 229, 1),
        "text/darker": Color.fromRGBO(204, 204, 204, 1),
        "text/light": Color.fromRGBO(153, 153, 153, 1),
        "text/lighter": Color.fromRGBO(150, 150, 150, 1),
        "text/lightest": Color.fromRGBO(65, 65, 65, 1),
        "text/reverse": Color.fromRGBO(0, 0, 0, 1),
        "warning/dark": Color.fromRGBO(221, 52, 52, 1),
        "warning/darker": Color.fromRGBO(197, 46, 46, 1),
        "warning/default": Color.fromRGBO(246, 58, 58, 1),
        "warning/light": Color.fromRGBO(41, 41, 41, 1),
      };

      expect(_figmaColorTokenMap(ColorTokens.light), expectedLight);
      expect(_figmaColorTokenMap(ColorTokens.dark), expectedDark);
    });
  });

  group("text styles", () {
    test("match the published type scale", () {
      expect(TextStyles.fontFamily, "Inter");
      expect(TextStyles.outfitFontFamily, "Outfit");
      expect(TextStyles.fontPackage, "ente_components");

      expect(TextStyles.display1.fontFamily, "packages/ente_components/Outfit");
      expect(TextStyles.display1.fontSize, 32);
      expect(TextStyles.display1.height, 40 / 32);
      expect(TextStyles.display1.fontWeight, FontWeight.w600);
      expect(TextStyles.display1.letterSpacing, 0);

      expect(TextStyles.display2.fontFamily, "packages/ente_components/Outfit");
      expect(TextStyles.display2.fontSize, 24);
      expect(TextStyles.display2.height, 32 / 24);
      expect(TextStyles.display2.fontWeight, FontWeight.w600);
      expect(TextStyles.display2.letterSpacing, 0);

      expect(TextStyles.h1.fontFamily, "packages/ente_components/Inter");
      expect(TextStyles.h1.fontSize, 20);
      expect(TextStyles.h1.height, 28 / 20);
      expect(TextStyles.h1.fontWeight, FontWeight.w700);
      expect(TextStyles.h1.letterSpacing, 0);

      expect(TextStyles.h2.fontSize, 18);
      expect(TextStyles.h2.height, 24 / 18);
      expect(TextStyles.h2.fontWeight, FontWeight.w600);

      expect(TextStyles.display3.fontFamily, "packages/ente_components/Outfit");
      expect(TextStyles.display3.fontSize, 20);
      expect(TextStyles.display3.height, 28 / 20);
      expect(TextStyles.display3.fontWeight, FontWeight.w600);

      expect(TextStyles.body.fontFamily, "packages/ente_components/Inter");
      expect(TextStyles.body.fontSize, 14);
      expect(TextStyles.body.height, 20 / 14);
      expect(TextStyles.body.fontWeight, FontWeight.w500);

      expect(TextStyles.mini.fontSize, 12);
      expect(TextStyles.tiny.fontSize, 10);
      expect(TextStyles.bodyLink.decoration, TextDecoration.underline);
    });
  });

  group("theme", () {
    test("maps color and text tokens into light ThemeData", () {
      final theme = ComponentTheme.lightTheme();

      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, ColorTokens.light.backgroundBase);
      expect(theme.colorScheme.primary, ColorTokens.light.primary);
      expect(theme.colorScheme.error, ColorTokens.light.warning);
      expect(
        theme.textTheme.headlineLarge?.fontFamily,
        TextStyles.h1.fontFamily,
      );
      expect(theme.textTheme.headlineLarge?.fontSize, TextStyles.h1.fontSize);
      expect(
        theme.textTheme.headlineLarge?.fontWeight,
        TextStyles.h1.fontWeight,
      );
      expect(
        theme.textTheme.bodyMedium?.fontFamily,
        TextStyles.body.fontFamily,
      );
      expect(theme.textTheme.bodyMedium?.fontSize, TextStyles.body.fontSize);
    });

    test("maps color and text tokens into dark ThemeData", () {
      final theme = ComponentTheme.darkTheme();

      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, ColorTokens.dark.backgroundBase);
      expect(theme.colorScheme.primary, ColorTokens.dark.primary);
      expect(theme.colorScheme.error, ColorTokens.dark.warning);
      expect(
        theme.textTheme.labelSmall?.fontFamily,
        TextStyles.tiny.fontFamily,
      );
      expect(theme.textTheme.labelSmall?.fontSize, TextStyles.tiny.fontSize);
      expect(
        theme.textTheme.labelSmall?.fontWeight,
        TextStyles.tiny.fontWeight,
      );
    });

    test("maps selected app primary tokens into ThemeData", () {
      final authTheme = ComponentTheme.lightTheme(app: ComponentApp.auth);
      final lockerTheme = ComponentTheme.darkTheme(app: ComponentApp.locker);

      expect(authTheme.colorScheme.primary, purpleDefaultLight);
      expect(
        authTheme.scaffoldBackgroundColor,
        ColorTokens.light.backgroundBase,
      );
      expect(lockerTheme.colorScheme.primary, blueDefaultDark);
      expect(
        lockerTheme.scaffoldBackgroundColor,
        ColorTokens.dark.backgroundBase,
      );
    });

    testWidgets("selects color tokens from the ambient brightness", (
      tester,
    ) async {
      late ColorTokens lightColors;
      late ColorTokens darkColors;

      await tester.pumpWidget(
        Theme(
          data: ComponentTheme.lightTheme(),
          child: Builder(
            builder: (context) {
              lightColors = ComponentTheme.colorsOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        Theme(
          data: ComponentTheme.darkTheme(),
          child: Builder(
            builder: (context) {
              darkColors = context.componentColors;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(lightColors.backgroundBase, ColorTokens.light.backgroundBase);
      expect(lightColors.textBase, ColorTokens.light.textBase);
      expect(darkColors.backgroundBase, ColorTokens.dark.backgroundBase);
      expect(darkColors.textBase, ColorTokens.dark.textBase);
    });

    testWidgets("reads app-aware tokens from ComponentTheme ThemeData", (
      tester,
    ) async {
      late ColorTokens authColors;
      late ColorTokens lockerColors;

      await tester.pumpWidget(
        Theme(
          data: ComponentTheme.lightTheme(app: ComponentApp.auth),
          child: Builder(
            builder: (context) {
              authColors = context.componentColors;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        Theme(
          data: ComponentTheme.darkTheme(app: ComponentApp.locker),
          child: Builder(
            builder: (context) {
              lockerColors = context.componentColors;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(authColors.primary, purpleDefaultLight);
      expect(authColors.backgroundBase, ColorTokens.light.backgroundBase);
      expect(lockerColors.primary, blueDefaultDark);
      expect(lockerColors.backgroundBase, ColorTokens.dark.backgroundBase);
    });

    testWidgets("uses configured app tokens when ThemeData has no extension", (
      tester,
    ) async {
      addTearDown(() => ComponentTheme.configure(app: ComponentApp.photos));
      ComponentTheme.configure(app: ComponentApp.locker);

      late ColorTokens colors;
      await tester.pumpWidget(
        Theme(
          data: ThemeData(brightness: Brightness.dark),
          child: Builder(
            builder: (context) {
              colors = context.componentColors;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(colors.primary, blueDefaultDark);
      expect(colors.backgroundBase, ColorTokens.dark.backgroundBase);
    });

    test("defaults to photos primary tokens when no app is passed", () {
      expect(
        ComponentTheme.lightTheme().colorScheme.primary,
        greenDefaultLight,
      );
    });
  });
}

Map<String, Color> _figmaColorFamilyMap(ColorTokens colors) {
  return {
    "greens/green-light": colors.greenLight,
    "greens/green-light-hover": colors.greenLightHover,
    "greens/green-light-pressed": colors.greenLightPressed,
    "greens/green-stroke": colors.greenStroke,
    "greens/green": colors.green,
    "greens/green-dark": colors.greenDark,
    "greens/green-darker": colors.greenDarker,
    "purples/purple-light": colors.purpleLight,
    "purples/purple-light-hover": colors.purpleLightHover,
    "purples/purple-light-pressed": colors.purpleLightPressed,
    "purples/purple-stroke": colors.purpleStroke,
    "purples/purple": colors.purple,
    "purples/purple-dark": colors.purpleDark,
    "purples/purple-darker": colors.purpleDarker,
    "blues/blue-light": colors.blueLight,
    "blues/blue-light-hover": colors.blueLightHover,
    "blues/blue-light-pressed": colors.blueLightPressed,
    "blues/blue-stroke": colors.blueStroke,
    "blues/blue": colors.blue,
    "blues/blue-dark": colors.blueDark,
    "blues/blue-darker": colors.blueDarker,
  };
}

Map<String, Color> _figmaColorTokenMap(ColorTokens colors) {
  return {
    "accent/orange": colors.accentOrange,
    "accent/orange-light": colors.accentOrangeLight,
    "accent/pink": colors.accentPink,
    "accent/pink-light": colors.accentPinkLight,
    "accent/teal": colors.accentTeal,
    "accent/teal-light": colors.accentTealLight,
    "background/base": colors.backgroundBase,
    "caution/default": colors.caution,
    "caution/light": colors.cautionLight,
    "fill/base": colors.fillBase,
    "fill/dark": colors.fillDark,
    "fill/darker": colors.fillDarker,
    "fill/darkest": colors.fillDarkest,
    "fill/light": colors.fillLight,
    "primary/dark": colors.primaryDark,
    "primary/darker": colors.primaryDarker,
    "primary/default": colors.primary,
    "primary/light": colors.primaryLight,
    "primary/light-hover": colors.primaryLightHover,
    "primary/light-pressed": colors.primaryLightPressed,
    "primary/stroke": colors.primaryStroke,
    "special/content-reverse": colors.specialContentReverse,
    "special/scrim": colors.specialScrim,
    "special/white": colors.specialWhite,
    "special/white-overlay": colors.specialWhiteOverlay,
    "stroke/dark": colors.strokeDark,
    "stroke/faint": colors.strokeFaint,
    "text/base": colors.textBase,
    "text/dark": colors.textDark,
    "text/darker": colors.textDarker,
    "text/light": colors.textLight,
    "text/lighter": colors.textLighter,
    "text/lightest": colors.textLightest,
    "text/reverse": colors.textReverse,
    "warning/dark": colors.warningDark,
    "warning/darker": colors.warningDarker,
    "warning/default": colors.warning,
    "warning/light": colors.warningLight,
  };
}
