# Locked Self-Hosted Ente Photos for Android

**Status:** Living document. Updated at the end of every task.
**Started:** 2026-07-13
**Owner:** vanton
**Planning doc:** n/a
**Companion docs:** `living_docs/LockedSelfHostedIOS.md`, `mobile/apps/photos/README.md`, `docs/docs/self-hosting/installation/post-install/index.md`, `docs/docs/self-hosting/administration/object-storage.md`

---

## 1. Phase / Task tracker

| Phase | Task | Title | Size | Status | Notes |
|------:|----:|-------|:----:|--------|-------|
| 1 | 1.1 | Align the Android toolchain and build an unchanged debug APK | M | 🟢 done | Installed a checksum-verified ARM64 Temurin 17.0.19 JDK and isolated Android SDK outside Git, including API 36, Build Tools 36, Platform Tools 37, pinned NDK 28.2, and transitive compatibility components. Built the unchanged `independentDebug` APK with rustup first on `PATH`; verified package `io.ente.photos.independent.debug`, minimum API 26, target API 36, Android debug signing, ARMv7/ARM64 libraries, and SHA-256 `d34db3323e4c500bfdf44b392c136bbb27ebc156b7a7cc7afa812ec571f544bc`. |
| 1 | 1.2 | Boot an emulator and preflight private Museum and MinIO HTTPS | S | ⚪ not started | Confirm a clean Android emulator can resolve and trust the private Tailscale hostname, reach Museum, and reach the MinIO endpoint used by signed object URLs. |
| 2 | 2.1 | Add the self-hosted flavor and guarded Android build wrapper | M | ⚪ not started | Add a dedicated flavor with application ID `com.vanton1.ente.photos.selfhosted`. Reuse the shared Dart endpoint validator and have the wrapper inject the locked endpoint while rejecting caller overrides. Preserve every official Android flavor. |
| 2 | 2.2 | Test the Android flavor, wrapper, endpoint lock, and APK identity | M | ⚪ not started | Exercise normal and locked Dart tests, wrapper rejection cases, Gradle variant assembly, manifest identity, and artifact inspection without weakening the official builds. |
| 3 | 3.1 | Verify the locked Android build end to end in an emulator | M | ⚪ not started | Register or log in, upload and download encrypted media, force-restart the app, and prove a same-package artifact for a different valid HTTPS origin fails locally without Museum requests. |
| 3 | 3.2 | Sign and verify the locked Android build on a physical device | M | ⚪ not started | Create or reuse a local signing key outside Git, build and audit a release APK, install it on a physical Android device, and repeat the critical account, media, restart, and server-evidence checks. |

**Legend:** ⚪ not started · 🟡 working · 🟢 done · 🔴 blocked / needs decision
**Size:** XS · S · M · L · XL (never days or weeks).

One task is one reviewable step. Mark a row 🟡 working before implementation and 🟢 done after its verification passes. Use `Task <phase>.<sub> — <short imperative title>` for corresponding commits.

---

## 2. Goal

Create a personal Android build of Ente Photos that can coexist with official Ente variants and is permanently bound to the same self-hosted Museum HTTPS origin as the personal iOS build. A successful V1 produces an emulator-tested debug artifact and a locally signed release APK for a physical Android device, supports registration or login plus encrypted photo upload and download, preserves state across forced restarts, cannot be switched to Ente's production API, and fails locally before authenticated networking when its endpoint configuration or stored endpoint identity is unsafe. Normal Android flavors must retain their current behavior.

---

## 3. Architecture / approach

The Android application shares its Dart startup, endpoint configuration, network interceptor, and tests with the completed iOS implementation. The locked Android artifact will reuse that policy rather than add a second endpoint implementation:

- Compile with `lockedEndpoint=true` and one canonical HTTPS `endpoint` value.
- Reject Ente's production Museum origins, invalid endpoint syntax, pre-existing endpoint overrides, incompatible account state, and endpoint-binding mismatches before authenticated networking starts.
- Keep authenticated Museum requests on the compiled origin and reject redirects. Continue allowing Museum-provided signed object-storage URLs through the separate upload and download clients.
- Preserve the endpoint identity across logout and require a manual app-data clear or reinstall after an unsafe mismatch instead of silently deleting local state.

Android packaging will add one `selfhosted` product flavor to the existing application module. Its application ID will be `com.vanton1.ente.photos.selfhosted`, while the existing `io.ente.photos` Kotlin namespace and native source tree remain shared. The unique application ID lets the personal build coexist with official, independent, development, and F-Droid variants. Existing variants, signing configuration, manifests, and output naming remain unchanged unless a narrowly required shared fix is proven by the baseline.

A guarded Android wrapper will be the supported build path. It will validate `ENTE_SELF_HOSTED_ENDPOINT` with the existing Dart command-line validator, select only the `selfhosted` flavor, inject the locked endpoint defines, and reject caller arguments that could replace the flavor or Dart defines. Debug builds may use Android's standard debug signature. Release builds will use the existing Gradle signing inputs with a local keystore whose path and credentials stay outside Git.

The Android emulator and physical device will use the existing private deployment:

```text
Android wrapper -> validate HTTPS origin -> build selfhosted APK
       |
       v
app startup -> validate compiled policy and stored binding
       | invalid                          | valid
       v                                  v
local diagnostic, no Museum traffic   local Museum -> signed MinIO URLs
```

V1 locks authenticated Museum traffic only, matching the iOS security boundary. Existing ancillary networking remains allowed. Startup diagnostics, `adb logcat`, artifact inspection, and Museum logs provide the verification evidence. The unique package makes rollback reversible by uninstalling only the self-hosted app. There is no data migration, compliance change, or new performance target beyond parity with the normal Photos app.

---

## 4. Future work / out-of-scope

> Single source of truth for everything that is NOT in V1. Items move into V1 only with explicit approval and a decision-log entry.

| Item | Status | Why |
|------|--------|-----|
| Background photo backup, widgets, and notification behavior as explicit self-hosted acceptance tests | V1.1 backlog | Thorough V1 proves the core account and foreground media workflow first; these Android integrations add permissions and lifecycle cases. |
| Remove or self-host Google and Ente ancillary services | V1.1 backlog | V1 intentionally matches the iOS Museum-only isolation boundary. |
| Reusable self-hosted Android packaging for all contributors | Out of scope | This initiative targets one personal application identity and one server origin. |
| Strict network-wide hostname allowlisting | Out of scope | It would likely break maps, legal links, model downloads, and other non-Museum features outside the requested data-server boundary. |
| Runtime server switching in the locked artifact | Out of scope | Changing servers requires rebuilding and clearing or reinstalling the unique application package. |
| Google Play, F-Droid, or other store distribution | Out of scope | V1 installs a locally signed APK directly on the owner's device. |
| Separate Android architecture companion document | Out of scope | The settled endpoint design lives in the iOS document; this document records the Android packaging and verification delta. |

**Status values:**
- `V1.1 backlog` — deferred but planned for the next milestone.
- `Out of scope` — will not be done in this initiative; distinct from deferred work.

---

## 5. Decision log

> Append-only. Newest entries stay on top. If a decision changes, add a new entry instead of rewriting history.

### 2026-07-13 — Install an isolated Android toolchain outside Git

**Decision:** Keep the Android JDK and SDK under `/Users/vanton/projects/ente-android-toolchain`, reference the SDK through ignored local Gradle properties and command environment, and put the existing rustup shims before the broken Homebrew Rust installation during builds.

**Why:** The Mac had no Android SDK or JDK 17, while its Intel Homebrew Java 24 and Rust 1.84 installations do not match the project and the Rust installation aborts against its current LLVM. Checksum-verified isolated tools preserve unrelated system and repository configuration while producing the unchanged Android baseline.

**Alternatives considered:** Install Android Studio and global toolchains, reuse the incompatible system Java and Rust installations, or change project build versions to accommodate the machine.

### 2026-07-13 — Reuse the iOS endpoint and server design references

**Decision:** Keep Android-specific planning in this document and link the completed iOS living document, Photos build instructions, and server object-storage documentation. Do not duplicate the endpoint architecture or create another architecture companion.

**Why:** Android reuses the same Dart policy and private server. Recording only the packaging and platform-verification delta reduces documentation drift.

**Alternatives considered:** Duplicate the complete design here, or add a new cross-platform architecture companion.

### 2026-07-13 — Match the iOS Museum-only security boundary

**Decision:** Lock authenticated Museum requests and retain existing ancillary networking in Android V1. Fail unsafe startup locally and use the diagnostic screen, `adb logcat`, and Museum logs for evidence.

**Why:** The user chose parity with the proven iOS boundary rather than broadening Android into an ancillary-service or network-allowlist project.

**Alternatives considered:** Disable Ente-operated ancillary services, or enforce a strict allowlist for Museum and signed MinIO URLs.

### 2026-07-13 — Sequence Android work risk first

**Decision:** Prove the pinned Android toolchain and unchanged application build, then preflight networking, add packaging, verify the emulator, and finish on a signed physical device.

**Why:** JDK and Android SDK alignment are current unknowns. Establishing the baseline keeps environment and dependency failures separate from self-hosted flavor changes.

**Alternatives considered:** Implement an end-to-end vertical slice immediately, or configure the physical device and release signing before emulator work.

### 2026-07-13 — Add a dedicated self-hosted Android flavor

**Decision:** Extend the existing Android application module with a `selfhosted` flavor, a separate application ID, and a guarded wrapper that reuses the shared Dart endpoint validator.

**Why:** A dedicated flavor preserves native integration reuse, keeps official variants unchanged, and produces an unmistakable package that can coexist with them.

**Alternatives considered:** Reuse the `independent` flavor and risk identity confusion, or create a separate Android application module and duplicate native configuration.

### 2026-07-13 — Prove a thorough personal Android V1

**Decision:** Test a separate package on both an emulator and a physical Android device, including local release signing, account and media flows, restart persistence, and endpoint-mismatch rejection.

**Why:** A debug emulator build alone cannot prove release signing, device networking, or installation behavior, while the broader Android integration suite is not required for the requested core workflow.

**Alternatives considered:** Stop at a debug emulator MVP, or include background backup, widgets, notifications, and ancillary-service removal in V1.

### 2026-07-13 — Build a personal locked Android companion

**Decision:** Produce a personal Android application that is permanently bound to the same local server as the locked iOS application.

**Why:** The requested Android app should communicate with the local server without being confused with or switched to the official Ente service.

**Alternatives considered:** Keep endpoint switching in a developer build, or create a generic upstream-facing self-hosted flavor for all users.

---

## 6. Open questions

- Which physical Android device will be used for Task 3.2?
- Where should the local Android release-signing keystore be stored and backed up outside Git?

---

## 7. Lessons learned

> Populated at the end of each phase. Record surprises, anti-patterns, and improvements for the next phase.

_Empty until Phase 1 completes._
