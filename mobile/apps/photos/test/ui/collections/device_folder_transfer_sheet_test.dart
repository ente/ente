import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photos/ente_theme_data.dart';
import 'package:photos/models/device_collection.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/settings/local_settings.dart';
import 'package:photos/ui/collections/device/device_folder_transfer_sheet.dart';
import 'package:photos/ui/viewer/file/no_thumbnail_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    ServiceLocator.instance.localSettings = LocalSettings(
      await SharedPreferences.getInstance(),
    );
    final fonts = FontLoader('packages/ente_components/Inter');
    for (final name in ['Regular', 'Medium', 'SemiBold']) {
      fonts.addFont(
        rootBundle.load('packages/ente_components/fonts/Inter-$name.ttf'),
      );
    }
    await fonts.load();
  });

  testWidgets('picker shows empty albums and searches without rescanning', (
    tester,
  ) async {
    var loads = 0;
    await _pump(
      tester,
      title: 'Add to album',
      loadFolders: () async {
        loads++;
        return [DeviceCollection('empty', 'Empty album')];
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('Add to album'), findsOneWidget);
    expect(find.text('Empty album'), findsOneWidget);
    expect(find.byType(NoThumbnailWidget), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'camera');
    await tester.pumpAndSettle();
    expect(find.text('No results found'), findsOneWidget);
    expect(loads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed destination scan can be retried', (tester) async {
    var attempts = 0;
    await _pump(
      tester,
      loadFolders: () async {
        if (++attempts == 1) throw StateError('Permission changed');
        return [];
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load albums'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No albums available for these items'), findsOneWidget);
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits light and dark layouts with large text and keyboard', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      await tester.binding.setSurfaceSize(const Size(640, 320));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(
        tester,
        dark: dark,
        keyboard: 180,
        textScale: 2,
        loadFolders: () async => [],
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required Future<List<DeviceCollection>> Function() loadFolders,
  bool dark = false,
  double keyboard = 0,
  double textScale = 1,
  String? title,
}) => tester.pumpWidget(
  MaterialApp(
    theme: (dark ? darkThemeData : lightThemeData).copyWith(
      platform: TargetPlatform.iOS,
    ),
    localizationsDelegates: StringsLocalizations.localizationsDelegates,
    supportedLocales: StringsLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        viewInsets: EdgeInsets.only(bottom: keyboard),
      ),
      child: child!,
    ),
    home: Scaffold(
      resizeToAvoidBottomInset: false,
      body: Align(
        alignment: Alignment.bottomCenter,
        child: DeviceFolderTransferSheet(
          title: title ?? 'Move to album',
          loadFolders: loadFolders,
        ),
      ),
    ),
  ),
);
