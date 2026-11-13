import 'package:ente_auth/locale.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => autoDetectedLocale = null);

  test('normalizes Portuguese to pt-BR', () {
    expect(_resolve(const Locale('pt')), const Locale('pt', 'BR'));
    expect(_resolve(const Locale('pt', 'PT')), const Locale('pt', 'BR'));
  });

  test('normalizes Chinese by script, then region', () {
    expect(
      _resolve(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ),
      const Locale('zh', 'TW'),
    );
    expect(
      _resolve(
        const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
          countryCode: 'TW',
        ),
      ),
      const Locale('zh', 'CN'),
    );
    expect(_resolve(const Locale('zh', 'HK')), const Locale('zh', 'TW'));
    expect(_resolve(const Locale('zh', 'MO')), const Locale('zh', 'TW'));
    expect(_resolve(const Locale('zh', 'TW')), const Locale('zh', 'TW'));
    expect(_resolve(const Locale('zh', 'CN')), const Locale('zh', 'CN'));
    expect(_resolve(const Locale('zh', 'SG')), const Locale('zh', 'CN'));
    expect(_resolve(const Locale('zh')), const Locale('zh', 'CN'));
    expect(_resolve(const Locale('zh', 'MY')), const Locale('zh', 'CN'));
  });

  testWidgets('loads common strings for an enabled regional locale', (
    tester,
  ) async {
    const locale = Locale('zh', 'TW');
    late Locale resolvedLocale;
    late String value;

    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
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

    expect(resolvedLocale, locale);
    expect(value, lookupStringsLocalizations(locale).ok);
  });
}

Locale _resolve(Locale locale) =>
    localResolutionCallBack([locale], appSupportedLocales);
