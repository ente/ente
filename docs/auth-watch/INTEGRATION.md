# Integration

How a coding agent lands the watch companion in the existing checkout. Do not clone over `/Volumes/MacExt/ente`. Do not commit or open a pull request unless the user asks.

## This workspace

| Fact | Value |
| :---- | :---- |
| Checkout | `/Volumes/MacExt/ente` |
| `git remote -v` | `origin https://github.com/ente-io/ente.git` (fetch and push) |
| Canonical repo from `gh repo view ente-io/ente` | name `ente`, URL `https://github.com/ente/ente`, description "💚 End-to-end encrypted cloud for everything.", default branch `main` |
| Auth location | `mobile/apps/auth` inside that monorepo. Package name `ente_auth`, version `4.4.27+1007`. There is no separate `ente-io/auth` repository. |

`gh repo view ente-io/ente` succeeds and returns the `ente/ente` URL. The organization rename means `gh repo list ente-io` is empty and `gh search issues --repo ente-io/ente` fails with "resources do not exist". Search with `--repo ente/ente`.

`gh repo list ente` includes other repositories (`photos-desktop`, `nightly`, `ffmpeg-packaging`, and more). Those are not the Auth app. Watch work does not clone them.

## Where the code goes

| Piece | Path |
| :---- | :---- |
| Flutter payload and trigger | `mobile/apps/auth/lib/services/watch_sync_service.dart` (proposed) |
| Tests | `mobile/apps/auth/test/services/watch_sync_payload_test.dart` (proposed) |
| iOS channel | `mobile/apps/auth/ios/Runner/EnteWatchBridgePlugin.swift` (proposed), registered from `AppDelegate.swift` |
| Xcode | `mobile/apps/auth/ios/Runner.xcodeproj`: add a watchOS app target, embed it in the Runner iOS app, set the watch deployment target to the current Xcode default |
| Watch sources | `mobile/apps/auth/ios/EnteAuthWatch/` (proposed) |

Suggested bundle identifier, **INFERRED** from `Configuration`'s `clientPackageName` `io.ente.auth`: `io.ente.auth.watch`. The Keychain service string is already specified as `io.ente.auth.watch`.

### Method channel

Pattern to copy: `WindowsWindowPlacement` in `mobile/apps/auth/lib/services/windows_window_placement.dart`.

```dart
static const _channel = MethodChannel('io.ente.auth/window_geometry');
```

Watch channel, **INFERRED** name in the same style:

```dart
static const watchChannel = MethodChannel('io.ente.auth/watch');
```

| Method | Direction | Role |
| :---- | :---- | :---- |
| `syncTokens` | Phone Dart → iOS runner | One argument: the version-1 map from [SYNC-CONTRACT.md](SYNC-CONTRACT.md). |
| `WCSession.updateApplicationContext` | iOS runner → watch | The same dictionary. Not a Dart call. |
| per-tick OTP | none | The watch computes codes locally. |

`AppDelegate.swift` today registers plugins and handles `app_links`. Add the channel there or from the plugin's `register(with:)`. Leave the app-links block in place.

## Xcode

1. Open `mobile/apps/auth/ios/Runner.xcworkspace` (the Flutter iOS workspace), not a new project.
2. Add a watchOS App target to `Runner.xcodeproj`.
3. Embed that watch app in the Runner iOS target.
4. Use Xcode's default current watchOS deployment target. This doc set does not pin a watchOS version.
5. The iOS target's current settings, EXTRACTED from `project.pbxproj`, stay `SUPPORTED_PLATFORMS = "iphonesimulator iphoneos"` and `IPHONEOS_DEPLOYMENT_TARGET = 15.0` until Xcode itself adds the watch platform beside them. Do not delete the iPhone platforms.

The watch target links SwiftUI, WatchConnectivity, CryptoKit, and Security. It does not link Flutter.

## Commands

`gh` is already authenticated in this environment as a GitHub user with repo scope. Re-check before pushing:

```bash
gh auth status
git remote -v
git fetch origin
```

Inspect the community thread and the repo without cloning again:

```bash
gh repo view ente-io/ente --json name,url,description,defaultBranchRef
gh api graphql -f query='query { repository(owner:"ente-io", name:"ente") { discussion(number:485) { title url number } } }'
gh issue view 143 --repo ente-io/ente --json number,title,url,state
```

A fresh clone, only when the worktree is not already `/Volumes/MacExt/ente`:

```bash
gh repo clone ente-io/ente
```

Do not run that clone inside `/Volumes/MacExt/ente` or over it.

Start a branch from current `main` (documentation only; do not run as part of writing these docs):

```bash
git fetch origin
git switch -c auth-watch-phase-1 origin/main
```

Open a pull request when the user asks (documentation only here):

```bash
git push -u origin HEAD
gh pr create --repo ente/ente --title "auth: watchOS companion phase 1" --body "$(cat <<'EOF'
## Summary
- Add a watchOS target and a Watch Connectivity bridge for pinned TOTP accounts.

## Test plan
- [ ] Payload filter tests
- [ ] RFC 6238 vectors on the watch target
- [ ] Manual pairing checklist in docs/auth-watch/PLAN.md

EOF
)"
```

Use `--repo ente/ente` because that is the canonical URL `gh repo view` returned. The local remote may still say `ente-io/ente.git`; that remote works for fetch and push.

## Keeping a branch current

```bash
gh auth status
git remote -v
git fetch origin
git rebase origin/main
```

Prefer a merge if the branch has already been pushed and someone else is using it. Do not force-push `main`.

## Packages the phone already uses

| Package | Pin in `mobile/apps/auth/pubspec.yaml` | Repository `gh repo view` returned |
| :---- | :---- | :---- |
| `otp` | 3.2.0 | `https://github.com/daegalus/dart-otp` — "RFC6238 Time-Based One-Time Password / Google Authenticator Library" |
| `steam_totp` | 0.0.2 | `https://github.com/elliotwutingfeng/steam_totp` — "A Dart library for generating 5-character alphanumeric Steam TOTP codes." |
| simple-icons | Not a pub dependency. Vendored assets declared as `assets/simple-icons/icons/` and `assets/simple-icons/_data/`. `IconUtils` loads `assets/simple-icons/_data/simple-icons.json`. | `https://github.com/simple-icons/simple-icons` — "SVG icons for popular brands" |

Phase 1 does not bump `otp` or `steam_totp`. The watch TOTP engine uses CryptoKit, not the Dart package. Steam stays on the phone.

## Discussion the spec cites

Verified with `gh api graphql` on 2026-10-10:

- Discussion 485 title: **[Feature Request] Wear OS Support**
- URL: `https://github.com/ente/ente/discussions/485`
- Body: "Wear OS Instant Preview of Codes from Wrist only"
- Label on the converted issue: `auth`

Issue 143 is the same request. `gh issue view 143 --repo ente-io/ente` returns state CLOSED, the same title, URL `https://github.com/ente/ente/issues/143`. A GraphQL `ConvertedToDiscussionEvent` on issue 143 (2024-03-01) points at discussion number 485 with that title and URL. The spec's sentence "Discussion #485 (originally Issue #143)" matches that event.

The thread is Wear OS, not a watchOS design. `gh search issues --repo ente/ente watch` returns Photos "watched folder" issues. `gh search issues --repo ente/ente watchOS` returns issue 143 and a separate closed photos item. There is no second Auth issue that specifies Apple Watch APIs. The watchOS architecture in this folder comes from the local spec file, not from a GitHub issue body.
