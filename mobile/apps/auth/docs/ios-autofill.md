# iOS verification-code AutoFill

Ente Auth provides a native, authenticated TOTP picker on iOS 18 and later. The
containing Flutter app continues to support iOS 15. This first version uses manual
account search; domain matching and QuickType identity indexing are future work.
HOTP and Steam codes are excluded.

## Setup and signing

Use Xcode 16 or later. The `Runner` target embeds and depends on `AutoFill.appex`;
the extension has matching configurations for Debug, Release, Profile, Production
and Debug-production, with versions read from Flutter's generated xcconfig.

In the Apple developer account used for signing:

1. Register `io.ente.auth.autofill` as the extension's bundle identifier.
2. Enable AutoFill Credential Provider on both app identifiers.
3. Register the App Group `group.io.ente.auth.autofill` and assign both targets.
4. Allow the shared Keychain group `$(AppIdentifierPrefix)io.ente.auth.autofill`
   for both provisioning profiles. Runner also retains its original default
   Keychain group so existing account keys remain accessible.
5. Regenerate provisioning profiles. If using another development team or bundle
   identifier, update both entitlements, the shared group constant, the
   `AutoFillKeychainGroup` plist values, and `AutoFill/AutoFill.xcconfig` together.

In Ente Auth, open **Settings → General → Verification code AutoFill**, enable it,
then use **Open AutoFill settings** to enable Ente Auth in the system provider list.
For a verification-code field, choose Ente Auth from the system AutoFill options
and search for the account. Availability depends on the host app exposing the
field to iOS AutoFill.

## Data and authentication

`IOSAutoFillService` publishes a versioned snapshot through
`io.ente.auth/autofill`. It contains only saved, non-trashed TOTP entries and the
clock offset used by the main app. Record IDs are scoped to the online account or
offline vault. The snapshot refreshes on startup, foregrounding, code changes,
sign-in, and completed syncs. Changes from another device require the main app to
sync before they become available to the extension.

`AutoFillStore` encrypts the snapshot with AES-256-GCM and writes it atomically to
the App Group with complete file protection and backup exclusion. Its dedicated
key is stored in the shared Keychain with
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Account credentials and master
keys are not shared. The extension uses explicit LocalAuthentication
`deviceOwnerAuthentication` before reading the snapshot; it always requires user
interaction, independently of the Flutter app's PIN/password lock preference.
Enabling the feature also requires device authentication.

The extension generates codes at selection time, using SHA-1/256/512, the stored
digit count and period, and the main app's clock offset. It re-reads the snapshot
before returning a code, so a deleted entry or revoked snapshot cannot be filled
from an already-open picker's cache. Backgrounding cancels the picker and clears
its in-memory data.

Disabling AutoFill or signing out removes the shared key and snapshot. In-flight
reads cannot republish after revocation; native revocation does not wait for those
reads. Refresh failures disable the feature and attempt to remove stale data.
A fresh install also clears leftover shared Keychain material. Secrets and decode
errors are never included in bridge error messages.

## Verification

From `mobile/apps/auth/`:

```sh
flutter test test/services/ios_autofill_service_test.dart
# On macOS with Xcode:
swift test --package-path ios
```

The Swift package tests the production generator against all RFC 6238 vectors for
SHA-1, SHA-256 and SHA-512, plus custom periods, leading zeroes, secret normalization
and invalid parameters. The Flutter tests cover opt-in, authentication cancellation,
eligibility filtering, startup refresh, account scoping, failure cleanup and
revocation during an in-flight read.

On an iOS 18+ device, verify:

- Enablement, authentication cancellation, Face ID/Touch ID and passcode fallback.
- Filling in Safari and an app with a `oneTimeCode` input, including when Runner
  has been terminated and the device is offline.
- Search, duplicate account labels, empty results, and selection across a TOTP
  period boundary; compare the result with the main app.
- Edits, trash, deletion, imports and remote sync replacing the published data.
- Disablement and logout while a picker is open; previously listed codes must no
  longer fill. Re-enabling must publish a new snapshot.
- Fresh install/reinstall, app backgrounding, and a device without biometrics but
  with a passcode configured.
- A build/install on iOS 15–17 still launches normally and hides AutoFill settings.
