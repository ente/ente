# Locked Self-Hosted Ente Photos for iOS

**Status:** Living document. Updated at the end of every task.
**Started:** 2026-07-13
**Owner:** vanton
**Planning doc:** n/a
**Companion docs:** `mobile/apps/photos/README.md`, `docs/docs/self-hosting/installation/post-install/index.md`, `docs/docs/self-hosting/administration/object-storage.md`

---

## 1. Phase / Task tracker

| Phase | Task | Title | Size | Status | Notes |
|------:|----:|-------|:----:|--------|-------|
| 1 | 1.1 | Align the repository-pinned mobile toolchain and generated bindings | M | 🟢 done | Verified Flutter 3.38.10, native rustup Rust 1.97.0, locked Flutter packages, unchanged generated Rust bindings, and a deployment-clean CocoaPods graph. Refreshed stale plugin spec checksums in `Podfile.lock`. |
| 1 | 1.2 | Produce an unchanged Photos build for an iOS simulator | S | 🟢 done | Built and signature-verified the unchanged `io.ente.frame.debug` app at `mobile/apps/photos/build/ios/Debug-iphonesimulator/Runner.app` for the arm64 iOS Simulator. Recorded the clean-checkout generation and machine setup prerequisites below. |
| 1 | 1.3 | Install and verify a local Ente quickstart cluster | S | 🟢 done | Installed the official Docker quickstart outside Git at `/Users/vanton/projects/my-ente`. Verified healthy Museum and PostgreSQL containers, Museum `/ping`, MinIO health, and HTTP 200 responses from the Photos and Albums web applications; restricted generated configuration files and all published HTTP ports to the local Mac. |
| 1 | 1.4 | Expose Museum and MinIO through private Tailscale HTTPS | M | 🟢 done | Reused the installed and authenticated Tailscale client, enabled private Serve routes for Museum on HTTPS port 443 and MinIO on HTTPS port 8443, and changed Museum to generate HTTPS object-storage URLs. Verified both TLS routes and Museum-to-MinIO reachability. |
| 1 | 1.5 | Preflight Museum and object-storage reachability | S | 🟢 done | From an iOS 26.5 Simulator, verified Apple-trusted HTTPS, Museum `/ping`, MinIO health, and a short-lived signed object download through the private hostname. Confirmed quickstart companion-app URLs remain local and unpublished under the core-only scope. |
| 2 | 2.1 | Add and unit-test the fail-closed endpoint policy | M | 🟢 done | Added compile-time endpoint validation, persistent endpoint binding, foreground/background startup gates, locked mutation rejection, authenticated same-origin enforcement, and a local recovery screen. Verified 18 focused tests under normal and locked defines, all 262 Photos tests, and a clean analyzer run. |
| 2 | 2.2 | Disable endpoint editing and add the locked-build command | S | 🟢 done | Removed the seven-tap editor from locked compilations while retaining the read-only server label. Added and documented a wrapper that shares the runtime validator, rejects define overrides, and applies the arm64 simulator workaround. Verified normal and locked UI/policy tests, all 264 Photos tests, a clean analyzer run, wrapper rejection cases, and a real locked simulator artifact. |
| 2 | 2.3 | Add the core-only self-hosted iOS target and signing configuration | M | 🟢 done | Added the shared `selfhosted` scheme and `SelfHostedRunner` target with bundle ID `com.vanton1.ente.photos.selfhosted`, local team input, empty entitlements, a separate CocoaPods aggregate, and no extension dependencies. Verified a locked arm64 simulator artifact and reproducible pod installation while preserving the official Runner. |
| 3 | 3.1 | Verify the locked build end to end in the simulator | M | 🟢 done | On an arm64 iOS 26.5 Simulator, registered a local account, synced, uploaded an encrypted image, downloaded it after device-local deletion, and preserved the account across restarts. A same-bundle build for a different valid HTTPS origin showed the local endpoint-binding diagnostic with zero Museum requests; restoring the correct build preserved the account and photo. Enabled Xcode ad-hoc signing so embedded simulator frameworks load correctly. |
| 3 | 3.2 | Install and verify the locked build on a physical iPhone | M | 🟢 done | Built and audited a Personal Team-signed arm64 release, registered and provisioned the connected iPhone without committing personal identifiers, and installed and trusted the app. On iOS 26.5.2, registered a local account, synced, uploaded encrypted photos through private MinIO, downloaded a cloud copy after device-local deletion, and preserved the account and photo across a forced restart. Rebuilt, signature-verified, installed, and launched the simulator artifact after the signing changes. |

**Legend:** ⚪ not started · 🟡 working · 🟢 done · 🔴 blocked / needs decision
**Size:** XS · S · M · L · XL (never days or weeks).

One task is one reviewable step. Mark a row 🟡 working before implementation and 🟢 done after its verification passes. Use `Task <phase>.<sub> — <short imperative title>` for corresponding commits.

---

## 2. Goal

Create a personal-development iOS build of Ente Photos that is permanently bound to one self-hosted Museum HTTPS origin. A successful V1 builds and runs on an iOS simulator and a personally signed iPhone, supports registration or login plus photo sync, upload, and download, cannot be switched to Ente's production API, and fails before authenticated networking when its endpoint configuration or local endpoint identity is unsafe. Normal Ente builds must retain their current production and developer-endpoint behavior.

---

## 3. Architecture / approach

The existing Photos app already accepts an `endpoint` Dart define and stores a runtime endpoint override. V1 extends that mechanism with an explicit `lockedEndpoint` compile-time policy rather than introducing a separate Dart application bootstrap.

In a normal build, endpoint behavior remains unchanged. In a locked build:

- The compiled endpoint must be an absolute HTTPS Museum origin and must not be either Ente production origin.
- Foreground and background entrypoints validate the policy before creating any network client.
- The compiled endpoint takes precedence over preferences, runtime endpoint mutation is rejected, and the seven-tap editor is inert. The existing custom-endpoint label remains as a read-only indicator.
- The app stores an endpoint-identity binding on a clean first launch. Existing account/endpoint state or a different binding fails closed with local reset instructions; the app never silently erases local data.
- Authenticated Museum requests must remain on the compiled origin and do not follow redirects in the locked build. Presigned object-storage requests remain allowed because Museum intentionally sends those through the non-Museum download/upload clients.
- Invalid foreground startup renders a local diagnostic view without initializing networking. Invalid background startup records a local error and returns without networking.

The supported build path uses a wrapper that validates `ENTE_SELF_HOSTED_ENDPOINT` with the same Dart policy used at runtime and supplies `lockedEndpoint=true` plus the canonical endpoint define. It rejects caller-supplied Dart defines and flavors so these inputs cannot be overridden. On Apple-silicon simulator builds, it configures Flutter and then invokes Xcode for arm64 only, matching the proven baseline workaround for the unsupported x86_64 Rust slice. Simulator code signing remains enabled with the ad-hoc identity so Xcode and CocoaPods sign every embedded framework for the simulator runtime. A core-only `SelfHostedRunner` target and shared `selfhosted` scheme use bundle ID `com.vanton1.ente.photos.selfhosted`, accept the local Apple development-team identifier through `ENTE_IOS_DEVELOPMENT_TEAM`, and use an empty entitlement set. They have a separate CocoaPods aggregate, do not directly declare the StoreKit framework or In-App Purchase capability, and do not depend on or embed the production Share Extension and widgets. The official Runner target's existing configurations, phases, dependencies, and signing settings stay unchanged.

The wrapper always runs Flutter's configuration-only phase with code signing disabled; the following direct Xcode build owns the complete simulator or device signature. A signed device build can take the connected phone identifier through `ENTE_IOS_DEVICE_ID`, select that device as its destination, and allow Xcode to register it and update its development profile. Omitting the optional device identifier retains the generic device destination for already-provisioned builds. Team, device, certificate, and profile values remain local command inputs or Apple-managed state rather than repository configuration.

The local deployment baseline is Ente's official Docker quickstart in `/Users/vanton/projects/my-ente`. It keeps PostgreSQL private to Docker while exposing Museum at `http://127.0.0.1:8080`, MinIO at `http://127.0.0.1:3200`, Photos web at `http://127.0.0.1:3000`, and Albums web at `http://127.0.0.1:3002`. These loopback HTTP addresses remain local diagnostics only. Tailscale Serve privately publishes Museum on HTTPS port 443 and MinIO on HTTPS port 8443 of one tailnet DNS hostname; the web applications are not published.

Museum uses that tailnet hostname and MinIO HTTPS port for all three quickstart buckets, with local-bucket mode disabled and path-style URLs retained. Museum and remote clients therefore use the same TLS endpoint in signed object-storage URLs. The quickstart `socat` sidecar was removed because Museum no longer resolves `localhost:3200` to MinIO.

The intended flow is:

```text
build wrapper -> validate HTTPS self-host origin -> compile locked policy
      |
      v
app startup -> validate policy and endpoint binding -> initialize Museum client
      | invalid                                  | valid
      v                                          v
local diagnostic, no networking            account and photo flows
```

---

## 4. Future work / out-of-scope

> Single source of truth for everything that is NOT in V1. Items move into V1 only with explicit approval and a decision-log entry.

| Item | Status | Why |
|------|--------|-----|
| Push notifications, Share Extension, widgets, and application groups for the personal target | V1.1 backlog | V1 proves the core Photos account and media flows without provisioning Ente's complete Apple target suite. |
| Self-host or disable Ente-operated ancillary services such as Sentry, update checks, payments, and model assets | Out of scope | The chosen V1 guarantee applies only to the Museum API. |
| Network-wide allowlisting or an air-gapped build | Out of scope | Third-party maps, legal links, model downloads, and other non-Museum networking remain permitted. |
| HTTP LAN endpoints | Out of scope | The chosen deployment uses a trusted HTTPS hostname reachable by both simulator and iPhone. |
| Ad hoc, TestFlight, or App Store distribution | Out of scope | V1 uses personal development signing only. |
| Runtime server switching in the locked artifact | Out of scope | Immutability is the purpose of the locked build; changing servers requires rebuilding and clearing the installation. |
| Generic self-hosted build support for all contributors and mobile apps | Out of scope | V1 targets one personal Ente Photos iOS workflow rather than an upstream-wide flavor system. |
| Remote access to Photos companion web applications | Out of scope | V1 publishes only Museum and object storage to the private tailnet; public Albums, Cast, Accounts, and other web applications remain local or use the upstream ancillary defaults allowed by the Museum-only policy. |
| Separate architecture companion document | Out of scope | The endpoint policy and packaging path are compact enough to document here and in the build runbook. |

**Status values:**
- `V1.1 backlog` — deferred but planned for the next milestone.
- `Out of scope` — will not be done in this initiative; distinct from deferred work.

---

## 5. Decision log

> Append-only. Newest entries stay on top. If a decision changes, add a new entry instead of rewriting history.

### 2026-07-13 — Keep the self-hosted target compatible with a Personal Team

**Decision:** Remove the direct StoreKit framework declaration from only `SelfHostedRunner`, leaving the official Runner and the shared Flutter dependency graph unchanged. The personal target does not declare the In-App Purchase capability.

**Why:** Xcode treated the direct StoreKit declaration as an In-App Purchase capability and refused to create a profile because Apple Personal Teams cannot provision it. The self-hosted V1 does not need payments, and its signed release succeeds with the existing Flutter plugin dependency but without the target-level declaration.

**Alternatives considered:** Use a paid or corporate Apple team, remove the purchase plugin from the shared Dart application, or keep an uncommitted local Xcode edit. Those choices would broaden required credentials, change normal Ente behavior, or make the personal build irreproducible.

### 2026-07-13 — Give Xcode sole ownership of device signing and registration

**Decision:** Run Flutter's configuration-only phase with `--no-codesign`, then let the wrapper's direct Xcode build perform the final signature. Signed builds may provide `ENTE_IOS_DEVICE_ID` so Xcode selects and registers that connected phone while automatic provisioning updates are enabled.

**Why:** Flutter's configuration phase rejected a valid local certificate before the intended Xcode signing phase, while a generic device destination could not register the first Personal Team device. Separating configuration from signing and optionally selecting the connected phone produced a minimal, audited development profile without committing a team or device identifier.

**Alternatives considered:** Let both Flutter and Xcode sign, require the phone to be registered manually in Apple's portal, or hard-code the local team and phone identifiers. Dual signing failed early, manual registration adds avoidable setup, and hard-coding personal identifiers makes the fork machine-specific.

### 2026-07-13 — Ad-hoc sign the complete simulator bundle

**Decision:** Keep simulator code signing enabled and pass Xcode the ad-hoc identity `-` so the application and every embedded framework are signed as part of the normal build.

**Why:** Disabling signing produced an installable bundle, but the iOS 26.5 Simulator terminated it in dyld because embedded media frameworks such as `Ass.framework` were unsigned. The signed wrapper build passes strict deep verification and launches normally.

**Alternatives considered:** Keep signing disabled, post-sign only the outer application with `codesign --deep`, or require an Apple Development certificate for simulator builds. The first remained unlaunchable, the post-build attempt did not sign the flattened prebuilt framework, and a developer certificate is unnecessary for simulator execution.

### 2026-07-13 — Keep personal Apple signing local to the build command

**Decision:** Fix the self-hosted application identity at `com.vanton1.ente.photos.selfhosted`, use an empty entitlement set, and supply the owner's Apple development-team identifier at build time through `ENTE_IOS_DEVELOPMENT_TEAM`. Do not commit a personal team identifier or certificate identity.

**Why:** The unique bundle ID can coexist with the official app, while empty entitlements avoid Ente-owned push, associated-domain, and application-group capabilities. A local team input lets automatic signing create the appropriate development profile without coupling the fork to one Apple account.

**Alternatives considered:** Reuse Ente's bundle identity and team, commit the owner's team identifier, or provision the complete production capability suite. Those choices would fail personal signing, leak machine-specific configuration into the fork, or expand V1 into the deferred extension work.

### 2026-07-13 — Reserve Dart defines for the locked build wrapper

**Decision:** Reject caller-supplied `--dart-define`, `-D`, and define-file options in the self-hosted iOS wrapper, then append the validated `lockedEndpoint` and `endpoint` values itself.

**Why:** A convenient build option must not be able to override the two inputs that establish the artifact's server guarantee. Other Flutter build-mode and version arguments remain available without weakening the endpoint lock.

**Alternatives considered:** Rely on argument ordering so the wrapper's values win, or permit unrelated Dart defines while parsing only endpoint-related keys. Duplicate-key precedence is less explicit, and accepting define files makes reliable key inspection unnecessarily complex for this personal build path.

### 2026-07-13 — Reuse the runtime endpoint policy during builds

**Decision:** Move the two production Museum origins into a Dart-only constants library and run the app's `EndpointPolicy` from a small command-line validator before invoking Flutter.

**Why:** Build-time and startup validation now canonicalize and reject exactly the same endpoint values, avoiding a second shell implementation of URL and production-host rules.

**Alternatives considered:** Duplicate validation with shell regular expressions or let invalid inputs compile and fail only when the app launches. Shell URL parsing is easy to diverge, while a late startup failure wastes a full iOS build and weakens the supported command's feedback.

### 2026-07-13 — Disable redirects for locked authenticated Museum requests

**Decision:** Require the final authenticated request URI to match the compiled Museum scheme, host, and effective port, then disable automatic redirects for that request in locked builds. Leave normal builds and unauthenticated or object-storage clients unchanged.

**Why:** Validating before dispatch prevents direct cross-origin requests, while disabling redirects ensures an authenticated request cannot be forwarded after that check. Museum API calls do not require redirects, so rejecting all of them is a small and auditable security boundary.

**Alternatives considered:** Follow same-origin redirects or inspect each redirect target dynamically. Dio's request interceptor runs before the HTTP adapter follows redirects, so either option would require a more invasive redirect handler for no V1 API requirement.

### 2026-07-13 — Persist the locked endpoint identity across logout

**Decision:** On the first clean locked launch, store a canonical endpoint binding in preferences. Preserve only that binding when logging out, reject runtime endpoint preference state, and reject account state that predates a matching binding.

**Why:** A stable binding makes the server identity explicit for the installation and prevents account state from one artifact or endpoint being silently reused with another. Preserving it through logout keeps subsequent accounts on the same compiled server without weakening the normal build's existing preference-clearing behavior.

**Alternatives considered:** Derive identity solely from the current compile-time define, overwrite a binding on every launch, or clear it during logout. Those choices cannot distinguish unsafe pre-existing state, silently accept an artifact switch, or unnecessarily discard the installation identity.

### 2026-07-13 — Switch Museum's quickstart buckets to the private HTTPS endpoint

**Decision:** Configure all three quickstart buckets with the tailnet MinIO hostname and HTTPS port, disable Museum's local-bucket mode, retain path-style URLs, and remove the no-longer-needed `socat` forwarding container.

**Why:** Museum embeds its bucket endpoint in presigned URLs, so both Museum and the iOS client must reach the same address. Disabling local-bucket mode makes the Amazon S3 client use TLS, while path-style URLs preserve MinIO compatibility.

**Alternatives considered:** Keep `localhost:3200` plus `socat`, which produces client-unreachable signed URLs, or give Museum a separate internal endpoint, which would require additional URL-rewriting behavior outside the quickstart design.

### 2026-07-13 — Use separate HTTPS ports on one tailnet hostname

**Decision:** Publish Museum on HTTPS port 443 and MinIO on HTTPS port 8443 of the Mac's private Tailscale DNS hostname. Do not publish the Photos or Albums web applications.

**Why:** The iOS client gets a conventional Museum origin while MinIO keeps an independent origin suitable for S3 path-style requests and signatures. Both remain accessible only to authenticated tailnet devices.

**Alternatives considered:** Route MinIO below a Museum URL path, allocate a second tailnet service hostname, or expose MinIO directly on the local network. A path prefix complicates S3 request signing, a second hostname adds unnecessary service configuration, and direct exposure violates the chosen private-HTTPS boundary.

### 2026-07-13 — Bind quickstart HTTP ports to loopback

**Decision:** Override the quickstart's published Museum, MinIO, Photos, and Albums ports to bind to `127.0.0.1` on the Mac. Tailscale Serve will proxy only Museum and MinIO from these loopback listeners in the next task.

**Why:** The stock quickstart binds its published ports to every host interface. The chosen deployment should keep its unencrypted HTTP listeners and web applications local while granting remote devices access only through private HTTPS.

**Alternatives considered:** Keep the default all-interface bindings or rely solely on the macOS firewall. Both make the deployment's intended access boundary less explicit than enforcing it in Docker Compose.

### 2026-07-13 — Use private Tailscale HTTPS for the local server

**Decision:** Run Ente's Docker quickstart locally, then expose only Museum and MinIO through Tailscale Serve over automatically provisioned HTTPS inside the owner's private tailnet. Keep the web applications on local HTTP for setup and diagnostics.

**Why:** Both the simulator and physical iPhone need a stable, trusted HTTPS Museum origin and must reach the object-storage address embedded in presigned URLs. A private tailnet provides those properties without publishing the development server to the internet.

**Alternatives considered:** Keep the installation on loopback HTTP only, or publish it through a public domain and Caddy. Loopback cannot serve the phone, while public exposure adds unnecessary DNS and internet-facing operations for a personal development server.

### 2026-07-13 — Store the quickstart installation outside Git

**Decision:** Create the generated Ente quickstart installation at `/Users/vanton/projects/my-ente` rather than inside the fork checkout.

**Why:** The quickstart directory contains unique database, object-storage, Museum encryption, and JSON Web Token secrets alongside its Compose configuration. Keeping it outside the repository prevents accidental staging or publication.

**Alternatives considered:** Create `my-ente` at the repository root or edit the checked-in sample configuration in place. Both put runtime secrets and mutable deployment state next to source control.

### 2026-07-13 — Preinitialize Rive Native from the Photos package

**Decision:** Run `dart run rive_native:setup --verbose --platform ios` from `mobile/apps/photos` when the Rive iOS setup marker is absent, before invoking Xcode.

**Why:** Rive's CocoaPods script attempts the same Dart command from `ios/Pods`. Dart rejects that working directory before the package executable can relocate to the workspace, whereas the documented manual command succeeds from the Photos package and installs the pinned iOS libraries in the dependency cache.

**Alternatives considered:** Patch the cached third-party podspec, commit downloaded Rive binaries, or repeatedly let the CocoaPods script fail. None belongs in the unchanged application baseline.

### 2026-07-13 — Complete Xcode first-launch setup after an update

**Decision:** Require `xcodebuild -checkFirstLaunchStatus` to pass and run `xcodebuild -runFirstLaunch` when it does not before attempting a Simulator build.

**Why:** Xcode 26.6 was installed while its system CoreSimulator resources remained at 26.5, which disabled all Simulator device support. Xcode's standard first-launch installer refreshed the resources and restored the installed iOS 26.5 runtime.

**Alternatives considered:** Treat the mismatch as an application failure, kill Simulator services without updating their framework, or require a source change. None addresses the machine-level version mismatch.

### 2026-07-13 — Build the baseline Simulator artifact for arm64

**Decision:** On this Apple-silicon Mac, compile the unchanged baseline with Xcode's `ARCHS=arm64` and `ONLY_ACTIVE_ARCH=YES` command-line settings. Do not commit an architecture exclusion to the upstream Runner or Pods projects.

**Why:** The standard generic Simulator build requests both arm64 and x86_64. The pinned ONNX Runtime Rust archive contains an arm64 prelinked object, so the x86_64 link fails with an undefined `_OrtGetApiBase` symbol while the arm64 build succeeds. The resulting `Runner.app` is an arm64 `iPhoneSimulator` bundle with the expected `io.ente.frame.debug` identifier and a valid local signature.

**Alternatives considered:** Commit an x86_64 exclusion to the existing iOS project, change the pinned ONNX Runtime dependency, or treat the x86_64 failure as an endpoint-policy problem. Those options alter upstream build behavior or dependency scope before the unchanged baseline is proven.

### 2026-07-13 — Generate ignored Dart parts after Rust bridge generation

**Decision:** After `cargo codegen frb`, run `dart run build_runner build --delete-conflicting-outputs` in both `mobile/packages/rust` and `mobile/apps/photos` before the iOS build.

**Why:** Flutter Rust Bridge emits ignored Dart source containing Freezed `part` declarations, but it does not emit `contacts.freezed.dart` or `ml_indexing_api.freezed.dart`. Both packages declare the required builders, and their generated outputs are intentionally ignored rather than source-controlled.

**Alternatives considered:** Commit generated bridge or Freezed output, hand-write the missing union classes, or remove the generated `part` declarations. All would fight the repository's generated-source convention.

### 2026-07-13 — Isolate work in a personal GitHub fork

**Decision:** Preserve `https://github.com/ente/ente.git` as the read-only `upstream` remote, use `https://github.com/vanton1/ente.git` as `origin`, and push task commits on the `codex/locked-self-hosted-ios` feature branch.

**Why:** Development and pushes must not interfere with the original Ente repository or its `main` branch.

**Alternatives considered:** Commit directly on the local `main` branch, or leave the official repository configured as the push remote.

### 2026-07-13 — Refresh stale Photos podspec checksums

**Decision:** Regenerate the Photos `Podfile.lock` checksum block from the locked Dart dependency graph and accept the resulting spec-checksum-only change.

**Why:** The checked-in Photos lockfile predated the mobile Dart-workspace migration and later `mobile/pubspec.lock` update. CocoaPods 1.16.2 rejected it in deployment mode even though every pod version, external source, Podfile checksum, and CocoaPods version remained unchanged. The regenerated lockfile now passes `pod install --deployment`.

**Alternatives considered:** Keep the stale lockfile and bypass deployment verification, or upgrade pod versions as part of this task. Both would weaken reproducibility or expand scope unnecessarily.

### 2026-07-13 — Use isolated pinned mobile toolchains

**Decision:** Run the project with an isolated Flutter 3.38.10 checkout and put rustup's native Apple-silicon Rust 1.97.0 ahead of the incompatible Homebrew Rust installation in build commands.

**Why:** The system Flutter is 3.41.7, while the repository and CI pin 3.38.10. The shell's Homebrew Rust 1.84 is both too old for Edition 2024 and broken against its installed LLVM; the rustup toolchain parses the workspace and completes bridge generation.

**Alternatives considered:** Modify the system Flutter checkout, or repair/replace Homebrew Rust globally. Isolated command paths avoid changing unrelated projects.

### 2026-07-13 — Use repository documentation as project context

**Decision:** Link the Photos build instructions and repository self-hosting documentation; do not link unrelated local planning files or create a separate architecture companion.

**Why:** These are the sources that define the current client build and Museum/object-storage requirements.

**Alternatives considered:** Add unrelated local plans, require external deployment notes, or create a separate as-built architecture document.

### 2026-07-13 — Fail closed and require manual reset

**Decision:** Invalid build configuration and endpoint-identity mismatches stop before networking and show local instructions to clear or reinstall the app. Do not erase local state automatically.

**Why:** This prevents production credentials or databases from being mixed with a self-hosted server and avoids silent destructive behavior.

**Alternatives considered:** Automatically clear local state, or terminate with logs and no user-visible diagnostic.

### 2026-07-13 — Add a core-only self-hosted Apple target

**Decision:** Add a minimal self-hosted development target and scheme with a personal bundle identity and no production extension dependencies.

**Why:** The existing project embeds extensions and entitlements owned by Ente's Apple Developer team, so a reproducible personal iPhone build cannot sign the existing target unchanged.

**Alternatives considered:** Keep fragile uncommitted Xcode edits, or parameterize and provision the entire extension suite.

### 2026-07-13 — Use personal development signing

**Decision:** V1 installs from Flutter/Xcode on the owner's simulator and iPhone, using a unique personal bundle identity.

**Why:** Distribution to other devices and App Store Connect are not required to prove the self-hosted workflow.

**Alternatives considered:** Ad hoc team distribution and TestFlight distribution.

### 2026-07-13 — Require a shared HTTPS hostname

**Decision:** Museum and object storage must be reachable through trusted HTTPS addresses from both simulator and iPhone.

**Why:** An iPhone cannot use the Mac's `localhost`, and client-reachable object-storage URLs are required for media transfers.

**Alternatives considered:** A changing LAN IP over HTTP, or Mac-only loopback that cannot satisfy the physical-device goal.

### 2026-07-13 — Prove simulator and iPhone behavior

**Decision:** Validate on a simulator first, then repeat critical flows on a physical iPhone.

**Why:** Simulator feedback shortens build iteration while the phone exposes real signing, local-network, and object-storage reachability problems.

**Alternatives considered:** Physical iPhone only, or simulator only.

### 2026-07-13 — Sequence work risk first

**Decision:** Align the toolchain, prove the unchanged iOS build, and preflight the server before implementing endpoint policy changes.

**Why:** The current Flutter and Rust installations do not match repository requirements, so build feasibility is the first meaningful risk.

**Alternatives considered:** Implement an end-to-end vertical slice immediately, or finish policy code before attempting an iOS build.

### 2026-07-13 — Encode locking as a compile-time policy

**Decision:** Extend the current endpoint configuration with a locked compile-time mode and retain the existing Dart entrypoint.

**Why:** This adds the required invariant with less bootstrap duplication than a second Dart entrypoint and keeps endpoint behavior testable in one place.

**Alternatives considered:** A separate self-hosted Dart entrypoint, or making all endpoint behavior depend on Xcode schemes and build settings.

### 2026-07-13 — Lock only the Museum API in V1

**Decision:** Make the Museum origin immutable and reject Ente production API origins while leaving ancillary and third-party services unchanged.

**Why:** The requested server isolation concerns account and photo data without expanding V1 into an air-gapped fork.

**Alternatives considered:** Disable all Ente-operated services, or enforce a network-wide host allowlist.

### 2026-07-13 — Build a locked self-hosted artifact

**Decision:** Produce a separate personal Ente Photos binary that cannot be switched to Ente production.

**Why:** A runtime-selectable local development build does not satisfy the requested guarantee that the artifact use the self-hosted server rather than the official one.

**Alternatives considered:** A personal build retaining the hidden endpoint switcher, or a generic contributor-facing build workflow.

---

## 6. Open questions

_None._

---

## 7. Lessons learned

> Populated at the end of each phase. Record surprises, anti-patterns, and improvements for the next phase.

### Phase 3 — Verify fail-closed behavior and real-device operation

- A complete iPhone proof must audit the built signature and entitlements, install the exact audited bundle, and confirm Museum requests identify the distinct self-hosted bundle; a successful compile alone does not prove the packaging boundary.
- Personal Team provisioning exposes target capabilities that simulator builds cannot: a direct StoreKit declaration blocked profile creation even though the self-hosted entitlement file was empty.
- The first signed build needs a connected device destination for automatic device registration, one-time Keychain permission for the new private key, and explicit trust of the development profile on the iPhone.
- Server-side evidence complements the visual test: Museum recorded the physical device's registration and encrypted uploads, then returned the expected object-storage redirect when the device-local photo was downloaded again.
- Rebuilding and launching the simulator artifact after the signing changes caught packaging regressions without disturbing the official Runner target.

### Phase 2 — Enforce the endpoint and package a separate Apple target

- Sharing one pure-Dart endpoint policy between runtime startup and the build validator prevented shell parsing from becoming a second, weaker security implementation.
- A Flutter iOS flavor needs matching project configurations, target configurations, shared scheme names, and CocoaPods mappings. The additional base-name target aliases keep CocoaPods compatible without changing the official Runner's existing configurations.
- A core-only Apple target is easier to sign and audit when it owns a separate CocoaPods aggregate and has no target dependencies, copy phases, or entitlements for the production extensions.
- Direct arm64 Xcode invocation remains necessary for the simulator because the Rust bridge pods do not provide the x86_64 simulator slice. Setting the Xcode product root explicitly gives the wrapper a deterministic artifact path.

### Phase 1 — Establish a buildable client and reachable private server

- A health check alone is not enough for Ente: the preflight must exercise a signed object transfer because Museum embeds the storage origin in upload and download URLs.
- The stock quickstart's all-interface port bindings and `localhost` storage endpoint are suitable only for same-host evaluation. A phone-capable private deployment needs explicit loopback bindings plus a shared HTTPS storage origin.
- The unchanged iOS baseline exposed machine and generated-source prerequisites before endpoint work began, keeping Flutter, Rust, CocoaPods, Rive, Xcode, and Simulator failures out of the policy implementation.
