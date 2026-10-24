# Plan

Three pull requests. Paths marked **proposed** do not exist yet. Do not expand a phase because a later phase is already designed.

## Phase 1 — Watch target and base bridge

Goal: a paired watch stores pinned (and `#watch`) TOTP seeds and computes the current code offline.

### Proposed files

| Path | Change |
| :---- | :---- |
| `mobile/apps/auth/ios/Runner/AppDelegate.swift` | Register the method channel. Keep the existing `GeneratedPluginRegistrant` and `app_links` behavior. The file today is a stock `FlutterAppDelegate`. |
| `mobile/apps/auth/ios/Runner/EnteWatchBridgePlugin.swift` | **New.** `FlutterMethodChannel` named `io.ente.auth/watch`, method `syncTokens`, then `WCSession.default.updateApplicationContext`. |
| `mobile/apps/auth/ios/Runner.xcodeproj` | Add a watchOS app target. Embed it in the Runner iOS app. Deployment target: the current watchOS default Xcode offers. Do not invent a minimum. iOS side today is `IPHONEOS_DEPLOYMENT_TARGET = 15.0` and `SUPPORTED_PLATFORMS = "iphonesimulator iphoneos"`. |
| `mobile/apps/auth/ios/EnteAuthWatch/` | **New** watchOS sources: `WatchSessionManager` (`WCSessionDelegate`), `WatchKeychainManager`, `TOTPCalculator`, `WatchToken`, a minimal list that shows issuer and current code. |
| `mobile/apps/auth/lib/services/watch_sync_service.dart` | **New.** `buildWatchPayload` and a listener on `CodesUpdatedEvent` that invokes `syncTokens`. |
| `mobile/apps/auth/test/services/watch_sync_payload_test.dart` | **New.** Filter tests below. |

### Explicitly untouched

- `AuthenticatorService` crypto and online sync, except that the new listener observes `CodesUpdatedEvent`, which that service already fires after sync.
- `mobile/packages/**` (`ente_crypto_api`, `ente_lock_screen`, `ente_configuration`, and the others).
- `server/`, `web/`, Photos, Locker, Rust.
- WidgetKit, Flutter settings UI, shielded mode, haptics, issuer SVG cache.

### Phase 1 done when

R1–R8, R11–R17, R19, R20, R24, R25, R27, R28 pass. The call site uses `syncAll: false`.

## Phase 2 — Full UI

- `TokenRowView` with `TimelineView(.periodic(from: .now, by: 1.0))` and `.privacySensitive()`.
- Next-code label when remaining ≤ 5.
- Digital Crown via a SwiftUI list.
- Empty, shielded, and ambient states from [DESIGN.md](DESIGN.md).
- Small issuer mark cache and the SHA-256 avatar.
- Optional haptic, default off.

Still no complications and no phone settings page.

## Phase 3 — Complications and phone settings

- WidgetKit extension on the watch target: `AccessoryCircular`, `AccessoryRectangular`, `AccessoryCorner`.
- Flutter Watch settings: "Sync All Accounts", and help text for pin and the `#watch` tag.
- The settings control only the boolean passed into `buildWatchPayload`. It does not add a new vault column.

## Test plan

### Swift TOTP

Run inside the watchOS target's tests (proposed XCTest):

| Case | Expect |
| :---- | :---- |
| RFC 4226, raw key `12345678901234567890`, count 0, 6 digits, SHA-1 | `755224` |
| RFC 6238, time 59, 8 digits, SHA-1 | `94287082` |
| Same time, SHA-256, 32-byte key from the RFC | `46119246` |
| Same time, SHA-512, 64-byte key from the RFC | `90693936` |
| Base32 `JBSWY3DPEHPK3PXP`, a fixed unix time, SHA-1, 6 digits | Equal to `otp.OTP.generateTOTPCodeString` for that time on the phone |
| `digits` modulus | Integer power, not `pow(10.0, Double(digits))` |

RFC keys are raw bytes. The base32 case is the otpauth path.

### Dart payload

From `mobile/apps/auth`:

```bash
flutter test test/services/watch_sync_payload_test.dart
```

CI (`.github/workflows/mobile-lint.yml`) runs `flutter test --no-pub` in every workspace package that has a `test/` directory, after `flutter pub get` at `mobile/`. New tests under `mobile/apps/auth/test/` are picked up by that loop.

| Case | Expect |
| :---- | :---- |
| Pinned TOTP | Included, `isFavorite: true` |
| Unpinned, tag `#watch` | Included, `isFavorite: false` |
| Unpinned, no tag, `syncAll` false | Excluded |
| `syncAll` true, unpinned TOTP | Included |
| `isTrashed` | Excluded; id in `deletedIds` if it was previously synced |
| `Type.steam` and issuer `steam` | Excluded, never a decimal code |
| `Type.hotp` | Excluded |
| `generatedID == null` | Excluded, and the secret is not used as an id |
| `CodeSortKey.manual` | `sortOrder` follows `position` |
| `CodeSortKey.issuerName` | Pinned eligible codes precede unpinned ones |
| Secret with spaces and lowercase | Payload secret equals `getSanitizedSecret` |

### Existing suite

Before sending the phase, run the auth package tests so the listener and imports did not break the vault:

```bash
cd mobile/apps/auth
flutter test
```

### Manual pairing checklist

1. Install the iOS app and the embedded watch app on a paired watch with a passcode.
2. Pin one SHA-1 TOTP account on the phone. Confirm it appears on the watch and matches the phone for the same period.
3. Confirm a Steam account and an HOTP account do not appear.
4. Trash the pinned account. Confirm the watch drops it after the next context.
5. Turn the watch passcode off. Confirm the message "Passcode required on Apple Watch to sync tokens" and that no new item appears in the watch Keychain.
6. Unplug the phone from the network and suspend the Flutter app. Confirm the watch still rolls the code.
7. Confirm device logs contain no secret and no live code.

Phase 2 adds: lower the wrist and confirm placeholders; with five seconds left, confirm the next code; turn the haptic on and feel one pulse at rollover.

Phase 3 adds: each complication family on a face, and the Sync All Accounts toggle.
