import "package:dio/dio.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/app_mode.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/app_navigation_service.dart";
import "package:photos/services/home_widget_service.dart";
import "package:photos/ui/settings/ml/ml_consent_sheet.dart";
import "package:photos/ui/settings/widgets/people_widget_settings.dart";
import "package:shared_preferences/shared_preferences.dart";

const _enableLabel = "Enable machine learning";
const _acknowledgement = "I understand, and wish to enable machine learning";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    await localSettings.setAppMode(AppMode.localGallery);
  });

  testWidgets("enable stays disabled until the acknowledgement is ticked", (
    tester,
  ) async {
    await _openSheet(tester);

    expect(_enableButton(tester).isDisabled, isTrue);

    await tester.tap(find.text(_acknowledgement));
    await tester.pumpAndSettle();
    expect(_enableButton(tester).isDisabled, isFalse);

    await tester.tap(find.text(_acknowledgement));
    await tester.pumpAndSettle();
    expect(_enableButton(tester).isDisabled, isTrue);
  });

  testWidgets("closing returns false and records the prompt as seen", (
    tester,
  ) async {
    final result = await _openSheet(tester);

    await tester.tap(find.byTooltip("Close"));
    await tester.pumpAndSettle();

    expect(await result, isFalse);
    expect(localSettings.hasSeenMLEnablingBanner, isTrue);
    expect(hasGrantedMLConsent, isFalse);
    expect(find.text(_enableLabel), findsNothing);
  });

  testWidgets(
    "people widget configure link asks for consent on the app navigator",
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(402, 874));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: AppNavigationService.instance.navigatorKey,
          theme: lightThemeData,
          localizationsDelegates: StringsLocalizations.localizationsDelegates,
          supportedLocales: StringsLocalizations.supportedLocales,
          home: const Scaffold(body: SizedBox()),
        ),
      );

      final launch = HomeWidgetService.instance.onLaunchFromWidget(
        Uri.parse("peoplewidget://configure"),
      );
      await tester.pumpAndSettle();
      expect(find.text(_acknowledgement), findsOneWidget);

      await tester.tap(find.byTooltip("Close"));
      await tester.pumpAndSettle();
      await launch;

      expect(find.text(_acknowledgement), findsNothing);
      expect(find.byType(PeopleWidgetSettings), findsNothing);
    },
  );
}

ButtonComponent _enableButton(WidgetTester tester) {
  return tester.widget<ButtonComponent>(
    find.widgetWithText(ButtonComponent, _enableLabel),
  );
}

Future<Future<bool>> _openSheet(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(402, 874));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  late Future<bool> result;
  await tester.pumpWidget(
    MaterialApp(
      theme: lightThemeData,
      localizationsDelegates: StringsLocalizations.localizationsDelegates,
      supportedLocales: StringsLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () => result = showMLConsentSheet(context),
              child: const Text("Open"),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text("Open"));
  await tester.pumpAndSettle();
  return result;
}
