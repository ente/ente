# PRD: Ente Auth on Apple Watch

Companion to [REQUIREMENTS.md](REQUIREMENTS.md) and [PROPOSAL.md](PROPOSAL.md). MVP is Phase 1 in [PLAN.md](PLAN.md).

## Personas

**Wrist unlocker.** They sign in to a laptop or a website several times a day. The phone is nearby and often locked. They want the current six-digit code on the watch, large enough to type, and they want the next code when the current one is about to roll.

**Heavy vault.** They have far more accounts than fit on a watch face. They pin the ones they actually type, or they mark a few with a tag, and they expect the watch to show that short list in the same order as the phone.

**Cautious user.** They set a watch passcode. They expect a stolen, locked watch to keep seeds unreadable, and they expect codes to disappear into placeholders when the wrist drops.

## Stories

1. As a wrist unlocker, I pin GitHub on the phone and, after the next sync, I see that account's current TOTP on the watch while the phone app is not on screen.
2. As a wrist unlocker, when fewer than or equal to 5 seconds remain, I see the next code so I do not start typing a code that is about to expire.
3. As a heavy vault user, I leave "Sync All Accounts" off and the watch receives only pinned accounts and accounts I have tagged `#watch`.
4. As a heavy vault user, I turn "Sync All Accounts" on (Phase 3) and the watch receives every non-trashed TOTP account.
5. As a cautious user, if my watch has no passcode, Ente refuses to store seeds and tells me "Passcode required on Apple Watch to sync tokens".
6. As a cautious user, codes and progress rings become placeholders in ambient mode.
7. As a user who trashes an account, that seed leaves the watch.
8. As a user with a Steam or HOTP entry, Phase 1 does not show a code for it.

## Success metrics

MVP (Phase 1) is successful when all of the following hold on a paired watch:

- A pinned SHA-1, SHA-256, or SHA-512 TOTP account appears on the watch after a sync, with the phone app then suspended.
- For an RFC 6238 vector and for a shared base32 secret at a fixed unix time, the watch code equals the phone code from `otp.OTP.generateTOTPCodeString` in `mobile/apps/auth/lib/utils/totp_util.dart`.
- Steam (`Type.steam`) and HOTP (`Type.hotp`) produce no watch code.
- Trashed accounts produce no watch code.
- A watch with no passcode stores no seed.
- Logs and crash reports contain neither seeds nor live codes.

Later phases add: next-code hint at ≤ 5 seconds, ambient masking, complications, and the full-vault toggle. Phase 3's rectangular complication that shows a live code is a product tension; see [THREAT-MODEL.md](THREAT-MODEL.md). Shipping it is not an MVP metric.

## Out of scope

Wear OS, Photos watch faces, server or web changes, live per-code Bluetooth fetches, Flutter widgets on the watch, and copying `PreferenceService`'s clock offset onto the watch. See [REQUIREMENTS.md](REQUIREMENTS.md) non-requirements.

## Open questions

These are unresolved product choices. Phase 1 can proceed with the recommendation recorded next to each one.

| Question | Why it is open | Phase 1 recommendation |
| :---- | :---- | :---- |
| Tag `#watch` versus a real sync-to-watch flag | Tags are freeform strings on `CodeDisplay.tags`. Graphify marked `#watch` → `TagChipState` AMBIGUOUS. There is no enum value and no reserved tag in source. | **INFERRED.** Treat a tag equal to `#watch` after trim as an inclusion signal. Do not change the `CodeDisplay` schema in Phase 1. An explicit flag can replace the convention later if people use `#watch` for something else. |
| Case of `#watch` | `TagChip` does not normalize tag strings. | **INFERRED.** Match `#watch` exactly, case-sensitive. |
| Steam and HOTP | The spec's CryptoKit engine is decimal TOTP only. The phone also supports both other types. | **Requirement R17.** Skip both in Phase 1. |
| Phone clock offset | `PreferenceService.timeOffsetInMilliSeconds()` shifts phone OTP. The spec uses `Date()` on the watch. | **INFERRED.** The watch uses its system clock. Do not copy the phone offset. See [MATH.md](MATH.md). |
| Rectangular complication showing a live code | The spec asks for issuer, account, and a live code on `AccessoryRectangular`. That is glanceable by anyone who can see the face. | **INFERRED.** Keep the complication behind the same passcode and privacy rules as the app, and treat a masked complication as an acceptable Phase 3 follow-up if shoulder surfing shows up in review. |
| `syncType` string | The spec sample says `DELTA`. A full eligible set is safer with `updateApplicationContext`, which replaces undelivered dictionaries. | **INFERRED.** Keep `"syncType": "DELTA"` and define it as an idempotent full eligible set plus `deletedIds`. See [SYNC-CONTRACT.md](SYNC-CONTRACT.md). |
