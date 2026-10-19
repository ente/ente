import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/ui/payment/subscription_common_widgets.dart";

void main() {
  group("SubscriptionToggle", () {
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

      final toggleAlignment = tester.widget<AnimatedAlign>(
        find.byType(AnimatedAlign),
      );
      expect(toggleAlignment.alignment, Alignment.centerLeft);
    });
  });
}

Widget _buildTestApp(Widget child, {ThemeData? theme}) {
  return MaterialApp(
    theme: theme ?? darkThemeData,
    localizationsDelegates: StringsLocalizations.localizationsDelegates,
    supportedLocales: StringsLocalizations.supportedLocales,
    home: Scaffold(body: SizedBox(width: 320, child: child)),
  );
}

void _noopToggle(bool _) {}
