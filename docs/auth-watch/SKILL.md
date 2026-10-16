---
name: ente-auth-watch
description: Implement or review the native watchOS companion for Ente Auth using the docs in docs/auth-watch. Use when adding the watch target, the Watch Connectivity bridge, the TOTP engine, or the payload mapper. Do not use for Photos, Wear OS, or server work.
---

# Ente Auth watch companion

## When to use

Use this procedure when the task is implementing or reviewing the Apple Watch companion for Ente Auth (`mobile/apps/auth` in the ente monorepo). The design lives in this folder so it does not become the monorepo's agent instructions. The Phase 1 app is `mobile/apps/auth/ios/EnteAuthWatch`.

Do not use it for Ente Photos, Locker, the web app, the server, or a Wear OS client. Discussion 485 is a Wear OS request; the implementation target of this skill is watchOS, specified locally.

## Inputs

- The phase to build (1, 2, or 3). Default to Phase 1.
- A checkout of https://github.com/ente/ente. The known worktree is `/Volumes/MacExt/ente`. Do not re-clone over it.
- This folder: [REQUIREMENTS.md](REQUIREMENTS.md), [SYNC-CONTRACT.md](SYNC-CONTRACT.md), [MATH.md](MATH.md), [THREAT-MODEL.md](THREAT-MODEL.md), [PLAN.md](PLAN.md), [INTEGRATION.md](INTEGRATION.md).

## Steps

1. Read [PLAN.md](PLAN.md) and limit the diff to that phase's file list.
2. Read the phone symbols the mapper touches: `Code.isPinned`, `CodeDisplay.tags`, `CodeDisplay.trashed`, `CodeDisplay.position`, `Code.generatedID`, `Type`, `getSanitizedSecret`, `HomePage.sortFilteredCodes`, `CodesUpdatedEvent`.
3. Add `buildWatchPayload` and tests before adding Swift. The tests encode the filter: pinned or `#watch`, drop trash, drop Steam, drop HOTP, stable id from `generatedID`.
4. Add `EnteWatchBridgePlugin` on the iOS runner. Channel `io.ente.auth/watch`, method `syncTokens`. Forward the map with `WCSession.updateApplicationContext`.
5. On the watch target, store seeds in the Keychain (`io.ente.auth.watch`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `.devicePasscode`) and compute TOTP with CryptoKit.
6. Prove the engine against RFC 4226 count 0 (`755224`) and RFC 6238 time 59 for SHA-1, SHA-256, and SHA-512. Use an integer modulus.
7. Run `flutter test` in `mobile/apps/auth`. Run the Swift tests on the watch target. Use the manual checklist in [PLAN.md](PLAN.md) when a paired watch is available.

## Verification

- Payload tests fail if a Steam or HOTP secret is copied into `tokens`.
- A suspended phone does not prevent a previously synced watch from rolling codes.
- Logs from the new code contain no `secret` values and no generated digits.
- `git diff` stays inside `mobile/apps/auth/` and `docs/auth-watch/`.

## Out of scope reminders

No Flutter UI on the watch. No per-display Bluetooth fetch. No edits to shared `mobile/packages` unless the auth app fails to compile without a proven one-line fix. No server, web, photos, locker, or Rust edits. No commit, push, or pull request unless the user asks.

## Links

- Index: [README.md](README.md)
- Agent constraints: [AGENTS.md](AGENTS.md) and [CLAUDE.md](CLAUDE.md)
- Verified URLs: [REFERENCES.md](REFERENCES.md)
