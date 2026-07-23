export 'extensions.dart';
export 'l10n/strings_localizations.dart';

/// Marks user-visible copy that should move to localized ARB after it settles.
String pendingTranslation(String s) => s;

/// Marks user-visible copy that intentionally should not be translated.
String untranslated(String s) => s;
