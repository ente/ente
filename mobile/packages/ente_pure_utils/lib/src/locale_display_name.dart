import 'package:flutter/widgets.dart';

String getLocaleDisplayName(Locale locale) {
  switch (locale.languageCode) {
    case 'ca':
      return 'Català';
    case 'cs':
      return 'Čeština';
    case 'ar':
      return 'العربية';
    case 'bg':
      return 'Български';
    case 'de':
      return 'Deutsch';
    case 'el':
      return 'Ελληνικά';
    case 'en':
      return 'English';
    case 'es':
      switch (locale.countryCode) {
        case 'ES':
          return 'Español (España)';
        default:
          return 'Español';
      }
    case 'fa':
      return 'فارسی';
    case 'fi':
      return 'Suomi';
    case 'fr':
      return 'Français';
    case 'he':
      return 'עברית';
    case 'hu':
      return 'Magyar';
    case 'id':
      return 'Bahasa Indonesia';
    case 'it':
      return 'Italiano';
    case 'ja':
      return '日本語';
    case 'ko':
      return '한국어';
    case 'lt':
      return 'Lietuvių';
    case 'nl':
      return 'Nederlands';
    case 'no':
      return 'Norsk';
    case 'pl':
      return 'Polski';
    case 'pt':
      if (locale.countryCode == 'BR') {
        return 'Português (Brasil)';
      } else if (locale.countryCode == 'PT') {
        return 'Português (Portugal)';
      }
      return 'Português';
    case 'ro':
      return 'Română';
    case 'ru':
      return 'Русский';
    case 'sk':
      return 'Slovenčina';
    case 'sl':
      return 'Slovenščina';
    case 'tr':
      return 'Türkçe';
    case 'zh':
      if (locale.countryCode == 'TW') {
        return '中文 (台灣)';
      } else if (locale.countryCode == 'HK') {
        return '中文 (香港)';
      } else if (locale.countryCode == 'CN') {
        return '中文 (中国)';
      }
      switch (locale.scriptCode) {
        case 'Hans':
          return '中文 (简体)';
        case 'Hant':
          return '中文 (繁體)';
        default:
          return '中文';
      }
    case 'uk':
      return 'Українська';
    case 'vi':
      return 'Tiếng Việt';
    default:
      return locale.languageCode;
  }
}
