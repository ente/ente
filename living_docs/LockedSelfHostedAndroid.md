# Locked Self-Hosted Ente Photos for Android

**Status:** Living document. Updated at the end of every task.
**Started:** 2026-07-13
**Owner:** vanton
**Planning doc:** n/a
**Companion docs:** `living_docs/LockedSelfHostedIOS.md`, `mobile/apps/photos/README.md`, `docs/docs/self-hosting/installation/post-install/index.md`, `docs/docs/self-hosting/administration/object-storage.md`

> **Historical baseline:** This locked-build milestone remains an append-only
> record of the artifacts verified on 2026-07-13. It was superseded on
> 2026-07-14 by `living_docs/ConfigurableSelfHostedMobileServer.md`, which keeps
> the same package identities and supports guarded runtime server changes.

---

## 1. Phase / Task tracker

| Phase | Task | Title | Size | Status | Notes |
|------:|----:|-------|:----:|--------|-------|
| 1 | 1.1 | Align the Android toolchain and build an unchanged debug APK | M | 🟢 done | Installed a checksum-verified ARM64 Temurin 17.0.19 JDK and isolated Android SDK outside Git, including API 36, Build Tools 36, Platform Tools 37, pinned NDK 28.2, and transitive compatibility components. Built the unchanged `independentDebug` APK with rustup first on `PATH`; verified package `io.ente.photos.independent.debug`, minimum API 26, target API 36, Android debug signing, ARMv7/ARM64 libraries, and SHA-256 `d34db3323e4c500bfdf44b392c136bbb27ebc156b7a7cc7afa812ec571f544bc`. |
| 1 | 1.2 | Boot an emulator and preflight private Museum and MinIO HTTPS | S | 🟢 done | Created and clean-booted the isolated `ente_api36_arm64` Pixel 7 AVD with Android 16/API 36 and Google APIs ARM64. From inside Android, resolved `macbook-pro-2.tailcfdac8.ts.net` to private address `100.100.190.42`; Android's trust store completed HTTPS to Museum `/ping` and MinIO `/minio/health/live`, both with HTTP 200 and TLS 1.3 `TLS_AES_128_GCM_SHA256`. Removed the temporary diagnostic and shut the emulator down cleanly while preserving the AVD. |
| 2 | 2.1 | Add the self-hosted flavor and guarded Android build wrapper | M | 🟢 done | Added the `selfhosted` flavor with release application ID `com.vanton1.ente.photos.selfhosted`, the normal `.debug` suffix for debug builds, a no-referrer fallback for the flavor-aware install-source plugin, and the standard launcher manifest overlay. Added a guarded APK wrapper that reuses the Dart endpoint validator, injects only `lockedEndpoint=true` plus the canonical endpoint, and rejects caller flavor or Dart-define overrides. Gradle exposed self-hosted debug/profile/release tasks alongside every existing flavor, generated both expected application IDs, and left the official flavor blocks unchanged. |
| 2 | 2.2 | Test the Android flavor, wrapper, endpoint lock, and APK identity | M | 🟢 done | Passed all 20 endpoint-policy and developer-settings tests in both normal and real locked-define modes. Verified one canonical wrapper invocation and nine fail-closed cases covering missing or unsafe endpoints, validation arity, Dart-define forms, and flavor overrides. Built and audited the 554,898,085-byte `selfhostedDebug` APK: package `com.vanton1.ente.photos.selfhosted.debug`, minimum API 26, target API 36, Android Debug signature, ARMv7/ARM64/x86_64 libraries, intact ZIP, canonical local hostname and lock policy in the Flutter kernel, correct launcher merge, and SHA-256 `1bf6391069960ef39c6bf15b8809480778bc13aa9cd8b4b321318e5e777a14cb`. Rebuilt `independentDebug` and confirmed its original package, SDK range, ABIs, and signer; SHA-256 `8d6247d670940d2ee91f31f90d37c7eea6e0d98f25fd916f3257fcf94ae97658`. |
| 3 | 3.1 | Verify the locked Android build end to end in an emulator | M | 🟢 done | Installed the checksum-audited local-server APK on the API 36 ARM64 emulator and verified the initial server identity, account recovery/login, and persisted authentication across both an app cold start and a full emulator restart. Uploaded a controlled image; Museum recorded the self-hosted debug package creating its collection, obtaining signed object URLs, and committing encrypted file metadata with HTTP 200. After the source disappeared from Android shared storage, a cold-started app requested `/files/download/10000005`, received the signed-object redirect, and rendered the decrypted full image. An in-place same-package build for `https://other.example` stopped on the local endpoint-binding diagnostic before creating a network client; Museum recorded zero package requests after launch. Reinstalling the preserved local-server APK retained the session and returned to home. Restored the canonical 554,898,085-byte output with SHA-256 `1bf6391069960ef39c6bf15b8809480778bc13aa9cd8b4b321318e5e777a14cb`, then shut down the preserved AVD. |
| 3 | 3.2 | Sign and verify the locked Android build on a physical device | M | 🔴 blocked / needs device | Created an external RSA-4096 release keystore with its generated password held in the macOS login Keychain and only the ignored keystore path/alias in local Gradle properties. Built and audited the 262,701,461-byte release APK: package `com.vanton1.ente.photos.selfhosted`, version `1.3.59`, minimum API 26, target API 36, ARMv7/ARM64 libraries, intact ZIP, canonical local endpoint in the AOT library, valid APK Signature Scheme v2 signature with certificate SHA-256 `9f0a5f39668e7098d097745931bcb8fc392d50da877cf349a2b20e2db1a4ce69`, and artifact SHA-256 `2f5f6011035e396f7b1d3660fe7043fc509115554dcca2051e3fe5a868461fc8`. Preserved the exact APK at `/Users/vanton/projects/ente-android-toolchain/artifacts/ente-photos-selfhosted-1.3.59-release.apk`. Physical installation and the account, media, restart, and server-evidence checks remain blocked until a device is available. |

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

Android packaging adds one `selfhosted` product flavor to the existing application module. Its release application ID is `com.vanton1.ente.photos.selfhosted`, while debug builds receive the existing build type's `.debug` suffix and the `io.ente.photos` Kotlin namespace and native source tree remain shared. The flavor uses the install-source plugin's `independent` fallback so personal builds retain the plugin's no-referrer behavior without changing its official variants. The unique application ID lets the personal build coexist with official, independent, development, and F-Droid variants. Existing variants, signing configuration, manifests, and output naming remain unchanged unless a narrowly required shared fix is proven by the baseline.

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

### 2026-07-14 — Supersede the locked artifacts with in-place configurable builds

**Decision:** Preserve this document as the verified locked baseline and move
subsequent Android packaging and endpoint-switch work to
`living_docs/ConfigurableSelfHostedMobileServer.md`. Keep release package
`com.vanton1.ente.photos.selfhosted` and its normal debug suffix so configurable
artifacts can upgrade their corresponding locked installations in place.

**Why:** The new guarded flow reuses the locked binding to preserve the current
server and account while allowing an explicitly validated later switch.
Rewriting this document's completed goal or evidence would erase the conditions
under which the earlier artifacts were verified.

**Alternatives considered:** Rewrite the locked milestone as if it had always
been configurable, or create second package identities and duplicate local
state.

### 2026-07-13 — Regenerate release-only Android plugins before packaging

**Decision:** Run the final locked release build with Flutter's normal dependency and platform preparation instead of passing `--no-pub` against previously generated debug state.

**Why:** A cold release attempt with `--no-pub` reused an ignored debug `GeneratedPluginRegistrant.java` that referenced `flutter_native_splash` and `integration_test`, while Flutter correctly excluded those development-only plugins from the release classpath. Normal release preparation regenerated the registrant without those entries and produced the signed APK from the cached native outputs.

**Alternatives considered:** Promote development-only plugins into the release runtime, manually edit or delete the ignored generated Java file, or teach the self-hosted wrapper to rewrite Flutter-generated plugin code.

### 2026-07-13 — Keep Android signing secrets in the login Keychain

**Decision:** Store the personal release keystore under `/Users/vanton/projects/ente-android-toolchain/signing`, keep its generated password in the macOS login Keychain service `ente-photos-selfhosted-release`, and place only the absolute keystore path and alias in ignored `android/key.properties`.

**Why:** Gradle already supports combining local properties with `SIGNING_*` environment variables. Retrieving the password from Keychain only for the build avoids committing it or keeping it in a plaintext properties file while preserving a reusable local signing identity.

**Alternatives considered:** Put the password directly in ignored `key.properties`, type credentials for every build, or store every signing input only in transient shell environment variables.

### 2026-07-13 — Cap emulator CPU and use the host GPU

**Decision:** Run the preserved Android AVD with two guest cores, 2 GiB of RAM, host GPU acceleration, no audio, no boot animation, and snapshots disabled for the end-to-end verification.

**Why:** The original four-core software-rendered launch saturated the Mac and caused a host crash. Hypervisor.framework and host Vulkan/GLES were available; the capped configuration kept the Mac responsive while preserving the API 36 ARM64 test environment and existing app data.

**Alternatives considered:** Continue with SwiftShader, run the emulator headlessly, or defer all remaining verification to a physical device.

### 2026-07-13 — Reuse the no-referrer install-source variant

**Decision:** Configure the Android `selfhosted` flavor to use `independent` as its matching fallback for flavor-aware library dependencies.

**Why:** Ente's install-source plugin mirrors the application flavor dimension and is the only dependency that could not resolve a new flavor automatically. Its `independent` variant already supplies the appropriate no-referrer implementation, so the fallback makes the personal artifact buildable without adding Play Store attribution or changing any official plugin variant.

**Alternatives considered:** Add a fifth flavor to the shared plugin, use the Play Store referrer implementation, or leave the dependency unresolved.

### 2026-07-13 — Preflight with an API 36 Google APIs ARM64 emulator

**Decision:** Preserve a dedicated Pixel 7 AVD under the isolated Android toolchain and use a temporary D8-compiled Java diagnostic through Android's `app_process` to test private DNS, the platform trust store, Museum, and MinIO before changing application packaging.

**Why:** The clean Android 16 image matches the build target and proved the device-side network path independently of Ente application code. Its shell does not include `curl`, `wget`, or `openssl`, so the temporary diagnostic exercised Android's actual HTTPS implementation without adding files or dependencies to the repository.

**Alternatives considered:** Rely on host-only HTTPS checks, install extra software into the emulator, or postpone device networking until after the self-hosted flavor exists.

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

### Phase 1

- Android builds require the isolated API-level toolchain plus rustup first on `PATH`; transitive Gradle plugins may install older SDK, NDK, build-tools, and CMake versions side by side with the pinned versions.
- A clean Google APIs ARM64 emulator can resolve the host's private Tailscale DNS name, route to its Tailscale address, and trust its private HTTPS certificates without application-specific network-security exceptions.
- Minimal Android system images do not necessarily include familiar HTTPS command-line clients. A temporary D8-compiled diagnostic run with `app_process` can exercise Android's trust store without changing the app or repository, and should be removed immediately afterward.

### Phase 2

- Flavor-aware Flutter plugins can require an explicit Gradle fallback even when most plugins are flavor-agnostic; resolving `selfhosted` to the install-source plugin's `independent` variant preserves the intended no-referrer behavior.
- Each application flavor drives separate native Rust build tasks. A universal debug APK is correspondingly large, but it gives one artifact that covers the ARMv7, ARM64, and x86_64 emulator/device paths needed by this initiative.
- A useful locked-artifact audit combines compile-time tests, wrapper rejection cases, the exact generated package ID, manifest launcher merging, APK signature and ABI inspection, the embedded canonical hostname, and a checksum. Any one of those checks alone leaves a meaningful packaging gap.
