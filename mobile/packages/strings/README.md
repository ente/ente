# Ente strings

This package contains the user-facing strings and translations shared by the Auth, Locker, and Photos apps. Flutter's localization generator turns the ARB files in `lib/l10n/arb` into the Dart files in `lib/l10n`.

## Translate

The strings can be translated in the [Ente Mobile Crowdin project](https://crowdin.com/project/ente-photos-app).

If your language is not listed, [request it on GitHub](https://github.com/ente/ente/issues/new?title=Request+for+New+Language+Translation&body=Language+name%3A+%0AProject%3A+mobile).

Partial translations are welcome; apps generally enable a language after about 90% of their reachable strings are translated.

## Add a string

1. Add the key and English text to [`strings_en.arb`](lib/l10n/arb/strings_en.arb):

   ```json
   {
     "existingKey": "Existing text",
     "newStringKey": "Your new string text"
   }
   ```

2. Run `flutter gen-l10n` from `mobile/packages/strings`.

3. Import the package in the app code:

   ```dart
   import "package:ente_strings/ente_strings.dart";
   ```

4. Read the string from a `BuildContext`:

   ```dart
   context.strings.newStringKey
   ```

5. Commit the ARB and app changes.

After the pull request merges, the [source workflow](../../../.github/workflows/mobile-crowdin-push-sources.yml) will upload the new string to Crowdin.

## Plurals

Use the locale-aware `one` and `other` categories instead of `=1`:

```json
"photosCount": "{count, plural, =0{No photos} one{{count} photo} other{{count} photos}}"
```

`=0`, `one`, and `other` can be used together. Exact selectors are evaluated first; `one` is a locale category and does not always mean exactly `1`. When displaying the number, use the placeholder rather than hardcoding it in a plural branch.

## Update a string

> [!WARNING]
>
> Updating a source string (English) invalidates _all_ its translations.

1. Update its English text in [`strings_en.arb`](lib/l10n/arb/strings_en.arb).
2. Run `flutter gen-l10n` from `mobile/packages/strings`.
3. Commit the ARB change.

After the pull request merges, the source workflow will update the string in Crowdin.

## Delete a string

1. Remove or replace every use of the string in the app code.
2. Remove its value and any corresponding `@key` entry from [`strings_en.arb`](lib/l10n/arb/strings_en.arb).
3. Run `flutter gen-l10n` from `mobile/packages/strings`.
4. Commit the ARB and app changes.

After the pull request merges, the source workflow will remove the string from Crowdin. The next translation sync will remove it from the translated ARB files.
