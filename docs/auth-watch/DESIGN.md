# Design

Phone analogues are EXTRACTED. Watch visuals that are not in the tree yet are from the spec, with design choices marked **INFERRED**.

## Phone analogue

`CodeWidget` (`mobile/apps/auth/lib/ui/code_widget.dart`) is the phone card:

- Current code from `getOTP`, refreshed on a half-second timer.
- For `Type.isTOTPCompatible` (`totp` and `steam`), the next code from `getNextTotp` is visible for the whole period, under the localized "next" label. Six-digit codes render as `123 456` (`_getFormattedCode`).
- HOTP does not show a second number. It shows a forward icon (`Icons.forward_outlined`) that advances the counter.
- `PreferenceService.shouldHideCodes()` masks every non-whitespace character as `•`.
- `CodeTimerProgress` draws a bar for the fraction of the period remaining, using `timeOffsetInMilliseconds`.
- A pinned mark is drawn when `code.isPinned` and the sort key is not manual (`ignorePin` when `sortKey == CodeSortKey.manual`).
- Issuer art comes from `IconUtils.getIcon`: custom icon, then simple-icons SVG, then a one-letter `CircleAvatar`.

The watch list should feel like a short version of that card, with the spec's differences below.

## Watch states

| State | What the person sees | Phase |
| :---- | :---- | :---- |
| List | One row per eligible token, in `sortOrder`. Issuer, account, current code, period ring. | 2 for the full layout. Phase 1 may be a plain list that proves codes match. |
| Empty | No eligible tokens. Short explanation that pinned accounts and `#watch` tags sync from the iPhone. | 2 |
| Passcode required | The spec string "Passcode required on Apple Watch to sync tokens". No codes. | 1 |
| Locked / wrist off | No digits. Keychain is unreadable (R8). | 1 |
| Shielded | Rows stay masked until tapped. Optional. | 2 |
| Ambient / inactive | `.privacySensitive()` replaces codes and rings with placeholders. | 2 |
| Last 5 seconds | The next code fades in: `Next: 839 201` for a six-digit example from the spec. Ring uses the spec's warning color when `remaining <= 5`. | 2 |
| Rollover | Code and ring restart. Optional haptic if the person turned it on (R23). | 2 |

`TokenRowView` uses `TimelineView(.periodic(from: .now, by: 1.0))` and calls `TOTPCalculator.generateCode` with `timeline.date`. That is the spec's update mechanism. Do not add a `Timer` that messages the phone.

## Interaction

- **Digital Crown.** Phase 2. A SwiftUI `List` on watchOS scrolls with the crown. Phase 1 does not need a custom crown HUD.
- **Tap to reveal.** Phase 2, only when shielded mode is on. Tap affects that row.
- **Tap a complication.** `AccessoryCircular` opens the app to the token with the lowest `sortOrder` (the top of the list). Phase 3.
- **Haptic.** `WKHapticType.directionDown` at the rollover, optional, default off (R23).

## Visual rules

- Codes use a monospaced face. Group six digits as three and three, matching the phone formatter and the spec example.
- The ring is a circular trim of `remaining / period`, starting at the top (−90 degrees in the spec snippet).
- Issuer logos for the six brands in the spec are monochrome or tinted vectors cached on the watch. Prefer copying those few SVGs from the phone's vendored `assets/simple-icons/` (the phone already loads `assets/simple-icons/_data/simple-icons.json`). Do not copy the entire icon set onto the watch.
- Fallback avatar: two characters and a color from SHA-256 of the issuer. Byte layout is a design choice in R22. It is intentionally different from the phone's one-letter `hashCode` palette.

## Complications (Phase 3)

| Family | Content |
| :---- | :---- |
| Accessory circular | Countdown ring for the top token's period. |
| Accessory rectangular | Issuer, account, live code for the top token. This is readable at a glance. [THREAT-MODEL.md](THREAT-MODEL.md) treats that as a shoulder-surfing exposure. |
| Accessory corner | App icon plus a progress arc. |

Timeline entries cover the current period and the next one so the face updates at the rollover without waking the phone.

## Phone settings

Phase 3 adds a Watch section on the iPhone, in the existing settings area (the general settings page already hosts `shouldHideCodes`). Contents:

- **Sync All Accounts.** Off by default. Off means R12 (pinned or `#watch`). On means every non-trashed TOTP.
- Short help text: pin an account, or add the tag `#watch`, to put it on the watch. The tag is typed like any other tag in the existing tag chip UI. There is no special chip in the app today.

Phase 1 does not add this screen. The payload function still accepts `syncAll` so tests can cover both modes. The call site passes `false`.

Shielded mode and the haptic toggle are watch-local settings in Phase 2. They are display preferences, not secrets, and they are not a reason to wake the phone.

## Tag convention

**INFERRED.** A tag string `#watch` means "include this account on the watch even when it is not pinned." `TagChip` only selects or unselects whatever string the person typed. The graphify link from `#watch` to `TagChipState` is ambiguous and is not an implementation.

An explicit boolean on `CodeDisplay` would be a schema change synced inside the encrypted vault, which is more than Phase 1. The tag convention avoids that. If real users already use `#watch` for another purpose, a later phase can add a dedicated flag and stop reading the tag.
