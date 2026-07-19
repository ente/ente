# Firebase iOS Distribution for the Self-Hosted Photos App

**Status:** Living document. Updated at the end of every task.
**Started:** 2026-07-17
**Owner:** vanton
**Planning doc:** n/a
**Companion docs:** `living_docs/ConfigurableSelfHostedMobileServer.md`, `living_docs/ConfigurableSelfHostedMobileServerArchitecture.md`, `living_docs/LockedSelfHostedIOS.md`, `living_docs/FirebaseAndroidDistribution.md`, `mobile/apps/photos/SELF_HOSTED_BUILD_GUIDE.md`, `mobile/apps/photos/SELF_HOSTED_IOS_DISTRIBUTION_GUIDE.md`, `living_docs/FirebaseIOSDistributionArchitecture.md`

---

## 1. Phase / Task tracker

| Phase | Task | Title | Size | Status | Notes |
|------:|----:|-------|:----:|--------|-------|
| 1 | 1.1 | Audit Cytech membership and signing permissions | S | 🟢 done | Verified the selected Cytech Ltd organization has an active Apple Developer Program membership, the current program agreement is accepted, and Certificates, Identifiers, Devices, Profiles, Keys, and App Store Connect resources are available. The owner is the Account Holder rather than only an Admin, so closed-beta authorization and full signing-resource access are satisfied without another approver. Local audit found Xcode 26.6, two valid Apple Development identities, no Apple Distribution identity, and only expired historical Cytech profiles; Tasks 1.3 and 1.5 therefore remain responsible for current distribution signing and provisioning. No Apple account state changed, and no team identifier, address, phone number, device identifier, certificate, or profile was added to Git. |
| 1 | 1.2 | Register the new self-hosted Apple App ID | S | 🟢 done | Registered explicit Apple App ID `me.vanton.ente.photos.selfhosted` under the verified Cytech organization with description `Ente Photos Self-Hosted`. The pre-registration confirmation and resulting identifier list showed the exact bundle value and no additional capabilities. No certificate, device, provisioning profile, Team ID, account detail, or credential was added to Git or changed outside this App ID registration. |
| 1 | 1.3 | Establish the Apple Distribution certificate | S | 🟢 done | Left the active teammate-created distribution certificate untouched and created a separate `Apple Distribution: Cytech Ltd` identity through Xcode. The matching private key is available in the macOS login Keychain and was not exported. `security find-identity` validates the identity; its public SHA-256 fingerprint is `8fcaf5f761acbcbeeae4710fb75370646071d8a905ac2a70ffeb46676c4a1e0c`, and the certificate expires on 2027-07-17. No App ID, device, provisioning profile, certificate private key, team identifier, or account detail was added to Git, and no device or profile state changed. |
| 1 | 1.4 | Register the owner's iPhone privately | S | 🟢 done | Completed Cytech's new-membership-year device-list review while retaining the existing owner iPhone. The Apple device detail offered `Disable`, proving the retained device is enabled, and its identifier was compared privately with the paired, available `vPhone` in Xcode and matched. No new device slot was consumed, and no device identifier or personal device detail was added to Git, release notes, or repository logs. |
| 1 | 1.5 | Create the owner-only Ad Hoc provisioning profile | S | 🟢 done | Generated and downloaded manual Ad Hoc profile `Ente Photos Self-Hosted Owner Ad Hoc` with UUID `a988a9d8-5e7e-43ef-9625-722e2fca0d3a`, expiring 2027-07-17. Local decoding verified the exact bundle/application-identifier binding, Cytech team binding without printing its identifier, one authorized device, one distribution certificate, and non-debug Ad Hoc state. The embedded certificate fingerprint matches Task 1.3. The `.mobileprovision` file, Team ID, and device identifier remain outside Git. |
| 1 | 1.6 | Rename only the self-hosted iOS target | M | 🟢 done | Changed the active `SelfHostedRunner` product identifier to `me.vanton.ente.photos.selfhosted` and aligned its non-entitled app-group placeholder with the new namespace. Updated current README/build/launch and clean-install guidance while preserving historical evidence and Android legacy guidance. Added two focused identity/core-only tests; they and focused analysis pass under pinned Flutter 3.38.10. Xcode resolves the new identity for Debug, Profile, and Release with the empty self-hosted entitlement file; the official Runner remains `io.ente.frame` with its original entitlements, no Android application file changed, and guarded endpoint validation still passes. |
| 1 | 1.7 | Add a reproducible Ad Hoc archive and export command | M | 🟢 done | Extended the existing guarded wrapper with non-building `--adhoc-preflight` and reproducible `--adhoc` modes. They require explicit local team/profile, expected device count, version/build, and new external archive/export paths; validate exact app/team/non-debug/device/expiry/certificate/private-key bindings; install only the validated profile locally; and archive/export with manual Xcode 26 `release-testing` options. The command pins the reviewed certificate, never enables Apple provisioning/device mutations, refuses output reuse, and requires one IPA. Eleven focused archive tests plus the target-identity tests and analysis pass; a real owner-profile/Keychain preflight also passed without invoking Flutter/Xcode or producing an artifact. No Team ID, device identifier, profile, or private key was committed. |
| 1 | 1.8 | Export and audit the baseline IPA | M | 🟢 done | Built owner-only baseline `1.3.59` (`2159`) for `https://macbook-pro-2.tailcfdac8.ts.net` and preserved the 88,632,015-byte IPA under `/Users/vanton/projects/ente-ios-toolchain/baseline-artifacts`. The first archive failed safely before artifact creation because command-line profile settings propagated to CocoaPods; target-scoped `SELF_HOSTED_*` signing indirection fixed the release path without provisioning Pods, and all 13 focused archive/identity tests plus analysis pass. The successful Xcode 26 manual export produced one extension-free IPA. Independent ZIP, archive, deep-signature, plist, AOT-string, entitlement, profile, certificate, and Mach-O audits verified the exact bundle and version, intended compiled endpoint, arm64 across 103 Mach-O files, non-debug state, no push/app-group/associated-domain/iCloud entitlements, exact private team/application binding, one authorized device, pinned certificate valid through 2027-07-17, and IPA SHA-256 `b4996440a95079b082cc45ca51f707297a9749b41ad6e61074d0fda6b42266fe`. The IPA was not installed or published, and no Team ID, device identifier, profile, private key, or export options entered Git. |
| 1 | 1.9 | Verify the new app side by side on the owner's iPhone | M | 🟢 done | Installed the audited `1.3.59` (`2159`) Ad Hoc IPA as `me.vanton.ente.photos.selfhosted` while retaining legacy `com.vanton1.ente.photos.selfhosted` `1.3.59` (`2158`). The clean new identity opened on the exact compiled Museum origin, accepted the intended local account, uploaded the latest photos in the foreground, downloaded and decrypted a cloud photo into Apple Photos, and retained the login, server binding, library, and readable media after a forced process restart. A final private device inventory confirmed both bundle identities remain installed; no account credential, media name, Team ID, or device identifier entered Git, and the IPA remains unpublished to Firebase. |
| 2 | 2.1 | Register the iOS application in Firebase | S | 🟢 done | Verified authenticated access to the existing self-hosted Firebase project, confirmed it had no iOS applications, and registered exactly one `IOS` app named `Ente Photos Self-Hosted iOS` for bundle ID `me.vanton.ente.photos.selfhosted`. A second inventory query matched the returned App ID, platform, name, and bundle exactly. The CLI path, project, iOS App ID, and bundle are stored only in `/Users/vanton/projects/ente-ios-toolchain/firebase/distribution.env`, protected by a mode-`700` directory and mode-`600` file; the App ID is absent from the repository. No Google service plist, Firebase runtime SDK, Analytics, Crashlytics, source file, tester group, or release changed. |
| 2 | 2.2 | Create the dedicated iOS tester group | S | 🟢 done | Confirmed alias `trusted-ios-testers` was absent, then created exactly one Firebase App Distribution group named `Trusted iOS Testers` without changing the pre-existing Android group. Reused the existing project-side owner tester identity privately and added it to the new group. A filtered post-change query verified exactly one member whose Firebase resource matched that owner and included the new group. No tester email, Firebase credential, invitation, release, application runtime configuration, or project binding entered Git. |
| 2 | 2.3 | Add an immutable IPA preparation command | M | 🟢 done | Added `prepare_self_hosted_ios_release.sh` and its Dart implementation. The command requires `HEAD` to be reachable from `origin/*`, requires the guarded build and preparation scripts to match that pushed commit, creates a clean detached worktree, strips Firebase/Google cloud credentials, owns temporary archive/export paths, runs the guarded Ad Hoc builder, audits the final IPA, then collision-safely preserves a mode-`0444` IPA/manifest pair in a mode-`0700` directory outside Git without invoking Firebase. The manifest binds artifact hash/size to the fork commit URL, clean-checkout evidence, Xcode/export contract, exact app/version/compiled endpoint, arm64 inventory, non-debug core-only signing, profile/device count, and pinned certificate validity without device identifiers. Static analysis, shell/help checks, 12 focused pure-Dart tests, and the optional real-owner-IPA audit pass; the latter reverified the `1.3.59` (`2159`) baseline, one-device profile, exact certificate, no extensions, and 103 arm64 Mach-O files. The existing baseline was inspected only; no new archive, prepared artifact, Firebase release, Apple state, or private identifier was created. |
| 2 | 2.4 | Add a guarded Firebase iOS publication command | M | 🟢 done | Added `publish_self_hosted_ios_release.sh` and its importable Dart implementation. It accepts only the immutable preparation manifest, requires the mode-`0444` IPA/manifest siblings in a mode-`0700` external directory, validates and re-hashes their complete source/build/iOS/profile/certificate/signature contract, repeats the native IPA audit, verifies the exact active Firebase iOS registration and `trusted-ios-testers`, generates one exact AGPL commit/build-guide link, and enforces a strictly increasing `CFBundleVersion` from mode-`0444` success receipts. Preflight is read-only. Publication requires `PUBLISH <release-id>`, then repeats the file audit, ledger, and Firebase checks before one fixed distribute call; child environments exclude Firebase, Google, Apple, signing, and unrelated cloud credentials. Complete CLI evidence writes a collision-safe success receipt; failure or ambiguous success writes a distinct partial-attempt record and forbids blind retry. Static analysis, Bash/help checks, privacy/diff scans, and 16 deterministic tests pass, including confirmation rejection, post-confirmation tamper detection, success, missing-reference recovery, and no-overwrite ledger behavior. An optional integration test twice re-audited the real `1.3.59` (`2159`) owner IPA and completed a live exact-app/group Firebase preflight. No upload, notification, durable receipt, Apple/Firebase mutation, or private identifier entered Git. |
| 2 | 2.5 | Document iOS releases, onboarding, and recovery | S | 🟢 done | Added `mobile/apps/photos/SELF_HOSTED_IOS_DISTRIBUTION_GUIDE.md`, a dedicated closed-beta operator runbook covering five independent trust boundaries; private local inputs; Museum and object-storage health; Apple signing/device scope; immutable preparation; non-mutating Firebase preflight; typed-confirmation publication and receipt reconciliation; Safari invitation acceptance; Firebase device registration; private Apple device/profile refresh; Developer Mode; Tailscale and Museum onboarding; controlled encrypted media acceptance; legacy-bundle cutover; in-place updates; four-layer offboarding; expiration; partial upload; forward rollback; signing recovery; account compromise; and wrong-server recovery. The build guide and Photos README link to it, and the companion list records it. Current primary Apple, Firebase, and Tailscale behavior was verified on 2026-07-18. All local links and command files exist; both guarded scripts pass shell syntax, executable, and help-contract checks; required topics are present; the guide contains no personal path, Firebase binding, tester identity, Team ID, device identifier, certificate fingerprint, profile identifier, private hostname, or credential; and `git diff --check` passes. |
| 2 | 2.6 | Generate Rust bindings inside the isolated release checkout | S | 🟢 done | Preparation tool `1.1.0` now runs the repository's exact `cargo codegen frb` command from the detached checkout's Rust workspace before the guarded build, exposes only six toolchain/cache environment paths, requires all six regular non-empty ignored FRB outputs, and rechecks the checkout for tracked mutations. Export contract `2` records this provenance and the publisher requires it. Focused analysis, Bash/help checks, six ignore-rule checks, `git diff --check`, and all 32 preparation/publication tests pass, including exact-command, missing-output, environment-isolation, detached-worktree, and publisher-rejection cases. No IPA, manifest, Firebase release, receipt, Apple state, or installed application changed. |
| 2 | 2.7 | Generate ignored Dart sources inside the isolated release checkout | M | 🟢 done | Preparation tool `1.2.0` now resolves the committed Flutter lockfile, generates shared and Photos localizations, runs the official FRB generator, and runs narrowly filtered shared/Photos builders inside the detached checkout. Export contract `3` requires all FRB files, both ignored Freezed files, both localization entrypoints and their complete import closures, explicit tracked-output stability, clean Git state, and separate Rust/Dart provenance accepted by the publisher. Restricted-environment, exact-order, missing-output, publisher-rejection, formatting, analysis, Bash/help, and all 35 deterministic tests pass. A real pinned-toolchain detached-checkout acceptance test regenerated every required source and finished Git-clean; no IPA, manifest, Firebase release, receipt, Apple state, or installed app changed. |
| 2 | 2.8 | Reconcile Firebase JSON-only publication success | M | 🟢 done | Publisher `1.1.0` adds a no-upload reconciliation mode over the immutable partial attempt and private mode-`0444` official release-list response. It re-audits the IPA, rechecks the active app/group and ledger, requires exit-`0` JSON success plus exactly one matching app resource, version/build, notes, creation window, and three known-host references, supports a no-write preflight, preserves both inputs, and collision-safely writes the normal success receipt with reconciliation hashes/provenance. Future distribute calls request reference-bearing CLI output instead of JSON-only mode. Formatting, analysis, Bash/help, privacy/diff checks, all 21 publisher and 38 combined tests pass. A real build-`2160` preflight matched the official release and wrote no receipt or Firebase mutation. |
| 3 | 3.1 | Publish the audited iOS baseline through Firebase | M | 🟢 done | Published the immutable `1.3.59` (`2160`) IPA/manifest pair after Museum/storage health, signing, clean-checkout generation, archive/export, audit, preflight, and exact confirmation passed. The first CLI response returned exit `0` JSON success without receipt references, so the guard preserved a mode-`0444` attempt and no retry occurred. After Task 2.8 was committed and pushed, one no-upload reconciliation matched the immutable attempt to the official read-only release-list evidence and wrote the unique mode-`0444` success receipt. An independent receipt check verified the exact build, both evidence hashes, official API method, preserved attempt, and `noUploadPerformed: true`. |
| 3 | 3.2 | Verify the owner's Firebase installation | S | 🟢 done | Accepted the Firebase invitation and installed its device-registration profile plus build `2160` on the owner's iPhone. After replacing one failed downloaded registration profile with a fresh profile, the distributed app launched, retained the configurable local server, authenticated to the intended Museum account, synced an iPhone upload to the local Photos web app, downloaded and decrypted a separate web upload, and preserved the login, server, library, and readable media after a forced process restart. No legacy-app removal was performed. |
| 3 | 3.3 | Retire the owner's legacy iOS installation | S | 🟢 done | Confirmed the replacement's bidirectional cloud sync plus restart persistence and the owner's safe copy of the local account password and recovery key. A private installed-app inventory found the legacy `com.vanton1.ente.photos.selfhosted` bundle already absent and the verified Firebase build `2160` present, so no uninstall command or app-local migration was performed. |
| 3 | 3.4 | Prepare and publish an in-place iOS update | M | 🟢 done | Verified local and private Museum/storage health, then prepared and published `1.3.59` (`2161`) from pushed commit `d61b831c33` with the same bundle, configurable server policy, Apple team, one-device profile, and signing certificate. Two preparation attempts failed safely before artifact creation when the command omitted the documented pinned Flutter and rustup PATH inputs; the corrected isolated build generated every ignored source, remained Git-clean, and produced a mode-`0444` 88,638,092-byte IPA/manifest pair with SHA-256 `7451689e8f3abb7e158fe90d3237095702606cb23d7b821d34d618a07f3cfddc`. Independent contract checks and the non-mutating Firebase preflight passed. After exact confirmation, one publication created the release and a unique mode-`0444` success receipt with all three references and no partial attempt; the `2160` receipt remained unchanged. |
| 3 | 3.5 | Verify state retention across the Firebase update | M | 🟢 done | Private device inventories confirmed Firebase replaced build `2160` with `2161` under the same bundle without deleting the application. On first launch after the update, the owner remained authenticated to the same configurable local server with the existing cloud library intact. A new iPhone upload appeared in the local Photos web app, a different web upload synchronized and decrypted on the iPhone, and a forced process restart preserved the account, server binding, library, and readable test media. |
| 3 | 3.6 | Register one non-owner tester device | S | ⚪ not started | Deferred to V1.1 until a non-owner tester and iPhone are available. Collect the invited tester's device identifier through Firebase, register it in Apple privately, and keep tester identity and device data outside Git. |
| 3 | 3.7 | Refresh provisioning and publish a tester-compatible build | M | ⚪ not started | Deferred to V1.1 with Task 3.6 because a real additional device is required. Create a profile containing the authorized tester device, rebuild with a higher `CFBundleVersion`, re-audit the IPA, and publish a distinct immutable release. |
| 3 | 3.8 | Verify a non-owner tester's installation | M | ⚪ not started | Deferred to V1.1 with Tasks 3.6–3.7. Confirm Firebase acceptance, Developer Mode, private-network access, an individual Museum account, installation, and one controlled encrypted upload/download without storing tester evidence in Git. |
| 3 | 3.9 | Document the as-built iOS distribution architecture | S | 🟢 done | Added `FirebaseIOSDistributionArchitecture.md`, a plain-language as-built companion covering the independent Git/operator/Apple/artifact/Firebase/device/private-network/Museum trust boundaries; core-only application identity; pinned isolated preparation; typed-confirmation publication and ambiguous-success reconciliation; verified in-place update state retention; runtime data flow; evidence/privacy rules; failure recovery; forward rollback; operator checklists; and the explicitly deferred V1.1 non-owner proof. All relative links resolve, required sections are present, the Markdown diff is clean, and the changed text contains no screened personal path, email, private hostname, or Firebase App ID. |

**Legend:** ⚪ not started · 🟡 working · 🟢 done · 🔴 blocked / needs decision
**Size:** XS · S · M · L · XL (never days or weeks).

One task = one row = one reviewable step. Mark a row 🟡 working before starting it and 🟢 done only after its acceptance evidence passes. Describe each task and wait for approval before implementation.

Task naming convention: `Task <phase>.<sub> — <short imperative title>`. If a commit is opened for a task, mirror that title.

---

## 2. Goal

Distribute pre-release builds of the configurable self-hosted Ente Photos iOS application to the owner through Firebase App Distribution and Apple Ad Hoc provisioning, while leaving a documented path for a small trusted group later. V1 is complete when the self-hosted target uses bundle identifier `me.vanton.ente.photos.selfhosted` under the Cytech Ltd Apple Developer Program team; the owner installs an audited Firebase baseline and then an in-place update that preserves account, server, and library state; the previous `com.vanton1.ente.photos.selfhosted` installation is retired without app-local migration only after the replacement is proven; and the settled architecture and operating boundaries are documented. Non-owner device registration, profile expansion, and installation verification are V1.1 work.

The observable success metric is one new-identity owner baseline plus one higher-build-number owner update that preserves the account, active server, cloud library, encrypted media flows, and restart state. Operator success also requires that wrong bundle IDs, Apple teams, certificates, profiles, device sets, compiled endpoints, modified IPAs, dirty or unpushed source, non-increasing build numbers, incorrect Firebase registrations, and expired signing assets fail before publication.

---

## 3. Architecture / approach

The settled as-built view lives in [`FirebaseIOSDistributionArchitecture.md`](FirebaseIOSDistributionArchitecture.md). This section retains the chronological design and implementation record.

### Identity and ownership cutover

Before Task 1.6, the proven configurable iOS application used bundle identifier `com.vanton1.ente.photos.selfhosted` and a short-lived Personal Team development profile. The active source now uses the target closed-beta identity:

| Property | Target value |
|---|---|
| Native target | `SelfHostedRunner` |
| Bundle identifier | `me.vanton.ente.photos.selfhosted` |
| Apple team owner | Cytech Ltd organization team |
| Distribution method | Apple Ad Hoc delivered by Firebase App Distribution |
| Firebase group | `trusted-ios-testers` |

Only the self-hosted target changes identity. The official Ente Runner, Android application IDs, configurable endpoint policy, empty self-hosted entitlement set, and exclusion of Share Extension and widgets remain unchanged. Team identifiers, certificate private keys, provisioning profiles, device identifiers, and Firebase credentials remain local Apple/Firebase state or external release inputs.

Task 1.6 changed the shared self-hosted Xcode configuration's product identifier to `me.vanton.ente.photos.selfhosted`. Its `CUSTOM_GROUP_ID` Info.plist placeholder now follows the `group.me.vanton.ente.photos.selfhosted` namespace, but the target's entitlement file remains empty and the target still has no Share Extension or widget dependencies, so this does not enable an application-group capability. Xcode resolves the new identity for Debug, Profile, and Release; the official Runner continues to resolve as `io.ente.frame` with its original entitlements. Current build and launch instructions use the new identity and explicitly treat the old bundle as a separate, non-migrating application.

Task 1.2 registered the exact explicit bundle identifier under Cytech with no additional Apple capabilities. This establishes the native identity needed by later distribution-certificate and Ad Hoc profile tasks without granting push notifications, application groups, associated domains, In-App Purchase, or extension services.

iOS treats the old and new bundle identifiers as unrelated applications. Their preferences, databases, keychain state, sessions, endpoint bindings, and caches do not migrate. Phase 1 deliberately installs the new app beside the old app and proves the cloud account before Phase 3 removes the legacy installation. Encrypted server media remains available after the owner signs in to the same Museum account.

The Cytech organization owns the new Apple App ID and its distribution lifecycle. Certificate loss or expiry is recoverable while authorized Cytech access and membership remain: issue a replacement distribution certificate and provisioning profile under the same team and App ID. Loss of team authorization, an unrenewed membership, or an unaccepted Apple agreement can stop new builds and profile renewal even when source and Firebase access remain available.

Task 1.1 confirmed through the live Apple Developer account that the selected organization membership and current agreement are active and that the owner is the Cytech Account Holder with access to certificates, identifiers, devices, profiles, keys, and App Store Connect. This supersedes the planning assumption that the owner held only an Admin role. The local Mac has valid development identities but no current Apple Distribution identity or usable Cytech provisioning profile, so later tasks must establish those assets explicitly rather than reusing stale local state.

Task 1.3 established a separate `Apple Distribution: Cytech Ltd` certificate and matching private key in the local macOS login Keychain. The active teammate-created distribution certificate remains untouched because its private key is not present locally. Local signing now uses the separately owned identity, whose public SHA-256 fingerprint is `8fcaf5f761acbcbeeae4710fb75370646071d8a905ac2a70ffeb46676c4a1e0c` and whose validity ends on 2027-07-17; the private key is not exported or committed.

### Ad Hoc device and privacy boundary

Every installable IPA embeds an Ad Hoc provisioning profile containing the devices authorized for that build. Firebase collects a tester's device identifier only after the tester accepts the invitation and installs the Firebase registration profile. The operator then registers that device with Apple, refreshes the provisioning profile, and rebuilds the IPA.

Task 1.4 retained the existing owner iPhone during Cytech's new-membership-year device-list review instead of consuming a new device slot. The portal device is enabled, and its identifier was matched privately to the paired, available physical iPhone. The identifier itself remains outside Git and written audit evidence; subsequent profile work refers only to one authorized owner device.

Task 1.5 generated manual Ad Hoc profile `Ente Photos Self-Hosted Owner Ad Hoc` for the explicit self-hosted App ID, the separately owned distribution certificate, and exactly one owner device. Local decoding verified a non-debug profile, exact application/team binding, one device, one certificate, UUID `a988a9d8-5e7e-43ef-9625-722e2fca0d3a`, and expiry on 2027-07-17. The embedded certificate has the same public SHA-256 fingerprint recorded in Task 1.3. The profile remains a local external signing input and is not committed because it embeds the private device list and team identifier.

The repository, release notes, manifests, receipts, and committed screenshots never contain tester emails or device identifiers. Audit metadata records only the profile UUID/name as appropriate, expiry, application identifier, team, certificate fingerprint, and authorized-device count. Because an IPA necessarily embeds its provisioning profile, every recipient is trusted with the profile's device list; the channel remains a small closed beta rather than a public download.

Strict immutable versioning applies: every changed IPA receives a higher `CFBundleVersion`, including a rebuild whose only functional change is an expanded provisioning profile. The publisher never assigns multiple IPA hashes to one application build identity. Disabling an Apple device does not reclaim the annual device slot and is not treated as immediate revocation of an already installed application.

### Risk-first release construction

Phase 1 proves the highest-risk Apple dependencies before Firebase tooling is built:

```text
Cytech authorization
        |
        v
explicit App ID -> distribution certificate -> owner device -> Ad Hoc profile
        |                                                     |
        +-------- self-hosted target / archive export --------+
                              |
                              v
                    audited owner-only IPA
                              |
                              v
                 side-by-side owner verification
```

The existing guarded configurable iOS wrapper remains the single application build entry point. Its `--adhoc-preflight` mode validates explicit local team/profile, expected-device-count, version/build, and external output-path inputs without invoking Flutter or Xcode. Its `--adhoc` mode repeats those checks, configures the locked Flutter release, creates the manually signed archive, generates ephemeral Xcode 26 `release-testing` export options, and exports exactly one IPA. The validated profile is installed only into Xcode's local cache; the Team ID, device identifiers, profile, private key, export options, archive, and IPA remain outside Git. The command does not request Xcode provisioning updates or device registration and never overwrites output.

The first real archive exposed that Xcode command-line `PROVISIONING_PROFILE_SPECIFIER`, `CODE_SIGN_*`, and `DEVELOPMENT_TEAM` settings propagate into every workspace target, including CocoaPods targets that must not receive profiles. The self-hosted xcconfig now owns default automatic-development values through `SELF_HOSTED_*` indirection. Ad Hoc archive commands override only those custom settings, so `SelfHostedRunner` receives the manual profile, exact certificate, and Cytech team while Pods retain their normal unsigned framework settings.

Task 1.8 inspected the final IPA rather than trusting the build arguments. Baseline `1.3.59` (`2159`) contains the intended private Museum origin as an exact Flutter AOT string, one `me.vanton.ente.photos.selfhosted` application, no extensions, and arm64 across all 103 Mach-O files. The profile and signed entitlements are non-debug, bind privately to the exact application and Cytech team, authorize one device, and omit push, application-group, associated-domain, and iCloud capabilities. Deep code-signature and ZIP verification pass; the profile and signing leaf certificate match the pinned public fingerprint and remain valid through 2027-07-17. The 88,632,015-byte IPA has SHA-256 `b4996440a95079b082cc45ca51f707297a9749b41ad6e61074d0fda6b42266fe` and remains unpublished in the private baseline-artifact directory for Task 1.9.

Task 1.9 installed that exact audited IPA on the owner iPhone as a clean, independent application while retaining the legacy bundle as a pause-safe rollback path. The new app exposed the compiled Museum origin before credentials were entered, then authenticated to the intended local account and completed a foreground encrypted upload/download round trip. A forced process restart preserved the account, server binding, library, and readable media. The final installed-app inventory still contained both bundle identities, so Phase 1 proved the Apple signing and application-state boundary without removing the known-good legacy installation or publishing through Firebase.

### Two-stage Firebase release pipeline

After the manual risk proof, V1 separates signing from publication:

```text
pushed source commit
        |
        v
isolated clean checkout -> guarded archive/export -> signed Ad Hoc IPA
        |                                              |
        +--------- identity / endpoint / profile ------+
        |
        v
external read-only IPA + preparation manifest
        |
        v
guarded publisher -> re-audit -> typed confirmation -> Firebase
        |                                                   |
        v                                                   v
external receipt                                  trusted-ios-testers
                                                          |
                                                          v
                                      register device -> refreshed profile
                                                          |
                                                          v
                                      higher-build-number IPA and update
```

Preparation builds from an isolated checkout of one committed source reachable from the public fork's `origin` remote. This keeps the living tracker accurate in the primary checkout without allowing uncommitted files into a release. The command strips Firebase and unrelated cloud credentials from the build environment, uses only explicit local signing inputs, deletes stale build output, and atomically writes a collision-resistant read-only IPA/JSON pair outside Git. Its manifest records at least:

- IPA absolute path, size, and SHA-256;
- source commit, fork remote, exact AGPL commit URL, and clean-checkout evidence;
- bundle identifier, version, and `CFBundleVersion`;
- compiled configurable default HTTPS origin;
- architecture and release/debug state;
- application identifier and Apple team;
- embedded profile identifier, expiry, and authorized-device count without device identifiers;
- signing certificate public fingerprint and validity;
- archive/export and preparation tool schema versions.

Publication consumes only the immutable manifest/IPA pair. It re-hashes and re-inspects the IPA, checks the local receipt ledger for a strictly increasing build number, verifies the Firebase iOS registration and `trusted-ios-testers`, presents the complete target summary, and requires release-specific typed confirmation. It never invokes Xcode, Flutter, archive export, a certificate private key, or a provisioning-profile update. It repeats its audits after confirmation and preserves a read-only success receipt or a distinct partial-attempt record if Firebase may have changed before failure.

Firebase is a delivery channel only. The iOS app gains no Firebase runtime SDK, Analytics, Crashlytics, Google service configuration, or in-app updater. Release notes contain the exact public AGPL source commit and build-instruction link but no private server name, tester identity, device identifier, credential, invite, or recovery material.

Task 2.1 registered `me.vanton.ente.photos.selfhosted` as the sole iOS application in the existing self-hosted Firebase project, with display name `Ente Photos Self-Hosted iOS`. A post-creation inventory independently matched the platform, display name, bundle, and returned Firebase App ID. The publication binding lives only in `/Users/vanton/projects/ente-ios-toolchain/firebase/distribution.env`; its parent directory is mode `700`, the file is mode `600`, and the App ID is absent from Git. No `GoogleService-Info.plist` or runtime configuration was generated because later publication commands need only the local project/App-ID binding.

Task 2.2 created the dedicated Firebase App Distribution group `Trusted iOS Testers` with stable alias `trusted-ios-testers`. The pre-existing Android group remains separate. The one established project-side owner tester was reused privately rather than copied into source or documentation, and a filtered Firebase query verified that the iOS group contains exactly that member. Group membership alone grants access only to future Firebase deliveries; it does not change Apple device authorization, Tailscale access, Museum authentication, or either installed application.

Task 2.3 implemented the preparation half of the two-stage pipeline. `prepare_self_hosted_ios_release.sh` resolves `HEAD`, requires it to be reachable from a local `origin/*` ref, and refuses when the guarded build or preparation entry points differ from that pushed commit. It builds inside a temporary detached worktree, so unrelated edits in the primary checkout cannot enter the release and do not force the living tracker to be committed prematurely. The tool owns and removes its archive/export workspace, injects the explicit release inputs into an environment stripped of Firebase and Google cloud credentials, and never invokes Firebase.

Tasks 2.6 and 2.7 completed the clean-source generation contract. Before building, preparation resolves the committed Flutter lockfile; generates shared and Photos localizations; runs the repository's official `cargo codegen frb`; and runs filtered shared and Photos builders for the ignored Rust-API Freezed outputs plus the tracked Photos model outputs that the builder otherwise treats as stale. It requires every FRB output, both ignored Freezed outputs, both localization entrypoints, and every safely named locale file imported by those entrypoints. Only toolchain and cache paths enter the generation environment. A final Git-clean check proves the generators neither consumed primary-checkout output nor changed tracked source, and manifest contract `3` records separate Rust- and Dart-generation provenance for publication.

The exported IPA is independently treated as untrusted input. Preparation verifies ZIP safety, the one extension-free self-hosted application, exact bundle/version and compiled HTTPS origin, signed application/team identity, non-debug core-only entitlements, device-scoped profile and authorized-device count, pinned currently valid distribution certificate, code-signature structure, and arm64 on every Mach-O file. It restricts the external release directory to mode `0700`, copies the audited bytes into a staging directory, re-hashes them, writes a schema-versioned JSON manifest, makes both files mode `0444`, and finalizes them with no-overwrite hard links. Any collision or incomplete finalization fails closed and removes the partial public pair. The manifest records counts and public release evidence but never device identifiers; the IPA necessarily retains Apple's embedded private device list and remains restricted to trusted recipients.

Task 2.4 implemented the publication half as a separate command that accepts only the preparation manifest. It requires the IPA and manifest to remain regular, read-only siblings in their mode-`0700` external directory; validates every schema, source, build, iOS, profile, certificate, and signature field; re-hashes both files; and repeats the full native IPA audit. It then validates the exact active Firebase iOS bundle registration, pins `trusted-ios-testers`, generates release notes containing one exact AGPL commit URL and build-guide link, and checks the mode-`0700` success-receipt ledger for a strictly increasing `CFBundleVersion`.

Preflight stops after those read-only checks. Publication requires `PUBLISH <release-id>` exactly, then repeats the file load/hash/audit, version ledger, and Firebase app/group checks immediately before the only mutating subprocess. The Firebase invocation has one fixed App ID, group alias, and generated notes file; Firebase, Apple, signing, and unrelated cloud credentials are removed from child environments. A complete Firebase response finalizes one mode-`0444` success receipt. A nonzero result, process-start failure, or nominal success without all release references finalizes a separate partial-attempt record and instructs the operator to reconcile Firebase before retrying. Only success receipts advance the build ledger.

Task 2.8 added a no-upload recovery path for the real case where Firebase CLI returned exit `0` and JSON success after creating the release but omitted every reference required by the receipt contract. Reconciliation consumes the preserved immutable attempt plus an immutable response from Firebase's official read-only release-list API, then repeats the IPA, app, group, ledger, notes, version/build, creation-window, and reference checks before writing the ordinary success receipt. It hashes and preserves both evidence inputs and records `noUploadPerformed: true`; it cannot invoke the distribute operation. Future publication calls use Firebase's reference-bearing text output rather than JSON-only status.

Task 3.1 prepared and published `1.3.59` (`2160`) from pushed source. The ambiguous initial response was never retried: after Task 2.8 reached the public fork, one real reconciliation bound the existing Firebase release to its immutable artifact, manifest, partial attempt, official API evidence, and unique read-only success receipt. Task 3.2 then proved the owner-facing channel on a physical iPhone. Firebase profile registration and installation delivered the audited bundle, and the installed app authenticated to the intended private service, completed uploads in both directions between iPhone and local web app, decrypted the remotely introduced media, and retained account, server, and library state across a forced restart.

Task 3.3 closed the side-by-side rollback period only after the owner confirmed possession of the local account password and recovery key and the replacement's cloud copy had been proven from both the iPhone and local web app. The private device inventory found the legacy bundle already absent and only the verified Firebase build present, so retirement required no uninstall mutation and no app-local state migration.

Task 3.4 proved the forward-update publication path with `1.3.59` (`2161`). Local and private Museum/storage checks returned healthy before preparation. The first two isolated attempts failed before artifact creation because the operator command did not carry the already documented pinned Flutter/Dart binaries and rustup-first PATH; restoring the complete proven environment allowed clean dependency resolution, source generation, archive/export, and audit from pushed commit `d61b831c33`. The immutable artifact retained the bundle, configurable server policy, one-device Ad Hoc scope, distribution certificate, arm64-only core target, and zero extensions. A non-mutating Firebase preflight passed, one release-specific confirmation authorized one upload, and the normal read-only success receipt bound the created release and all three Firebase references to the exact manifest and IPA hashes without a partial attempt.

Task 3.5 installed that Firebase release over the existing owner baseline. Private device inventories established build `2160` immediately before installation and build `2161` afterward under the same bundle identity. The application opened without reauthentication or server reconfiguration, retained the existing cloud library, completed a fresh controlled encrypted media round trip in both directions between the iPhone and local web app, and preserved the account, server binding, library, and readable media after a forced process restart. This proves the guarded higher-build publication is an in-place update rather than a clean installation.

### Tester access and state transitions

A tester requires four independent grants:

1. Firebase invitation and membership in `trusted-ios-testers`;
2. an Apple-registered iPhone present in the embedded Ad Hoc profile;
3. Tailscale access to the private Museum and object-storage routes;
4. an individual Museum account and its own recovery material.

On current iOS versions, an Ad Hoc tester also enables Developer Mode. The operator verifies Museum `/ping` and object-storage health before publication and verifies the same private routes from the tester device before blaming the application.

Offboarding handles each system separately. Firebase removal prevents future group delivery but does not uninstall a build. Apple device/profile changes are not an immediate per-device kill switch for an already installed IPA. Tailscale access and the Museum account therefore remain the effective private-server controls and are revoked according to separate network and data-retention decisions.

### Failure visibility, rollback, and constraints

Preparation and publication fail with actionable local messages. Evidence is divided intentionally: manifests and receipts prove release bytes, Firebase proves delivery status, the installed application's signature/profile and visible server/version prove device state, and Museum logs prove account and media traffic. V1 adds no remote telemetry or performance objective because distribution does not change runtime behavior.

| Failure | Detection | Recovery |
|---|---|---|
| Cytech authorization, agreement, or membership unavailable | Task 1.1 account audit or Apple signing failure | Stop before App ID registration or release work; restore organization authorization rather than falling back silently to Personal Team. |
| Wrong or unavailable bundle identifier | Apple registration check or final IPA audit | Stop before publication; use only the explicitly approved identity. Do not silently create a variant. |
| Wrong team, entitlement, certificate, profile, or device set | Final IPA/profile/signature audit | Discard the IPA, correct Apple state, increase the build number if bytes will be redistributed, and prepare again. |
| Expired or near-expiry signing asset | Profile/certificate audit and runbook warning | Renew or replace the certificate/profile under Cytech, rebuild with a higher build number, and publish before installed builds become unusable. |
| Modified or stale IPA | Manifest hash, metadata, or clean-source mismatch | Discard the artifact and prepare again from the intended pushed commit. |
| Firebase fails after upload may have started | Nonzero result, missing references, or partial-attempt record | Preserve evidence, inspect Firebase, and reconcile before any retry. Never assume failure means no mutation. |
| New tester is absent from the embedded profile | Firebase registration state and profile device-count/device audit | Register the device, refresh the profile, increase the build number, prepare, and publish a distinct IPA. |
| Bad application release | Device report, signature/version evidence, or Museum logs | Build the last known-good source with a higher build number and publish it as a forward rollback. |
| Lost distribution private key | Local key audit | Issue a new authorized Cytech distribution certificate and profile; keep the App ID and team stable. |
| Lost Cytech access or expired membership | Apple portal/Xcode account state and profile-renewal failure | Restore organization access or membership. Do not move the identity to another team implicitly. Existing profile validity is a finite pause window, not durable recovery. |
| Museum, object storage, or Tailscale unavailable | `/ping`, storage health, device route, Docker, and Museum logs | Restore the private server/network path; do not publish an unchanged app for an infrastructure outage. |

Primary external references are Apple's [device registration limits](https://developer.apple.com/help/account/devices/devices-overview), [Developer Program roles](https://developer.apple.com/help/account/access/roles), and [membership comparison](https://developer.apple.com/support/compare-memberships/), plus Firebase's [iOS device-registration flow](https://firebase.google.com/docs/app-distribution/register-additional-devices) and [tester setup](https://firebase.google.com/docs/app-distribution/get-set-up-as-a-tester). TestFlight remains an explicitly rejected alternative; its current behavior is documented in Apple's [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).

---

## 4. Future work / out-of-scope

> Single source of truth for everything that is NOT in V1. Items move into V1 only with explicit owner approval and a decision-log entry.

| Item | Status | Why |
|---|---|---|
| Register, provision, publish for, and verify one non-owner tester (Tasks 3.6–3.8) | V1.1 backlog | The owner chose to finish the proven owner baseline/update path now and defer the real additional-device workflow until a non-owner tester and iPhone are available. |
| Automate archive preparation or Firebase publication in continuous integration | V1.1 backlog | V1 first proves Apple signing, immutable preparation, and publication locally without introducing remote Cytech or Firebase credentials. |
| Add proactive scheduled notifications for certificate or profile expiry | V1.1 backlog | V1 exposes validity during every audit and documents operator checks; remote scheduling requires a separate notification and credential design. |
| Preserve a durable binary archive beyond local immutable artifacts and Firebase retention | V1.1 backlog | V1 retains prepared IPAs, manifests, and receipts locally; off-machine retention requires a separate storage and access decision. |
| Add self-hosted Share Extension, widgets, push notifications, or application groups | V1.1 backlog | The existing core-only target deliberately avoids Ente-owned capabilities and additional provisioning surfaces. |
| Use external or internal TestFlight | Out of scope | Firebase Ad Hoc avoids external Beta App Review access to the private Tailscale-only backend and avoids granting testers App Store Connect roles. |
| Publish through the App Store, Apple Business Manager Custom Apps, Enterprise distribution, or public web download | Out of scope | V1 is a small invitation-only beta for explicitly registered devices. |
| Move or duplicate the Apple identity under a personal paid team | Out of scope | The owner selected Cytech organization ownership for this initiative; cross-team continuity needs a separate legal and technical decision. |
| Migrate app-local state from `com.vanton1.ente.photos.selfhosted` | Out of scope | The owner accepted a fresh new-identity login and cloud recovery rather than cross-bundle database, keychain, or preference migration. |
| Reuse a `CFBundleVersion` for a provisioning-profile-only rebuild | Out of scope | Strict immutable versioning gives every changed IPA one unique build identity and receipt. |
| Store tester emails, device identifiers, signing assets, profiles, or Firebase bindings in Git | Out of scope | Those values belong to Apple, Firebase, or private operator storage and would expose identities or credentials in the public fork. |
| Add Firebase Analytics, Crashlytics, App Distribution runtime SDK, or in-app update prompts | Out of scope | Firebase is a delivery channel only; runtime Google services would change application privacy and behavior. |
| Decide public Ente branding or trademark rights | Out of scope | This plan covers a closed beta and makes no determination about broader public distribution or branding permission. |
| Change the Android Firebase tracker or resume its paused physical-device task | Out of scope | Android Task 3.1 remains a separate paused initiative until the Android device is available. |

**Status values:**
- `V1.1 backlog` — deferred but planned for the next milestone.
- `Out of scope` — will not be done in this initiative; distinct from deferred work.

---

## 5. Decision log

> Append-only. Newest entries stay on top. If a decision changes, add a new entry instead of rewriting history.

### 2026-07-19 — Defer non-owner tester onboarding to V1.1

**Decision:** Move Tasks 3.6–3.8—non-owner device registration, profile expansion and publication, and tester installation verification—to the V1.1 backlog. Complete V1 after the verified owner baseline/update path and the as-built architecture companion.

**Why:** The owner chose to skip the non-owner device step and no real tester iPhone is currently available. Tasks 3.7 and 3.8 cannot produce valid evidence without the device identifier and Apple authorization established by Task 3.6; deferring the complete dependency chain keeps the release record honest while preserving the workflow for later execution.

**Alternatives considered:** Leave V1 blocked indefinitely on an unavailable tester; create a profile or publication without a real additional device, which would not prove tester installation; or remove the workflow entirely, which would discard useful future scope. Deferral preserves a pause-safe backlog without claiming unperformed acceptance evidence.

### 2026-07-19 — Reconcile JSON-only Firebase success without re-uploading

**Decision:** Preserve the immutable partial-attempt record, capture a private immutable response from Firebase's official read-only release-list API, and add a guarded reconciliation mode that re-audits all local and Firebase bindings before writing the normal success receipt without an upload. Make future distribute calls request Firebase's reference-bearing human-readable output instead of JSON-only status.

**Why:** The installed Firebase CLI returned exit `0` and `{"status":"success"}` after creating and distributing build `2160`, but omitted the console, tester, and binary references required by the receipt contract. Official API evidence supplies those references and independently proves the exact app/version/build/source-notes release. Binding both immutable records retains fail-closed provenance while preventing an unsafe duplicate upload.

**Alternatives considered:** Retry the IPA, which could duplicate or re-notify an already successful release; trust status alone or fabricate URLs, which would weaken the receipt; or accept a console screenshot/manual note, which is mutable and cannot be machine-bound to the prepared artifact. None preserves the existing audit and increasing-build ledger as strongly as official immutable evidence plus no-upload reconciliation.

### 2026-07-19 — Regenerate every ignored compile-time source inside the release checkout

**Decision:** Resolve the committed Flutter lockfile, generate both localization packages, run the official FRB generator, then run filtered shared and Photos builders inside the detached release checkout. Require every compile-critical ignored output and localization import, include the tracked Photos builder outputs needed to prove byte stability, require final Git cleanliness, and make the publisher reject manifests without separate Rust and Dart provenance.

**Why:** A pushed Git commit intentionally omits generated FRB, Freezed, and localization files that the iOS archive still needs. Rebuilding the entire compile-time source closure from that commit makes the prepared IPA reproducible without trusting mutable files from the primary checkout. Explicit tracked-output filters and the final cleanliness check also catch generator/version drift before signing or publication.

**Alternatives considered:** Copy ignored files from the primary checkout, which cannot establish commit provenance; commit every ignored output, which would change repository policy and add generated churn; or run broad builders with deletion enabled or incomplete filters, which real clean-checkout trials proved can delete tracked Photos outputs. The filtered, Git-clean contract preserves both reproducibility and the repository's generated-file policy.

### 2026-07-18 — Generate ignored Rust bindings from release source

**Decision:** Make the guarded iOS preparer run the repository's official `cargo codegen frb` command inside its detached pushed-source checkout, require every shared and Photos generated binding before the build, recheck tracked cleanliness afterward, and make the upgraded publisher reject manifests without this explicit provenance.

**Why:** Flutter-Rust-Bridge outputs are intentionally ignored, so a clean worktree cannot compile by merely reproducing tracked files. Regenerating them from the selected commit preserves source provenance and keeps the release pipeline reproducible without adding generated code to Git or trusting mutable output from the primary checkout.

**Alternatives considered:** Copy the ignored bindings from the primary checkout, which cannot prove they correspond to the selected commit, or commit generated outputs, which would change the repository-wide source policy and create high-churn generated diffs. Neither is needed when the repository already owns a canonical generator.

### 2026-07-18 — Publish a fresh guarded baseline instead of adopting build 2159

**Decision:** Push the completed release tooling, prepare `1.3.59` build `2160` from that exact pushed commit, and publish its immutable IPA/manifest pair as the first guarded Firebase iOS baseline. Keep the already installed `2159` IPA as Phase 1 owner-validation evidence and do not alter either installed application during publication.

**Why:** Build `2159` was created and audited before the immutable preparation command existed, so it has no preparation-produced manifest or clean detached-worktree evidence. Creating a new higher build preserves the rule that one build identity maps to one IPA hash, source commit, manifest, and Firebase receipt without falsifying provenance.

**Alternatives considered:** Add an import schema and publisher path for the legacy IPA, which adds another tooling task and a weaker provenance class, or upload `2159` directly with Firebase CLI, which bypasses the guarded pipeline and receipt ledger. Neither is justified when a fresh signed build can preserve the established contract.

### 2026-07-18 — Separate Firebase publication behind a two-pass confirmation gate

**Decision:** Publish only through a command that consumes an immutable preparation manifest, completes a non-mutating audit/Firebase preflight, requires `PUBLISH <release-id>`, repeats all mutable-input and destination checks, and records a read-only success or partial-attempt receipt around one Firebase distribute call.

**Why:** IPA construction needs Apple signing authority, while delivery needs Firebase authority; combining them would expose signing inputs to an avoidable network mutation and make ambiguous upload failures difficult to reconcile. Two audit passes close the human-confirmation race, the external success ledger makes increasing build numbers enforceable, and partial records preserve evidence when Firebase may have changed despite unusable CLI output.

**Alternatives considered:** Invoke Firebase directly after archive export, which couples signing and delivery credentials; use the Firebase CLI manually, which does not bind the uploaded bytes to the prepared manifest or receipt ledger; or automate publication in CI, which would introduce remote Apple/Firebase credential custody before the local contract is proven.

### 2026-07-18 — Prepare releases from a detached pushed worktree

**Decision:** Let the preparation command tolerate unrelated primary-checkout dirt while requiring its critical entry points to match a `HEAD` commit reachable from `origin/*`, then build and audit inside a temporary clean detached worktree at that exact commit.

**Why:** The living tracker and paused Android note legitimately remain modified while iOS work proceeds, but release bytes must still come exclusively from reviewable fork source. A detached worktree gives the build the repository's exact committed dependency graph without copying primary dirt, avoids another network clone, and permits before/after cleanliness checks around the build and audit.

**Alternatives considered:** Require the primary checkout to be entirely clean, which would couple unrelated documentation and paused work to each release; build directly from a dirty primary checkout while hashing selected files, which leaves too many untracked inputs; or fetch a fresh clone for every release, which adds network availability and remote-race dependencies without stronger commit identity than the local pushed ref plus detached worktree.

### 2026-07-17 — Scope manual signing settings to SelfHostedRunner

**Decision:** Route code-sign identity, signing style, development team, and provisioning-profile selection through `SELF_HOSTED_*` variables consumed only by `SelfHosted.xcconfig`; the Ad Hoc wrapper overrides those variables instead of global Xcode build settings.

**Why:** The first real archive proved that global command-line provisioning settings propagate into CocoaPods targets, which correctly reject application profiles. Target-scoped indirection signs the application exactly while leaving Pods on their normal framework build settings, and it keeps private values outside project files.

**Alternatives considered:** Continue passing global Xcode settings, which cannot archive this workspace; edit generated CocoaPods settings, which is broad and regeneration-sensitive; or write the private team/profile into the Xcode project, which would leak local signing bindings into Git.

### 2026-07-17 — Pin the owner baseline to version 1.3.59 build 2159

**Decision:** Keep the source marketing version `1.3.59` and assign the new iOS owner baseline `CFBundleVersion` `2159`.

**Why:** Source and the Android baseline use `1.3.59` (`2158`), while the new iOS bundle has no prior Firebase release. Advancing one build number gives the distinct IPA bytes a unique identity and establishes the strictly increasing update sequence without inventing a new marketing release.

**Alternatives considered:** Reuse build `2158`, which would make different platform/source and IPA baselines share one build identity, or jump to an arbitrary much higher number, which adds no safety while consuming versioning headroom.

### 2026-07-17 — Keep iOS release inputs and evidence under one private local root

**Decision:** Use `/Users/vanton/projects/ente-ios-toolchain` outside Git, with `signing` for profiles, `baseline-artifacts` for Phase 1 archives/IPAs/logs, and later `prepared-releases` and `firebase-receipts` directories for guarded publication evidence.

**Why:** A dedicated owner-only root separates private Apple inputs and large release evidence from the public checkout and from the Android toolchain while giving later commands stable, reviewable path boundaries.

**Alternatives considered:** Leave profiles and IPAs in Downloads, where provenance and retention are unclear; store them under the Git checkout and risk accidental inclusion; or mix them into the Android toolchain root and blur platform-specific signing and recovery boundaries.

### 2026-07-17 — Separate Ad Hoc preflight from archive and export

**Decision:** Extend the existing guarded iOS wrapper with `--adhoc-preflight` and `--adhoc`, using explicit local signing/release inputs, pinned certificate validation, manual Xcode signing, and ephemeral Xcode 26 `release-testing` export options.

**Why:** The non-building preflight proves the high-risk local profile, certificate, private-key, identity, and output contract before an expensive archive. Repeating the same validation during export makes the operation reproducible without storing private Apple bindings in Git or allowing Xcode to mutate portal state.

**Alternatives considered:** Automatic signing or `-allowProvisioningUpdates` could download or change Apple state; a checked-in export-options plist would bind the public repository to a private team/profile; and Organizer-only export would leave the release operation dependent on undocumented GUI choices.

### 2026-07-17 — Align the non-entitled app-group placeholder with the new identity

**Decision:** Rename the self-hosted target's `CUSTOM_GROUP_ID` Info.plist placeholder to `group.me.vanton.ente.photos.selfhosted` while preserving the empty entitlement file and extension-free target.

**Why:** The shared Runner Info.plist interpolates this value even though the core-only target has no application-group entitlement. Keeping a legacy namespace in active self-hosted configuration would make the identity cutover incomplete and misleading; changing only the placeholder keeps configuration coherent without granting a capability.

**Alternatives considered:** Retain the stale legacy placeholder, remove the shared Info.plist key and risk affecting official targets, or register and enable a real application group. The first leaves conflicting active identity data, while the latter two broaden this target beyond the reviewed core-only design.

### 2026-07-17 — Pin the baseline Ad Hoc profile to one device and certificate

**Decision:** Use a manually generated owner-only Ad Hoc profile containing the explicit self-hosted App ID, the separately owned Cytech distribution certificate, and exactly one verified owner iPhone.

**Why:** A narrow manual profile makes the initial signing boundary explicit and auditable before Firebase delivery or tester onboarding. Its one-device and one-certificate contents match the Phase 1 owner baseline and avoid silently authorizing unrelated devices or signing identities.

**Alternatives considered:** Let Xcode automatically manage an opaque Ad Hoc profile, which weakens reproducibility, or include every registered device and distribution certificate preemptively, which broadens the baseline trust boundary without a current need.

### 2026-07-17 — Retain the existing owner iPhone registration

**Decision:** Complete Cytech's annual device-list review without removing the existing owner iPhone, then use that enabled device as the sole owner device for the initial Ad Hoc profile.

**Why:** A private comparison confirmed that the existing portal registration matches the paired physical iPhone intended for testing. Retaining it preserves the valid registration and avoids consuming a duplicate device slot.

**Alternatives considered:** Remove and attempt to re-register the same phone, which adds unnecessary Apple-state churn, or register another entry without comparing identifiers, which risks a duplicate or the wrong device in the provisioning profile.

### 2026-07-17 — Create a separate local Cytech distribution identity

**Decision:** Create a new Apple Distribution certificate and matching private key through Xcode for local Cytech signing, while leaving the active teammate-created distribution certificate untouched.

**Why:** The existing active portal certificate does not have an accessible private key on this Mac. A separately owned identity isolates key custody and revocation while enabling local Ad Hoc signing without depending on another operator.

**Alternatives considered:** Obtain and import the teammate's `.p12`, which would transfer private-key custody and share revocation impact, or ask the teammate to sign each release, which would add external coordination to every build.

### 2026-07-17 — Register the explicit App ID without capabilities

**Decision:** Register `me.vanton.ente.photos.selfhosted` as an explicit Apple App ID under Cytech with description `Ente Photos Self-Hosted` and no additional capabilities.

**Why:** The core-only self-hosted target has an empty entitlement set and excludes Ente's extensions, application groups, push notifications, and purchase capability. Registering only the identity keeps Apple state aligned with the reviewed target instead of granting unused services.

**Alternatives considered:** Reuse the legacy bundle identifier, register a wildcard identifier, or enable capabilities preemptively. Those choices conflict with the requested final identity, cannot express the exact distributable application, or broaden signing state without a V1 requirement.

### 2026-07-17 — Confirm the owner as Cytech Account Holder

**Decision:** Proceed with the Cytech organization ownership selected during planning. Treat the owner's live Account Holder role as the authorization for the closed beta and as full access to the Apple signing resources required by later tasks.

**Why:** The Apple Developer account showed an active organization membership, an accepted current program agreement, and access to Certificates, Identifiers, Devices, Profiles, Keys, and App Store Connect. The Account Holder finding is stronger than the earlier Admin-role assumption. The local machine has no Apple Distribution identity and no current Cytech profile, but those are expected deliverables of Tasks 1.3 and 1.5 rather than failures of membership authorization.

**Alternatives considered:** Seek approval from a different Account Holder or move the application to a separate personal membership. Neither is required after the live account audit.

### 2026-07-17 — Keep iOS distribution in a focused living document

**Decision:** Track the initiative in `living_docs/FirebaseIOSDistribution.md`, finish with `living_docs/FirebaseIOSDistributionArchitecture.md`, and place the operational runbook at `mobile/apps/photos/SELF_HOSTED_IOS_DISTRIBUTION_GUIDE.md`. Link existing mobile endpoint, iOS signing, Android Firebase, and build documents as companions.

**Why:** Apple certificates, devices, provisioning profiles, bundle ownership, and IPA installation form a distinct lifecycle from both runtime server selection and Android APK delivery. A focused tracker preserves the paused Android task and completed configurable-server history.

**Alternatives considered:** Merge iOS into the Android Firebase tracker, which would entangle paused device acceptance with Apple state; or reopen the completed configurable-server document, which would mix runtime and distribution concerns.

### 2026-07-17 — Give every changed IPA a higher build number

**Decision:** Require a strictly higher `CFBundleVersion` whenever IPA bytes change, including provisioning-profile expansion for a newly registered device.

**Why:** One build identity then maps to one IPA hash, manifest, Firebase publication, and receipt. This removes ambiguity during device onboarding, partial upload recovery, updates, and forward rollback.

**Alternatives considered:** Reuse the same version/build for profile-only exports, which Firebase can treat as the existing release and notify differently, or allow manual exceptions. Both make multiple binaries share one build identity and weaken the guarded ledger.

### 2026-07-17 — Use high-isolation task boundaries

**Decision:** Separate membership audit, App ID registration, certificate, device, profile, source rename, export tooling, artifact audit, Firebase registration, group creation, pipeline stages, publication, installation, cutover, update, tester provisioning, and documentation into individual S/M tasks.

**Why:** These steps mutate different external systems or review different security boundaries. Small tasks make Apple and Firebase changes auditable and preserve a safe stop point after every external mutation.

**Alternatives considered:** A balanced tracker with fewer tasks or a compact tracker that merged signing, code, Firebase, and device changes. Both reduce checkpoints at the cost of larger and harder-to-reconcile failure domains.

### 2026-07-17 — Sequence Apple risk before Firebase tooling

**Decision:** Verify Cytech authorization, register the identity, establish Ad Hoc signing, and prove a side-by-side owner IPA before building Firebase preparation/publication tooling or removing the legacy app.

**Why:** Apple team access, explicit App ID availability, distribution certificates, registered devices, and profiles are the blocking unknowns. Proving them first avoids implementing a publication path around invalid signing assumptions and keeps the working legacy app available.

**Alternatives considered:** Build a vertical Firebase slice immediately, which would combine every risk, or implement tooling first, which could encode assumptions before Cytech signing is proven.

### 2026-07-17 — Use the Cytech organization team

**Decision:** Register and distribute `me.vanton.ente.photos.selfhosted` under the Cytech Ltd Apple Developer Program organization team, subject to Task 1.1 confirming active membership, agreements, permissions, and Account Holder authorization.

**Why:** The owner selected the existing organization team rather than purchasing a separate personal membership. The current Admin role is expected to support identifiers, certificates, profiles, and devices once organization readiness is verified.

**Alternatives considered:** Enroll in an individual paid program for independent ownership, or continue free Personal Team signing. The former adds a separate membership; the latter supports owner development testing but not the selected Ad Hoc closed beta.

### 2026-07-17 — Deliver iOS through Firebase Ad Hoc distribution

**Decision:** Use Apple Ad Hoc signing with Firebase App Distribution, a dedicated `trusted-ios-testers` group, private device registration, and no Firebase runtime SDK.

**Why:** This mirrors the Android delivery experience while keeping the Tailscale-only backend outside Apple Beta App Review. It supports a small known group without granting testers App Store Connect roles.

**Alternatives considered:** External TestFlight offers easier installation but its first external build requires review and an accessible backend or demo mode. Internal TestFlight avoids external testing but makes every tester an App Store Connect user. Direct IPA delivery retains the same Ad Hoc device burden with a worse invitation and update experience.

### 2026-07-17 — Ship a thorough closed-beta V1

**Decision:** Include identity replacement, audited preparation and publication, owner baseline and update, one non-owner installation, onboarding/offboarding/recovery documentation, and an as-built architecture companion.

**Why:** A single owner build would not prove recurring updates, device registration, profile expansion, or real tester operations. The selected scope covers the predictable first-use and recovery paths without introducing continuous integration or public distribution.

**Alternatives considered:** A narrow one-build proof would leave updates and tester recovery unverified. A strategic V1 with remote automation would expand Cytech and Firebase credential handling before the local contract is proven.

### 2026-07-17 — Replace the self-hosted iOS bundle identity

**Decision:** Change only `SelfHostedRunner` from `com.vanton1.ente.photos.selfhosted` to `me.vanton.ente.photos.selfhosted`, install it beside the old application for validation, and later remove the old application without local-state migration.

**Why:** The owner wants the final personal namespace while preserving official Ente targets. Side-by-side validation makes the otherwise fresh-install identity change pause-safe, and Museum cloud data can be recovered through the account.

**Alternatives considered:** Keep the old bundle identifier, rename official Ente targets, or attempt cross-bundle local database/keychain migration. These conflict with the requested identity, broaden unrelated targets, or add a high-risk migration that the owner does not need.

### 2026-07-17 — Optimize for a small trusted group

**Decision:** Design for the owner and a few known, mostly nontechnical testers who each use their own Firebase, Tailscale, and Museum identities.

**Why:** The goal is private recurring beta delivery rather than owner-only sideloading, organization-wide management, or public availability. The framing requires understandable invitations and updates but permits explicit device registration and hands-on offboarding.

**Alternatives considered:** Owner-only durable installation would omit human onboarding, while a company-managed or public audience would require broader policy, support, review, and branding decisions.

---

## 6. Open questions

_Add new questions as they arise. Move resolved questions to §5 once answered, with the resolution as the decision._

- What minimum remaining certificate/profile validity should publication require rather than merely warn about?

---

## 7. Lessons learned

> Populated at the end of each phase. Surprises, anti-patterns discovered, things to do differently next time.

### Phase 1 — Prove Apple signing and the owner baseline

- Verify the Apple chain in dependency order—organization authority, explicit App ID, locally controlled distribution identity, retained device, then manual Ad Hoc profile—before attempting a release archive. This made portal mistakes and missing private-key ownership fail early.
- Command-line Xcode signing settings can leak from the application target into CocoaPods. Target-scoped custom xcconfig indirection is the reliable boundary for manually signing only `SelfHostedRunner`.
- Treat the exported IPA as untrusted until its bundle, compiled endpoint, architectures, entitlements, embedded profile, certificate, signature, and ZIP structure are independently audited. Build arguments alone are not release evidence.
- A new bundle identifier provides a strong rollback boundary but deliberately carries no local app state. Showing the selected server before login, reauthenticating to the same Museum account, and proving encrypted media plus restart persistence made that clean-install boundary observable before the legacy app was touched.

### Phase 2 — Guard Firebase delivery and document operations

- Keep preparation and publication separate. A detached pushed worktree creates and audits immutable bytes without Firebase credentials, while the publication command can only re-audit and deliver the exact read-only pair after a release-specific confirmation.
- Treat Firebase's successful process exit as insufficient evidence. Missing release references are operationally ambiguous, so preserve a partial-attempt record and reconcile the console before any retry.
- iOS tester onboarding is a two-release loop: the first invitation collects the iPhone identifier, then Apple registration and a refreshed embedded profile make a later IPA installable. Requiring a higher build number even for a profile-only change keeps one build identity mapped to one IPA and receipt.
- Distribution, device authorization, launch permission, network access, and encrypted account access are independent. The operator guide must handle Firebase, Apple profiles, Developer Mode, Tailscale, and Museum separately during both onboarding and offboarding.

### Phase 3 — Prove owner delivery, update, and recovery behavior

- Prove the Apple authorization chain before involving Firebase. A valid organization, explicit App ID, locally controlled distribution identity, registered device, and audited Ad Hoc profile turn Firebase into a delivery concern instead of a signing-debugging concern.
- The same bundle identity plus a strictly increasing build number produced a real in-place update: build `2161` replaced `2160` while retaining authentication, the selected local server, the encrypted library, and readable media across a forced restart.
- Treat an incomplete Firebase success response as unknown state, not failure. Preserve the attempt, inspect the official read-only release state, and reconcile the exact release; never upload blindly a second time.
- Carry the complete pinned Flutter/Dart and rustup-managed Rust/Cargo environment into every isolated release invocation. Interactive-shell defaults can select newer incompatible tools even when the repository lockfiles are correct.
- Keep device authorization, Firebase delivery, Developer Mode, private-network access, and Museum account access as independent checks. A green result in one system does not diagnose or authorize the others.
- When physical acceptance evidence is unavailable, defer the whole dependent chain. Moving non-owner registration, reprovisioning/publication, and installation together to V1.1 is more accurate than claiming tester support from owner-only evidence.
