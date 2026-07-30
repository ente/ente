import "package:ente_components/theme/colors.dart" show ComponentApp;
import "package:ente_components/theme/theme.dart" show ComponentTheme;
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/generated/intl/app_localizations.dart";
import "package:photos/theme/text_style.dart" as ente_text;
import "package:photos/ui/payment/subscription_common_widgets.dart";

void main() {
  group("SubscriptionToggle", () {
    testWidgets("uses the provided initial billing period", (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const SubscriptionToggle(isYearly: false, onToggle: _noopToggle),
        ),
      );

      final togglePosition = tester.widget<AnimatedPositioned>(
        find.byType(AnimatedPositioned),
      );
      expect(togglePosition.left, greaterThan(0));
    });

    testWidgets("updates when the selected billing period changes", (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          const SubscriptionToggle(isYearly: false, onToggle: _noopToggle),
        ),
      );

      await tester.pumpWidget(
        _buildTestApp(
          const SubscriptionToggle(isYearly: true, onToggle: _noopToggle),
        ),
      );
      await tester.pumpAndSettle();

      final togglePosition = tester.widget<AnimatedPositioned>(
        find.byType(AnimatedPositioned),
      );
      expect(togglePosition.left, 0);
    });

    testWidgets("uses readable inactive text color in light theme", (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          const SubscriptionToggle(isYearly: true, onToggle: _noopToggle),
          theme: lightThemeData,
        ),
      );

      final monthlyLabel = tester.widget<Text>(find.text("Monthly"));
      expect(
        monthlyLabel.style?.color,
        ente_text.lightTextTheme.bodyMuted.color,
      );
    });

    testWidgets("uses Figma selected pill color in light theme", (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          const SubscriptionToggle(isYearly: true, onToggle: _noopToggle),
          theme: lightThemeData,
        ),
      );

      final selectedPill = tester.widget<Container>(
        find
            .ancestor(
              of: find.text("Yearly").last,
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = selectedPill.decoration! as BoxDecoration;
      expect(
        decoration.color,
        ComponentTheme.colorsForApp(ComponentApp.photos).fillLight,
      );
    });
  });
}

Widget _buildTestApp(Widget child, {ThemeData? theme}) {
  return MaterialApp(
    theme: theme ?? darkThemeData,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SizedBox(width: 320, child: child)),
  );
}

void _noopToggle(bool _) {}
