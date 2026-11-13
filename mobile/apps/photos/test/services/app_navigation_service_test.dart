import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/app_navigation_service.dart';
import 'package:photos/settings/local_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    ServiceLocator.instance.localSettings = LocalSettings(
      await SharedPreferences.getInstance(),
    );
  });

  testWidgets('guards external navigation across Guest view transitions', (
    tester,
  ) async {
    final navigation = AppNavigationService.instance;
    var intentUpdates = 0;
    Widget app() => MaterialApp(
      navigatorKey: navigation.navigatorKey,
      home: const Scaffold(body: Text('Selected Guest photos')),
    );

    await tester.pumpWidget(app());
    await localSettings.setOnGuestView(true);

    final activeResult = navigation.pushPage<Object>(
      const Scaffold(body: Text('External content')),
      onBeforePush: () => intentUpdates++,
    );
    await tester.pumpAndSettle();

    expect(find.text('External content'), findsNothing);
    expect(find.text('Selected Guest photos'), findsOneWidget);
    expect(await activeResult, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await localSettings.setOnGuestView(false);
    final waitingResult = navigation.pushPage<Object>(
      const Scaffold(body: Text('External content')),
      onBeforePush: () => intentUpdates++,
    );
    await tester.pump();
    await localSettings.setOnGuestView(true);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('External content'), findsNothing);
    expect(await waitingResult, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await localSettings.setOnGuestView(true);
    final ignoredResult = navigation.pushPage<Object>(
      const Scaffold(body: Text('External content')),
      onBeforePush: () => intentUpdates++,
    );
    await localSettings.setOnGuestView(false);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('External content'), findsNothing);
    expect(await ignoredResult, isNull);
    expect(intentUpdates, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app());
    await localSettings.setOnGuestView(true);
    await localSettings.setOnGuestView(false);

    final result = navigation.pushPage<String>(
      const Scaffold(body: Text('External content')),
      onBeforePush: () => intentUpdates++,
      forceCustomPageRoute: true,
    );
    await tester.pumpAndSettle();
    expect(find.text('External content'), findsOneWidget);

    navigation.navigator!.pop('done');
    await tester.pumpAndSettle();
    expect(await result, 'done');
    expect(intentUpdates, 1);
    expect(find.text('Selected Guest photos'), findsOneWidget);
  });
}
