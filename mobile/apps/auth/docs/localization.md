## Localization

If the feature requires adding new strings, you can do that by following these steps:

1. Add a new entry inside [app_en.arb](https://github.com/ente/ente/blob/main/auth/lib/l10n/arb/app_en.arb) (remember to save!)

2. In your dart file, add the following import

   ```dart
   import "package:ente_auth/l10n/l10n.dart";
   ```

3. Refer to the string using `context.l10n.<keyName>`. For example

   ```dart
   context.l10n.account
   ```
