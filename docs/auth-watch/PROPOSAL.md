# Proposal: native Apple Watch companion for Ente Auth

**Status:** proposal. Nothing in this document is implemented in the repository.

The architectural spec this proposal follows is the file `building the app for ente feels like a good idea....md` at the repository root. Community context is GitHub Discussion 485, which `gh` confirms was converted from Issue 143. Both are titled **[Feature Request] Wear OS Support**. The discussion body is a single line: "Wear OS Instant Preview of Codes from Wrist only." That thread asks for codes on a wrist, on Wear OS. This proposal answers the same job for Apple Watch with a native watchOS app. It does not implement Wear OS.

## Problem

People keep 30 to 100 authenticator entries in Ente Auth. A 41 mm or 45 mm watch cannot scroll that list comfortably. Asking the watch to fetch a live code from the iPhone over Bluetooth each time the screen wakes adds latency and fails when the phone is asleep, out of range, or the session drops. The person who needs a code is often already at a laptop, with the watch on their wrist and the phone in a pocket.

## Proposal

Ente Auth on iPhone stays a Flutter app. The watch becomes a separate Swift and SwiftUI target and an autonomous cryptographic node. When accounts change, the phone pushes a small payload of eligible seeds. The watch stores those seeds in its Keychain and generates RFC 6238 codes on its own clock. Raising the wrist shows a code with no round trip to the phone.

The payload's app-level JSON contains the base32 secret as a string. Apple's Watch Connectivity transport carries the dictionary. The watch Keychain is the at-rest store. See [THREAT-MODEL.md](THREAT-MODEL.md) and [SYNC-CONTRACT.md](SYNC-CONTRACT.md).

## What ships, in three phases

| Phase | User-visible result |
| :---- | :---- |
| 1 | Paired watch receives pinned accounts (and accounts tagged `#watch`) and can compute TOTP offline. Steam and HOTP are skipped. |
| 2 | A list UI: Digital Crown scroll, always-on masking, next-code hint in the last 5 seconds, issuer marks, tap-to-reveal. |
| 3 | WidgetKit complications and a Watch section in the iPhone settings, including "Sync All Accounts". |

Phase boundaries and file paths are in [PLAN.md](PLAN.md). Requirements are in [REQUIREMENTS.md](REQUIREMENTS.md).

## Non-goals

- A Flutter UI on watchOS. The watch target is Swift and cannot import Flutter widgets.
- A Bluetooth fetch on every code display.
- Changes to Ente Photos, Locker, the web app, the server, or the Rust libraries.
- A Wear OS app. Discussion 485 is the demand signal; the implementation target is watchOS.
- Rewriting `AuthenticatorService` or the encrypted vault format.
- Syncing HOTP or Steam Guard in Phase 1. Those algorithms differ from decimal TOTP. Emitting a decimal code for them would be wrong. See [MATH.md](MATH.md).
