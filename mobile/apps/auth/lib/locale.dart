import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

// list of locales which are enabled for auth app.
// Add more language to the list only when at least 90% of the strings are
// translated in the corresponding language.
const List<Locale> appSupportedLocales = <Locale>[
  Locale('ar'),
  Locale('bg'),
  Locale('ca'),
  Locale('cs'),
  Locale('de'),
  Locale('el'),
  Locale('en'),
  Locale('es', 'ES'),
  Locale('fa'),
  Locale('fr'),
  Locale('he'),
  Locale('hu'),
  Locale('id'),
  Locale('it'),
  Locale('ja'),
  Locale('ko'),
  Locale('lt'),
  Locale('nl'),
  Locale('pl'),
  Locale('pt'),
  Locale('pt', 'BR'),
  Locale('ro'),
  Locale('ru'),
  Locale('sl'),
  Locale('sk'),
  Locale('tr'),
  Locale('uk'),
  Locale('vi'),
  Locale("zh", "CN"),
  Locale("zh", "TW"),
];

Locale? autoDetectedLocale;
// This function takes device locales and supported locales as input
// and returns the best matching locale.
// The device locales are sorted by priority, so the first one is the most preferred.
Locale localResolutionCallBack(
  List<Locale>? onDeviceLocales,
  Iterable<Locale> supportedLocales,
) {
  final Set<String> languageSupport = {};
  for (Locale supportedLocale in appSupportedLocales) {
    languageSupport.add(supportedLocale.languageCode);
  }
  for (Locale locale in onDeviceLocales ?? const []) {
    // check if exact local is supported, if yes, return it
    if (appSupportedLocales.contains(locale)) {
      autoDetectedLocale = locale;
      return locale;
    }
    // check if language code is supported, if yes, return it
    if (languageSupport.contains(locale.languageCode)) {
      autoDetectedLocale = locale;
      return locale;
    }
  }
  // Return the first language code match or default to 'en'
  return autoDetectedLocale ?? const Locale('en');
}

Future<Locale?> getLocale({bool noFallback = false}) async {
  final String? savedValue = (await SharedPreferences.getInstance()).getString(
    'locale',
  );
  // if savedLocale is not null and is supported by the app, return it
  if (savedValue != null) {
    late Locale savedLocale;
    if (savedValue.contains('_')) {
      final List<String> parts = savedValue.split('_');
      savedLocale = Locale(parts[0], parts[1]);
    } else {
      savedLocale = Locale(savedValue);
    }
    if (appSupportedLocales.contains(savedLocale)) {
      return savedLocale;
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
