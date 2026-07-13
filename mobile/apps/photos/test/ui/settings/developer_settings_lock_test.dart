import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/core/network/endpoint_policy.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/settings/developer_settings_tap_area.dart";
import "package:photos/ui/settings/developer_settings_widget.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    ServiceLocator.instance.init(
      preferences,
      Dio(),
      Dio(),
      Dio(),
      PackageInfo(
        appName: "Photos",
        packageName: "photos",
        version: "1.0.0",
        buildNumber: "1",
      ),
    );
  });

  testWidgets("the seven-tap editor follows the compile-time lock", (
    tester,
  ) async {
    const tapAreaKey = ValueKey("developerSettingsTapArea");
    await tester.pumpWidget(
      const MaterialApp(
        home: DeveloperSettingsTapArea(key: tapAreaKey, child: Text("Ente")),
      ),
    );

    final detector = find.descendant(
      of: find.byKey(tapAreaKey),
      matching: find.byType(GestureDetector),
    );
    expect(detector, kLockedEndpoint ? findsNothing : findsOneWidget);
  });

  testWidgets("the self-hosted endpoint remains visible as read-only text", (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: DeveloperSettingsWidget()),
      ),
    );
    await tester.pumpAndSettle();

    final endpointHost = Uri.parse(kCompiledEndpoint).host;
    expect(
      find.textContaining(endpointHost),
      kLockedEndpoint ? findsOneWidget : findsNothing,
    );
    expect(find.byType(TextField), findsNothing);
  });
}
