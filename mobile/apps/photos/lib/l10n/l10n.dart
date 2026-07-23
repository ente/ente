import "package:flutter/widgets.dart";
import 'package:photos/generated/intl/app_localizations.dart';
import "package:shared_preferences/shared_preferences.dart";

// list of locales which are enabled for photos app.
// Add more language to the list only when at least 90% of the strings are
// translated in the corresponding language.
const List<Locale> appSupportedLocales = <Locale>[
  Locale('ca'),
  Locale('cs'),
  Locale('en'),
  Locale('es'),
  Locale('de'),
  Locale('fr'),
  Locale('it'),
  Locale('ja'),
  Locale("nl"),
  Locale("no"),
  Locale("pl"),
  Locale("pt", "BR"),
  Locale('pt', 'PT'),
  Locale("ro"),
  Locale("ru"),
  Locale("tr"),
  Locale("uk"),
  Locale("vi"),
  Locale("zh", "CN"),
];

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

List<Locale> _onDeviceLocales = [];
Locale? autoDetectedLocale;

Locale localResolutionCallBack(
  List<Locale>? deviceLocales,
  Iterable<Locale> supportedLocales,
) {
  _onDeviceLocales = deviceLocales ?? [];
  final Set<String> languageSupport = {};
  for (Locale supportedLocale in appSupportedLocales) {
    languageSupport.add(supportedLocale.languageCode);
  }
  for (Locale locale in _onDeviceLocales) {
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

// This is used to get locale that should be used for various formatting
// operations like date, time, number etc. For common languages like english, different
// locale might have different formats. For example, en_US and en_GB have different
// formats for date and time. Use this method to find the best locale for formatting
// operations. This is not used for displaying text in the app.
Future<Locale> getFormatLocale() async {
  final Locale locale = (await getLocale())!;
  Locale? firstLanguageMatch;
  // see if exact matche is present in the device locales
  for (Locale deviceLocale in _onDeviceLocales) {
    if (deviceLocale.languageCode == locale.languageCode &&
        deviceLocale.countryCode == locale.countryCode) {
      return deviceLocale;
    }
    if (firstLanguageMatch == null &&
        deviceLocale.languageCode == locale.languageCode) {
      firstLanguageMatch = deviceLocale;
    }
  }
  return firstLanguageMatch ?? locale;
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
