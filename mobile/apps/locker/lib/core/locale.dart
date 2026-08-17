import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Add more language to the list only when at least 90% of the strings are
// translated in the corresponding language.
const List<Locale> appSupportedLocales = <Locale>[
  Locale('cs'),
  Locale('de'),
  Locale('en'),
  Locale('es'),
  Locale('fr'),
  Locale('it'),
  Locale('ja'),
  Locale('nl'),
  Locale('pl'),
  Locale('pt'),
  Locale('ro'),
  Locale('ru'),
  Locale('tr'),
  Locale('uk'),
  Locale('vi'),
];

Locale? autoDetectedLocale;
Locale localResolutionCallBack(
  List<Locale>? onDeviceLocales,
  Iterable<Locale> supportedLocales,
) {
  final Set<String> languageSupport = {};
  for (Locale supportedLocale in appSupportedLocales) {
    languageSupport.add(supportedLocale.languageCode);
  }
  for (final deviceLocale in onDeviceLocales ?? const []) {
    final locale = _normalizedLocale(deviceLocale);
    if (appSupportedLocales.contains(locale)) {
      autoDetectedLocale = locale;
      return locale;
    }
    if (languageSupport.contains(locale.languageCode)) {
      autoDetectedLocale = locale;
      return locale;
    }
  }
  return autoDetectedLocale ?? const Locale('en');
}

Future<Locale?> getLocale({bool noFallback = false}) async {
  final String? savedValue = (await SharedPreferences.getInstance()).getString(
    'locale',
  );
  if (savedValue != null) {
    late Locale savedLocale;
    if (savedValue.contains('_')) {
      final List<String> parts = savedValue.split('_');
      savedLocale = Locale(parts[0], parts[1]);
    } else {
      savedLocale = Locale(savedValue);
    }
    if (appSupportedLocales.contains(savedLocale)) {
      return _normalizedLocale(savedLocale);
    }
  }
  if (autoDetectedLocale != null) {
    return autoDetectedLocale!;
  }
  if (noFallback) {
    return null;
  }
  return const Locale('en');
}

Future<void> setLocale(Locale locale) async {
  if (!appSupportedLocales.contains(locale)) {
    throw Exception('Locale $locale is not supported by the app');
  }
  final StringBuffer out = StringBuffer(locale.languageCode);
  if (locale.countryCode != null && locale.countryCode!.isNotEmpty) {
    out.write('_');
    out.write(locale.countryCode);
  }
  await (await SharedPreferences.getInstance()).setString(
    'locale',
    out.toString(),
  );
}

Locale _normalizedLocale(Locale locale) =>
    locale.languageCode == 'pt' ? const Locale('pt', 'PT') : locale;
