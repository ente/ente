import 'dart:io';

import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/ente_theme_data.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/services/preference_service.dart';
import 'package:ente_auth/ui/code_widget.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
const _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);
final _codeText = find.byWidgetPredicate(
  (widget) =>
      widget is Text && RegExp(r'^\d+( \d+)*$').hasMatch(widget.data ?? ''),
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final root = await Directory.systemTemp.createTemp('auth_text_scale_');
    messenger.setMockMethodCallHandler(
      _pathProviderChannel,
      (_) async => root.path,
    );
    messenger.setMockMethodCallHandler(_secureStorageChannel, (_) async {
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    await Configuration.instance.init([]);
    await PreferenceService.instance.init();
  });

  for (final isCompactMode in [false, true]) {
    testWidgets(
      'fits every digit at 2x text${isCompactMode ? ' in compact mode' : ''}',
      (tester) async {
        // Every glyph of the test font is 1 em wide, so 480 dp is narrow here
        tester.view.physicalSize = const Size(960, 1600);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_app(_code(), isCompactMode: isCompactMode));

        final codes = _codeText.evaluate().toList();
        expect(codes, hasLength(2));
        for (final code in codes) {
          final paragraph = code.renderObject! as RenderParagraph;
          expect(paragraph.didExceedMaxLines, isFalse);
        }

        final nextCode = tester.getRect(
          find.byElementPredicate((element) => element == codes.last),
        );
        final card = tester.getRect(find.byType(CodeWidget));
        expect(nextCode.width, lessThanOrEqualTo(card.width / 2));
      },
    );
  }
}

Code _code() {
  return Code.fromAccountAndSecret(
    Type.totp,
    'person@example.com',
    'Ente',
    'JBSWY3DPEHPK3PXP',
    null,
    8,
  );
}

Widget _app(Code code, {required bool isCompactMode}) {
  return MaterialApp(
    theme: lightThemeData,
    localizationsDelegates: StringsLocalizations.localizationsDelegates,
    supportedLocales: StringsLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(2)),
      child: child!,
    ),
    home: Scaffold(body: CodeWidget(code, isCompactMode: isCompactMode)),
  );
}
