# Claude — Ente Auth watchOS companion

Use this file only for the native watchOS companion documented in this directory. The companion is the Swift target under `mobile/apps/auth/ios/EnteAuthWatch`, with the phone bridge in `EnteWatchBridgePlugin.swift` and `watch_sync_service.dart`. Isolating the instructions here keeps them out of the monorepo agent entry points. Do not modify `/Volumes/MacExt/ente/docs/CLAUDE.md`, `/Volumes/MacExt/ente/docs/README.md`, or a repository-root `CLAUDE.md` / `AGENTS.md` while doing this work.

## Start

1. Read [REQUIREMENTS.md](REQUIREMENTS.md) and [PLAN.md](PLAN.md).
2. Read [SYNC-CONTRACT.md](SYNC-CONTRACT.md) before writing the payload or the method channel.
3. Read [MATH.md](MATH.md) before writing `TOTPCalculator`.
4. Read [THREAT-MODEL.md](THREAT-MODEL.md) before writing Keychain code.
5. Read [INTEGRATION.md](INTEGRATION.md) before running `gh` or creating a branch.

[AGENTS.md](AGENTS.md) is the same constraint list. [SKILL.md](SKILL.md) is the procedure.

## Hard limits for Phase 1

The watch is Swift. Flutter stays on the phone. The only Dart additions are a pure function `buildWatchPayload` and a sync trigger on `CodesUpdatedEvent`.

Skip Steam and HOTP. Skipping means those codes are absent from `tokens`, not that a SHA-1 TOTP is shown in their place.

`AppDelegate.swift` is currently a stock `FlutterAppDelegate` with `GeneratedPluginRegistrant` and `app_links`. Add the watch channel without removing that behavior.

`SUPPORTED_PLATFORMS` in `Runner.xcodeproj` is iPhone only. A watchOS target is new work.

Seeds on the phone live in the encrypted authenticator database. `FlutterSecureStorage` inside `configuration.dart` holds account key material. The watch Keychain is a third store. Do not merge them.

Do not log secrets or live codes. Do not commit unless the user asks. Do not clone a second copy of ente over `/Volumes/MacExt/ente`.

## Tests to run

```bash
cd mobile/apps/auth
flutter test test/services/watch_sync_payload_test.dart
flutter test
```

Plus the Swift RFC vectors in [PLAN.md](PLAN.md).
