# Requirements

IDs are stable. Phase tags say when the behavior must exist. Acceptance is how a reviewer tells the requirement is met. **EXTRACTED** facts come from the current tree or the spec file. **INFERRED** items are choices this doc set adds so Phase 1 has one behavior.

Spec file: `building the app for ente feels like a good idea....md` (repository root).

## Spec words and the symbols that exist today

| Spec or contract word | What the Auth app actually has | Mapper rule |
| :---- | :---- | :---- |
| `isFavorite` | There is no `isFavorite` field. `Code.isPinned` returns `display.pinned`. `CodeDisplay.pinned` is a `bool` (`mobile/apps/auth/lib/models/code.dart`, `code_display.dart`). Aegis import copies Aegis `favorite` onto `pinned` (`aegis_import.dart`). | Payload field stays `isFavorite`. Dart reads `code.display.pinned`. |
| `#watch` tag | `CodeDisplay.tags` is `List<String>`. Tags are freeform chips (`TagChip` / `TagChipState` in `mobile/apps/auth/lib/onboarding/view/common/tag_chip.dart` and `onboarding/model/tag_enums.dart`). No reserved tag string exists. | **INFERRED.** Include a code when any tag equals `#watch` after trim. |
| Manual sort | `CodeDisplay.position` is the stored manual index. `HomePage.sortFilteredCodes` uses it only for `CodeSortKey.manual`. `CodeStore.getAllCodes` sorts pinned first, then issuer, then account, and does not compare `position`. | Watch `sortOrder` is the index after the home-screen sort. See R16. |
| Next code | `getNextTotp` in `totp_util.dart`. `CodeWidget` shows it for `Type.isTOTPCompatible` (`totp` and `steam`) for the whole period. HOTP shows a forward icon, not a second number. | Watch shows the next code only when remaining ≤ 5 seconds (spec). |
| Hide codes | `PreferenceService.shouldHideCodes()` (`kShouldHideCodesKey`). `CodeWidget._getFormattedCode` replaces non-whitespace with `•`. | Phone masking is a preference. Watch ambient masking is `.privacySensitive()`. They are different mechanisms. The graph's similarity edge is inferred. |
| Clock | `millisecondsSinceEpoch()` adds `PreferenceService.timeOffsetInMilliSeconds()` (`kLocalTimeOffsetKey`). | Watch uses `Date()` / the watch system clock. See R20. |
| Secret store | Seeds live in the encrypted authenticator DB (`AuthenticatorDB` / `OfflineAuthenticatorDB`, ciphertext in `encryptedData`), decrypted in `AuthenticatorService.getEntities`. | Watch seeds live in the watch Keychain. See R6 and R29. |
| `FlutterSecureStorage` | `Configuration` (`mobile/apps/auth/lib/core/configuration.dart`) stores account key material (`auth_secret_key`, `offline_auth_secret_key`) with `KeychainAccessibility.first_unlock_this_device`. | That store is not the OTP seed table and not the watch Keychain. |
| Native bridge pattern | `WindowsWindowPlacement` uses `MethodChannel('io.ente.auth/window_geometry')` (`windows_window_placement.dart`). | **INFERRED channel name:** `io.ente.auth/watch`. |
| iOS runner | `AppDelegate.swift` is a stock `FlutterAppDelegate`. It registers `GeneratedPluginRegistrant` and handles `app_links`. `Runner.xcodeproj` sets `SUPPORTED_PLATFORMS = "iphonesimulator iphoneos"` and `IPHONEOS_DEPLOYMENT_TARGET = 15.0`. | Phase 1 adds a channel registration and a watchOS target. |

## Functional requirements

### R1 — Autonomous watch node (Phase 1)

The watch generates TOTP locally from seeds it stores. Daily display does not send a request to the phone.

**Acceptance:** Airplane mode on the phone, watch still unlocked and previously synced, the current code still advances every period.

### R2 — No per-display Bluetooth fetch (Phase 1)

The implementation does not call the phone when a row renders or when a complication timeline reloads.

**Acceptance:** Code generation is a local function of secret, algorithm, digits, period, and the watch date. Review finds no `WCSession` send inside `TOTPCalculator`.

### R3 — Method channel (Phase 1)

**INFERRED name**, chosen to match `io.ente.auth/window_geometry`: `MethodChannel('io.ente.auth/watch')`.

Phone → native method: `syncTokens`. Arguments are the JSON object in [SYNC-CONTRACT.md](SYNC-CONTRACT.md). Native code sends that dictionary to the watch with Watch Connectivity. The watch does not call back into Dart on each tick.

**Acceptance:** A unit test can build the payload without a watch. A debug build invokes `syncTokens` only when codes change, not once per second.

### R4 — Change-driven sync (Phase 1)

Push a payload when the eligible set changes: add, update, rename, pin, unpin, tag edit, trash, restore, delete.

**EXTRACTED hooks:** `CodeStore.addCode` and `CodeStore.removeCode` fire `CodesUpdatedEvent` (`mobile/apps/auth/lib/store/code_store.dart`). `AuthenticatorService._onlineSyncOnce` also fires it after a remote sync. The event type is an empty `CodesUpdatedEvent` in `mobile/apps/auth/lib/events/codes_updated_event.dart`.

**Acceptance:** The Dart trigger listens for `CodesUpdatedEvent` (and any write path that changes pin, tags, trash, or secret without that event, if one is found). It does not fork the encrypt/decrypt path inside `AuthenticatorService`.

### R5 — Watch Connectivity transport (Phase 1)

Use `WCSession`. Apple's reference, verified by fetching the documentation JSON:

- `updateApplicationContext`: "This method replaces the previous dictionary that was set." It may be called when the counterpart is not currently reachable. The counterpart sees the most recent context.
- `transferUserInfo`: dictionaries "are queued on the other device and delivered in the order in which they were sent." A transfer that has started continues if the app is suspended.

**INFERRED Phase 1 choice:** send only `updateApplicationContext`, with the full eligible set in `tokens` and removals in `deletedIds`. Do not also enqueue `transferUserInfo` in Phase 1. A queued user-info dictionary can arrive after a newer context and put a removed seed back.

The spec names Apple's transport as AES-GCM. This doc set did not re-derive the cipher from the API reference. The verified point is the queue-versus-replace behavior. The JSON still contains the base32 secret as a plaintext string. See [THREAT-MODEL.md](THREAT-MODEL.md).

**Acceptance:** With the watch out of range, two quick edits result in the watch applying the later context once it reconnects, and the earlier context is not applied afterwards.

### R6 — Watch Keychain (Phase 1)

Store each seed as a generic password:

- `kSecClassGenericPassword`
- `kSecAttrService` = `io.ente.auth.watch`
- `kSecAttrAccount` = the token `id`
- `kSecValueData` = the raw seed bytes after base32 decode
- accessibility `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`

Apple's page for that constant: the item can be read only while the device is unlocked, and items with this attribute do not migrate to a new device, so a restore onto a different device does not contain them.

Never `UserDefaults`. Never a raw file in the watch container.

**Acceptance:** After unpairing or erasing, a new watch does not already contain the seeds. A Keychain dump of an iCloud-synced item set on another device does not contain `io.ente.auth.watch` items created here.

### R7 — Passcode required (Phase 1)

Create the access-control object with `SecAccessControlCreateWithFlags`, protection `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, flags `.devicePasscode`. If the watch has no passcode, do not write or read seeds. Surface the spec string: "Passcode required on Apple Watch to sync tokens".

**Acceptance:** A watch with passcode off completes sync with zero Keychain items and shows that message. Turning a passcode on allows a later sync to store seeds.

### R8 — Wrist lock (Phase 1)

**EXTRACTED requirement from the spec:** when the user takes the watch off, watchOS locks it (wrist detection plus passcode). Items stored under R6 and R7 stay unreadable until the user unlocks with the passcode. The spec also says watchOS purges volatile decryption keys from RAM on removal. Treat that sentence as the spec's description of the lock, and rely on Keychain accessibility rather than an app-managed cache of seeds across lock.

**Acceptance:** Remove the watch, reattach, and confirm codes stay unavailable until the passcode is entered. The app does not cache decoded seeds in `UserDefaults` to skip that prompt.

### R9 — Ambient masking (Phase 2)

Apply `.privacySensitive()` to the current code, the next code, and the progress ring. In ambient mode and when `ScenePhase` is inactive, the system replaces them with placeholders.

**Acceptance:** Lower the wrist or enter always-on ambient and confirm the digits are not readable. Raise and unlock, and the digits return.

### R10 — Shielded mode (Phase 2)

Optional setting. While it is on, list rows stay masked until that row is tapped.

**Acceptance:** With the setting on, a freshly opened list shows placeholders. One tap reveals that row. The setting survives watch relaunch (watch-local preference, not a seed).

### R11 — Memory scrubbing (Phase 1)

The spec requires a Swift reference type whose `deinit` zeroes its buffer with `memset_s`. Use that type for the bytes passed into HMAC.

**INFERRED:** `WatchToken.secret` in the spec is a `String`, and Swift strings are not a reliable scrub target. Decode base32 into the reference type, generate the code, and drop the reference. Do not log the bytes.

**Acceptance:** Code review shows `memset_s` on the seed buffer in `deinit`, and no `print`/`Logger` of the secret or the OTP.

### R12 — Default subset (Phase 1)

Default sync includes a code only when `code.isPinned` is true or a tag equals `#watch` (R14, recommendation in the mapping table).

**Acceptance:** Given a fixture of five codes where one is pinned, one is tagged `#watch`, and three are neither, the payload `tokens` array has length 2.

### R13 — Sync all accounts (Phase 3 UI, flag supported by the Phase 1 function)

A phone setting "Sync All Accounts" passes `syncAll: true`. The payload then includes every code that survives R15 and R17.

**Acceptance:** The pure function returns the full eligible list when `syncAll` is true and the subset from R12 when it is false. Phase 1's call site passes `false` until the settings screen exists.

### R14 — Favorite field mapping (Phase 1)

JSON `isFavorite` is `code.display.pinned`. The Dart model has no `isFavorite` property. Do not invent one on `Code`.

**Acceptance:** A pinned code serializes `"isFavorite": true`. An unpinned code that is included only because of `#watch` or `syncAll` serializes `"isFavorite": false`.

### R15 — Trashed codes stay off the watch (Phase 1)

`Code.isTrashed` is `display.trashed`. Trashed codes are omitted from `tokens`. If that id was synced before, it is listed in `deletedIds`.

**Acceptance:** A payload test trashes a previously included id and expects the id absent from `tokens` and present in `deletedIds`.

### R16 — Order mirrors the phone (Phase 1)

**EXTRACTED sort behavior:**

- `PreferenceService.codeSortKey()` defaults to `CodeSortKey.issuerName` (`mobile/apps/auth/lib/services/preference_service.dart`).
- `HomePage.sortFilteredCodes` (`home_page.dart`): `manual` compares `display.position`. Other keys sort by issuer, account, `tapCount`, `lastUsedAt`, or `createdAt`/`generatedID`. When the key is not `manual`, pinned codes are then moved to the front, stable relative to the sort.
- `CodeStore.getAllCodes` with `sortCodes: true` uses a different comparator: pinned first, then issuer, then account. `CodeStore.saveUpadedIndexes` writes `position` from the list index (the method name is spelled `saveUpadedIndexes` in source).

**INFERRED:** `sortOrder` is the index of the code in the eligible list after `HomePage.sortFilteredCodes` for the current `CodeSortKey`. That is the order the person sees. Do not sort the watch by raw `position` when the phone is in issuer order, and do not reorder a manual list by pinning.

**Acceptance:** A payload test with `CodeSortKey.manual` expects `sortOrder` to follow `position` among eligible codes. A test with `issuerName` expects pinned eligible codes before unpinned ones, and issuer order inside each group.

### R17 — Skip Steam and HOTP (Phase 1)

`Type` is `totp`, `hotp`, or `steam` (`code.dart`). `getOTP` uses `steam_totp` when `type == steam` or the issuer lowercased equals `steam`, and `otp.OTP.generateHOTPCodeString` for `Type.hotp`. The spec's `TOTPCalculator` covers SHA-1, SHA-256, and SHA-512 TOTP only.

Phase 1 omits `Type.steam`, `Type.hotp`, and any code whose issuer lowercased equals `steam`. If that id was previously on the watch, add it to `deletedIds`. Do not emit a decimal TOTP for those secrets.

**Acceptance:** Payload tests include one Steam code and one HOTP code and expect neither in `tokens`. A Swift test does not have a Steam or HOTP generator in Phase 1.

### R18 — Next code at 5 seconds (Phase 2)

`remaining = period - (unixSeconds mod period)`. When `remaining <= 5`, show `Next: ` plus the following code. The spec's example grouping for six digits is `839 201`.

The phone already shows the next code for the entire period (`CodeWidget` + `getNextTotp`). The five-second fade-in is the watch behavior from the spec.

**Acceptance:** At remaining 6 the next label is absent. At remaining 5 it is visible. The next value equals HOTP at `counter + 1`.

### R19 — Local TOTP engine (Phase 1)

`TOTPCalculator.generateCode` returns `(current, next, remainingSeconds)` for `WatchToken.HashAlgorithm` `sha1` / `sha256` / `sha512`, using CryptoKit HMAC (`Insecure.SHA1`, `SHA256`, `SHA512`). Dynamic truncation matches RFC 4226. Test vectors are in [MATH.md](MATH.md).

**INFERRED review comment on the spec snippet:** replace `UInt32(pow(10.0, Double(digits)))` with an integer power. See [MATH.md](MATH.md). The snippet is a proposal, not production code.

**Acceptance:** Swift tests pass the RFC 4226 count-0 vector and the RFC 6238 time-59 SHA-1, SHA-256, and SHA-512 vectors at 8 digits. A SHA-256 secret does not go through the SHA-1 branch.

### R20 — Clock policy (Phase 1)

**INFERRED.** The watch uses its system clock (the watch's own time, which watchOS keeps in step with network time when the watch is online). Do not add `PreferenceService`'s offset on the watch. The phone offset exists so a wrong phone clock can still match a server. Copying it would make the watch wrong whenever the phone offset is stale, and it would leave the watch unchanged when only the watch clock is wrong.

RFC 6238's resynchronization discussion allows a verifier to accept one neighboring time step. The watch is a generator. If its clock is off by more than one period, its code will not match the site. That residual risk is accepted in Phase 1.

**Acceptance:** `generateCode` uses the `date` argument, defaulting to `Date()`. No API reads the phone's `local_time_offset` preference.

### R21 — Complications (Phase 3)

WidgetKit families, all three required by the spec:

| Family | Behavior |
| :---- | :---- |
| `AccessoryCircular` | Countdown for the current period. Tap opens the app on the top sorted token. |
| `AccessoryRectangular` | Issuer, account, and the live code for that same token, via a timeline provider. |
| `AccessoryCorner` | Icon plus a progress arc for the remaining fraction of the period. |

The rectangular live code is glanceable. See the threat model before enabling it by default.

**Acceptance:** Each family renders on a watch face. The code matches `TOTPCalculator` at the timeline entry's date. Reloads do not call the phone (R2).

### R22 — Issuer marks (Phase 2)

Cache small monochrome or tinted marks for GitHub, AWS, Google, Proton, Discord, and Cloudflare. The phone already resolves icons in `IconUtils`: custom SVG, then vendored simple-icons under `assets/simple-icons/`, then a one-letter avatar colored by `String.hashCode` modulo the theme palette (`icon_utils.dart`). The watch does not ship the whole simple-icons set.

**INFERRED design choice** for the fallback, because the spec says "two-character avatar" and "SHA-256" without naming bytes:

- Hash UTF-8 bytes of the issuer string as stored (no case folding).
- Background color is `SHA256[0]`, `SHA256[1]`, `SHA256[2]` as red, green, blue.
- Label is the first two Unicode scalars of the trimmed issuer, ASCII letters uppercased. One scalar is shown once. An empty issuer shows `?`.

**Acceptance:** The same issuer string always yields the same color. `GitHub` and `github` may differ, because the hash input is not lowercased.

### R23 — Haptic at rollover (Phase 2)

Optional `WKHapticType.directionDown` when the code rolls (remaining hits the new period). Default off until the user opts in, so a quiet room is not pulsed every 30 seconds without a choice.

**INFERRED default:** off. The spec says the haptic is optional.

**Acceptance:** With the setting on, one haptic fires at the rollover and not every second. With it off, no haptic fires.

### R24 — Payload schema (Phase 1)

Version 1 JSON in [SYNC-CONTRACT.md](SYNC-CONTRACT.md): `version`, `timestamp`, `syncType`, `tokens[]`, `deletedIds`. Token fields: `id`, `issuer`, `account`, `secret`, `algorithm`, `digits`, `period`, `isFavorite`, `sortOrder`.

Swift model: `WatchToken: Identifiable, Codable, Sendable` with `HashAlgorithm` raw values `SHA1`, `SHA256`, `SHA512`.

**Acceptance:** A golden JSON fixture decodes into `WatchToken` and encodes back with the same field names.

### R25 — Stable ids and deletions (Phase 1)

`id` is `code.generatedID!.toString()`. `generatedID` is the SQLite primary key assigned in `AuthenticatorDB.insert`. `Code.selectionKey` falls back to `rawData` for unsaved codes, and `rawData` contains the secret. Unsaved codes are omitted.

`deletedIds` lists ids that left the eligible set since the last successful payload (trashed, deleted, unpinned and untagged when `syncAll` is false, or skipped under R17 after having been synced).

**Acceptance:** Payload tests cover pin removal, trash, and a code with null `generatedID`. The null id is absent from both arrays. No test fixture's secret appears inside an `id`.

### R26 — Phases (all)

Implement in three pull requests as [PLAN.md](PLAN.md) describes. Phase 1 is the watch target, the bridge, Keychain, CryptoKit, and pinned/`#watch` sync. Phase 2 is the full UI. Phase 3 is complications and the phone settings screen.

**Acceptance:** The Phase 1 diff does not add WidgetKit, a Flutter settings page, or a custom crown HUD.

## Security requirements

R6, R7, R8, R9, R10, R11, and R28. Threat details are in [THREAT-MODEL.md](THREAT-MODEL.md).

### R27 — Scope fence

Phase 1 does not modify `server/`, `web/`, Photos, Locker, or Rust. It does not modify shared packages (`ente_crypto_api`, `ente_lock_screen`, `ente_configuration`, and the other `mobile/packages/*` entries) unless a compile error in the auth app proves a one-line change. It does not rewrite `AuthenticatorService`.

**Acceptance:** `git diff` for the phase stays under `mobile/apps/auth/` plus this `docs/auth-watch/` folder.

### R28 — No secret logs

Do not log OTP secrets, raw otpauth URLs, or live codes. `safeDecode` in `totp_util.dart` already avoids logging the decoded value. Match that.

**Acceptance:** Grep of the phase diff finds no string interpolation of `secret` or the generated code in a log call.

### R29 — Three different stores

Keep these distinct in code and in comments:

| Store | Path | Contents |
| :---- | :---- | :---- |
| Encrypted authenticator DB | `AuthenticatorDB` database name `ente.authenticator.db`, table `entities`, columns `encryptedData` and `header`. Offline twin: `OfflineAuthenticatorDB`. | OTP records. Plaintext exists only after `CryptoUtil.decryptData` in `AuthenticatorService.getEntities`. |
| Phone secure storage | `Configuration._secureStorage` (`flutter_secure_storage` 9.0.0) | `auth_secret_key`, `offline_auth_secret_key`, and base account keys. Not the per-token OTP seed list. |
| Watch Keychain | R6 | Watch copies of eligible seeds. |

The graph edge from "Hardware Keychain Isolation" to `Configuration`'s `FlutterSecureStorage` is a semantic similarity (INFERRED by graphify), not an existing integration.

## Non-requirements

- Implementing Wear OS, or treating Discussion 485 as a watchOS API spec. The verified discussion is a Wear OS feature request.
- Flutter widgets, `WidgetRef`, or Dart UI on the watch.
- A WCSession round trip inside `TimelineView`.
- Syncing HOTP counters. Two devices incrementing one counter will diverge. Phase 1 omits HOTP (R17).
- Applying the phone time offset on the watch (R20).
- An app-level cipher around the JSON in Phase 1. That is a future hardening note in the threat model.
- Editing root `AGENTS.md`, root `CLAUDE.md`, `docs/CLAUDE.md`, or `docs/README.md`.
- Rebuilding the graphify corpus.

## Dart surface for Phase 1

One new pure function and one trigger. Signature (recommendation, not a claim that the file exists):

```dart
WatchSyncPayload buildWatchPayload(
  List<Code> codes, {
  required bool syncAll,
  required Set<String> deletedIds,
  CodeSortKey sortKey = CodeSortKey.issuerName,
});
```

Behavior is R12–R17, R24, and R25. Put it in a new file such as `mobile/apps/auth/lib/services/watch_sync_service.dart`. The trigger subscribes to `CodesUpdatedEvent`, reads codes from `CodeStore`, and invokes `syncTokens`.
