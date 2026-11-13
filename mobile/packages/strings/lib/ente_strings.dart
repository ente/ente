export 'extensions.dart';
export 'l10n/strings_localizations.dart';

// User-visible copy that should move to localized ARB after it settles.
String pendingTranslation(String s) => s;

// User-visible copy that intentionally should not be translated.
String untranslated(String s) => s;
