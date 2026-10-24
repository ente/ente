# Agents — Ente Auth watchOS companion

These instructions apply only while implementing or reviewing the Apple Watch companion specified in this folder. They are not the monorepo's root agent instructions. Do not create or edit a root `AGENTS.md`, a root `CLAUDE.md`, `docs/CLAUDE.md`, or `docs/README.md` as part of this feature.

## Read first

Read [README.md](README.md), then [REQUIREMENTS.md](REQUIREMENTS.md), [SYNC-CONTRACT.md](SYNC-CONTRACT.md), [PLAN.md](PLAN.md), and [THREAT-MODEL.md](THREAT-MODEL.md). Implement the phase the user named. If they did not name one, implement Phase 1 only.

## Phase 1 constraints

- Add a watchOS target under `mobile/apps/auth/ios`. Swift and SwiftUI. The watch target cannot import Flutter UI.
- Channel name `io.ente.auth/watch`, method `syncTokens`, patterned on `io.ente.auth/window_geometry` in `windows_window_placement.dart`.
- Send `updateApplicationContext` with the version-1 payload. Do not fetch a code over Bluetooth when the UI refreshes.
- Dart surface: `buildWatchPayload` plus a `CodesUpdatedEvent` listener. Do not rewrite `AuthenticatorService`.
- Map `isFavorite` from `code.display.pinned`. There is no `isFavorite` field in the Dart model.
- Include pinned codes and codes tagged exactly `#watch`. That tag is a convention, not an existing enum. Exclude trashed codes. Skip `Type.steam`, issuer `steam`, and `Type.hotp`.
- `id` is `generatedID.toString()`. Never put `rawData` in the payload id.
- Keychain service `io.ente.auth.watch`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `.devicePasscode`. If there is no passcode, store nothing.
- TOTP via CryptoKit for SHA-1, SHA-256, and SHA-512. Integer modulus, not `pow(10.0, Double(digits))`. Test the RFC vectors in [MATH.md](MATH.md).
- Watch clock is `Date()`. Do not copy `PreferenceService`'s time offset.
- Do not modify `server/`, `web/`, Photos, Locker, Rust, or `mobile/packages/**`.

## Style and safety

- Match neighboring files. Dart style in `watch_sync_service.dart` should look like `windows_window_placement.dart` and `code_store.dart`. Swift style should look like `AppDelegate.swift`.
- Never commit secrets, provisioning profiles, or a payload fixture that contains a real user's seed. RFC vectors and `JBSWY3DPEHPK3PXP` (the public base32 example) are fine.
- Never log OTP secrets, otpauth URLs, or live codes.
- Do not rebuild `graphify-out/`.
- Do not commit unless the user asks. Do not push or open a pull request unless the user asks.

## Tests

From `mobile/apps/auth`:

```bash
flutter test test/services/watch_sync_payload_test.dart
flutter test
```

The repo workflow `.github/workflows/mobile-lint.yml` runs `flutter test --no-pub` for each workspace package that contains a `test/` directory. Add the payload test under `mobile/apps/auth/test/` so that loop includes it.

Swift RFC tests live on the watch target. The manual pairing checklist is in [PLAN.md](PLAN.md).

## Labels

When a behavior is not in the current source, mark it as a recommendation in the pull-request description. Extracted facts and file paths are listed in [REFERENCES.md](REFERENCES.md).
