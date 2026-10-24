# Threat model

Assets, adversaries, and what Phase 1 actually does. Requirements R6–R11 and R28 are the controls. Display masking is a UX control; [MATH.md](MATH.md) says so explicitly.

## Assets

| Asset | Where it lives today | Where the watch copy lives |
| :---- | :---- | :---- |
| OTP seed | Encrypted authenticator DB. `AuthenticatorDB` (`ente.authenticator.db`, table `entities`, `encryptedData` + `header`) or `OfflineAuthenticatorDB`. Plaintext appears after `AuthenticatorService.getEntities` decrypts with the auth data key. | Watch Keychain item, service `io.ente.auth.watch`, account = token id, bytes = base32-decoded seed. |
| Auth data key and account keys | `Configuration`'s `FlutterSecureStorage` (`auth_secret_key`, `offline_auth_secret_key`, plus base account keys). iOS accessibility on that store is `KeychainAccessibility.first_unlock_this_device`. | Not copied to the watch. The watch does not hold the vault key. |
| Live 6–8 digit code | Computed in the phone UI (`getOTP`) and, after this project, on the watch. | Shown on the watch UI and, in Phase 3, possibly on a complication. |
| Payload dictionary | Built in memory on the phone, handed to `WCSession`. | The app-level JSON contains `secret` as plaintext base32. |

The graphify edge that links "Hardware Keychain Isolation" to `FlutterSecureStorage` is a semantic similarity. It is not a shared store. Putting OTP seeds into `Configuration._secureStorage` would be a bug. Putting them in the watch Keychain is the design.

## Adversaries

| Adversary | Goal | What holds |
| :---- | :---- | :---- |
| Thief with a locked watch | Read seeds or codes after a snatch | R7 and R8. `WhenUnlockedThisDeviceOnly` plus `.devicePasscode`. Wrist removal locks the watch. Items stay unreadable until the passcode. ThisDeviceOnly items do not migrate onto a different device via backup restore (Apple's wording for that constant). |
| Person who picks up an unlocked watch still on the wrist | Read the current code | They can. The code is meant to be read by the wearer. Ambient redaction (R9) and shielded mode (R10) shrink the window when the arm is down or the list is idle. They do not stop a shoulder look at a raised wrist. |
| Backup extractor | Lift seeds from an unencrypted watch backup or from iCloud Keychain | The spec requires `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` for this reason. Apple's page states the items do not migrate to a new device and are absent after restore onto a different device. |
| Shoulder surfer | Read digits off the face or the always-on display | `.privacySensitive()` in ambient and inactive scenes. Optional shielded mode. Optional haptic does not reveal digits. |
| Malicious or compromised phone app | Push extra seeds or replace seeds | The phone app is the source of truth. A compromised Ente process can already read decrypted codes. The watch trusts the paired phone's `WCSession`. This project does not add an attestation protocol in Phase 1. |
| Lost phone that still syncs | Keep updating a watch the owner no longer has | Unpairing is the user's control. Until the watch is unpaired or erased, a still-signed-in phone can replace the application context. Document that in the Phase 3 settings copy: removing accounts on the phone, or unpairing the watch, is how seeds leave the watch. |
| Shared-device watch | Next person on the same watch reads the previous owner's seeds | ThisDeviceOnly ties items to that watch. Erase the watch when lending it. The app should delete its Keychain items when the payload is an empty eligible set, and when the session is deactivated, so an explicit "sync nothing" clears seeds. |

## Spec controls

1. **Keychain isolation.** No `UserDefaults`, no raw files. Service `io.ente.auth.watch`. Account is the token id.
2. **Passcode.** `SecAccessControlCreateWithFlags(..., kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .devicePasscode, ...)`. Failure shows "Passcode required on Apple Watch to sync tokens" and writes nothing.
3. **Display.** `.privacySensitive()` on codes and rings. Shielded mode is optional and off the security-critical path: it is a preference.
4. **Scrubbing.** `memset_s` in `deinit` of the seed buffer used for HMAC. Swift `String` on `WatchToken.secret` is a poor scrub target; keep the HMAC input in the reference type (R11).

## Residual risks

**Plaintext secret inside the WCSession dictionary.** The spec's sample JSON includes `"secret": "JBSWY3DPEHPK3PXP"`. Real payloads will contain real base32 secrets in that field. Watch Connectivity encrypts the transfer at the transport. The bytes of the dictionary, once delivered to either app, are the secret. Logs, analytics, and crash attachments of the dictionary are a direct leak (R28).

**INFERRED future hardening, not Phase 1:** encrypt the secret field with a key established on the watch before placing it in the dictionary, so a log of the property list is not the seed. Phase 1 does not do this. Do not describe the current JSON as app-level encrypted.

**Complications.** `AccessoryRectangular` in the spec shows issuer, account, and the live code on the watch face. That fights the ambient-masking goal: a face is visible from farther away than an app the user opened. Phase 3 should ship the complication only with the same passcode gate, and reviewers should be able to turn the live digits off. A countdown ring without digits (`AccessoryCircular`, `AccessoryCorner`) leaks timing, not the code.

**Steam and HOTP desync.** Syncing them with the decimal engine would show a code that fails the login, which trains users to distrust the watch and to fall back to insecure workarounds. R17 skips them. HOTP has a second problem: a shared counter that both devices increment. That is why the skip is a requirement and not only a missing feature.

**Shared watch, family setup.** A watch paired to the owner's phone receives seeds. Anyone who knows the watch passcode and is wearing it can read codes. That is the same trust as handing over an unlocked phone.

**Clock skew.** A wrong watch clock emits a neighboring or distant TOTP. It does not leak the seed. It does cause failed logins. Policy is in R20.

**Large payload.** A failed or partial transfer must not be debugged by printing the dictionary.

## Pointer

Keychain accessibility wording and the 31-bit truncation rationale are in [MATH.md](MATH.md). Inclusion rules that keep trashed, Steam, and HOTP seeds off the watch are in [SYNC-CONTRACT.md](SYNC-CONTRACT.md).
