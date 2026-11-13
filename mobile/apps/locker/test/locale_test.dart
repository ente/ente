import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/core/locale.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => autoDetectedLocale = null);

  test('normalizes Portuguese to pt-PT', () {
    expect(_resolve(const Locale('pt')), const Locale('pt', 'PT'));
    expect(_resolve(const Locale('pt', 'BR')), const Locale('pt', 'PT'));
  });

  test('restores the generic Portuguese selector as pt-PT', () async {
    SharedPreferences.setMockInitialValues({'locale': 'pt'});

    expect(await getLocale(), const Locale('pt', 'PT'));
  });

  testWidgets('loads common strings for the Portuguese locale', (tester) async {
    const selectedLocale = Locale('pt');
    const resolvedPortuguese = Locale('pt', 'PT');
    late Locale resolvedLocale;
    late String value;

    await tester.pumpWidget(
      MaterialApp(
        locale: selectedLocale,
        supportedLocales: appSupportedLocales,
        localeListResolutionCallback: localResolutionCallBack,
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) {
            resolvedLocale = Localizations.localeOf(context);
            value = context.strings.ok;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(resolvedLocale, resolvedPortuguese);
    expect(value, lookupStringsLocalizations(resolvedPortuguese).ok);
  });
}

Locale _resolve(Locale locale) =>
    localResolutionCallBack([locale], appSupportedLocales);
