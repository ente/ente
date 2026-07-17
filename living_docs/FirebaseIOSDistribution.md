# Firebase iOS Distribution for the Self-Hosted Photos App

**Status:** Living document. Updated at the end of every task.
**Started:** 2026-07-17
**Owner:** vanton
**Planning doc:** n/a
**Companion docs:** `living_docs/ConfigurableSelfHostedMobileServer.md`, `living_docs/ConfigurableSelfHostedMobileServerArchitecture.md`, `living_docs/LockedSelfHostedIOS.md`, `living_docs/FirebaseAndroidDistribution.md`, `mobile/apps/photos/SELF_HOSTED_BUILD_GUIDE.md`, `mobile/apps/photos/SELF_HOSTED_IOS_DISTRIBUTION_GUIDE.md` (planned), `living_docs/FirebaseIOSDistributionArchitecture.md` (planned)

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
| 1 | 1.8 | Export and audit the baseline IPA | M | ⚪ not started | Verify the final IPA's bundle, version/build, compiled server, architecture, non-debug state, entitlements, embedded profile, Cytech team, certificate fingerprint, expiry, archive integrity, and SHA-256. |
| 1 | 1.9 | Verify the new app side by side on the owner's iPhone | M | ⚪ not started | Install the Ad Hoc IPA while retaining the legacy-bundle app, sign in to the intended Museum account, and prove foreground encrypted upload/download plus restart persistence. |
| 2 | 2.1 | Register the iOS application in Firebase | S | ⚪ not started | Add the exact new bundle identifier to the existing self-hosted Firebase project; keep the Firebase iOS App ID as local publication configuration rather than normal application runtime configuration. |
| 2 | 2.2 | Create the dedicated iOS tester group | S | ⚪ not started | Create stable group alias `trusted-ios-testers` and add the owner privately; keep tester identities out of Git. |
| 2 | 2.3 | Add an immutable IPA preparation command | M | ⚪ not started | Build from an isolated clean checkout of a pushed source commit, audit the final Ad Hoc IPA, and atomically preserve a read-only IPA plus manifest outside Git without invoking Firebase. |
| 2 | 2.4 | Add a guarded Firebase iOS publication command | M | ⚪ not started | Consume only the immutable manifest/IPA pair, re-audit identity and signing, pin the Firebase app and group, enforce increasing build numbers, require typed confirmation, and preserve success or partial-failure receipts. |
| 2 | 2.5 | Document iOS releases, onboarding, and recovery | S | ⚪ not started | Add an operator runbook for Apple device registration, profile refresh, Firebase delivery, Developer Mode, Tailscale, Museum accounts, updates, offboarding, expiration, credential loss, and rollback. |
| 3 | 3.1 | Publish the audited iOS baseline through Firebase | M | ⚪ not started | Run the guarded preflight and publication path for the exact baseline IPA, reconcile Firebase and the receipt, and do not alter either installed iOS application. |
| 3 | 3.2 | Verify the owner's Firebase installation | S | ⚪ not started | Accept the Firebase invitation, install the baseline through the tester experience, and repeat server, account, encrypted media, and restart checks while the legacy app remains available. |
| 3 | 3.3 | Retire the owner's legacy iOS installation | S | ⚪ not started | Confirm cloud backup and authentication recovery material, then remove `com.vanton1.ente.photos.selfhosted`; do not attempt to migrate its app-local state. |
| 3 | 3.4 | Prepare and publish an in-place iOS update | M | ⚪ not started | Increase `CFBundleVersion`, keep bundle ID, Cytech team, endpoint policy, and signing/profile validity stable, then prepare and publish through the guarded commands. |
| 3 | 3.5 | Verify state retention across the Firebase update | M | ⚪ not started | Install over the new-identity baseline and confirm the account, active server binding, cloud library, controlled upload/download, and restart persistence remain intact. |
| 3 | 3.6 | Register one non-owner tester device | S | ⚪ not started | Collect one invited tester's iPhone identifier through Firebase, register it in Apple privately, and keep tester identity and device data outside Git. |
| 3 | 3.7 | Refresh provisioning and publish a tester-compatible build | M | ⚪ not started | Create a profile containing the authorized tester device, rebuild from clean source with a higher `CFBundleVersion`, re-audit the changed IPA, and publish it as a distinct immutable release. |
| 3 | 3.8 | Verify a non-owner tester's installation | M | ⚪ not started | Confirm Firebase acceptance, Developer Mode, Tailscale access, an individual Museum account, installation, and one controlled encrypted upload/download without storing tester evidence in Git. |
| 3 | 3.9 | Document the as-built iOS distribution architecture | S | ⚪ not started | Write the settled Apple/Firebase/Tailscale/Museum trust boundaries, signing and release flows, state transitions, failure recovery, and maintenance checklist for a future operator. |

**Legend:** ⚪ not started · 🟡 working · 🟢 done · 🔴 blocked / needs decision
**Size:** XS · S · M · L · XL (never days or weeks).

One task = one row = one reviewable step. Mark a row 🟡 working before starting it and 🟢 done only after its acceptance evidence passes. Describe each task and wait for approval before implementation.

Task naming convention: `Task <phase>.<sub> — <short imperative title>`. If a commit is opened for a task, mirror that title.

---

## 2. Goal

Distribute pre-release builds of the configurable self-hosted Ente Photos iOS application to the owner and a small, trusted, mostly nontechnical group through Firebase App Distribution and Apple Ad Hoc provisioning. V1 is complete when the self-hosted target uses bundle identifier `me.vanton.ente.photos.selfhosted` under the Cytech Ltd Apple Developer Program team; the owner installs an audited Firebase baseline and then an in-place update; the previous `com.vanton1.ente.photos.selfhosted` installation is removed without app-local migration only after the replacement is proven; and one non-owner tester registers an authorized device, installs through Firebase, reaches the private Tailscale server, and completes an encrypted media round trip with an individual Museum account.

The observable success metric is one new-identity owner baseline, one higher-build-number owner update that preserves the account, active server, and cloud library, and one non-owner fresh installation. Operator success also requires that wrong bundle IDs, Apple teams, certificates, profiles, device sets, compiled endpoints, modified IPAs, dirty or unpushed source, non-increasing build numbers, incorrect Firebase registrations, and expired signing assets fail before publication.

---

## 3. Architecture / approach

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

Task 1.8 inspects the final IPA rather than trusting those build arguments. Its audit covers bundle identity, version/build, compiled endpoint, supported architecture, debug state, entitlements, application identifier, team, profile expiry and device count, signing certificate, ZIP integrity, and hash.

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
- Which external directories will hold Ad Hoc profiles, archives, immutable IPAs/manifests, and Firebase receipts?
- What exact baseline marketing version and initial `CFBundleVersion` should Task 1.8 pin after auditing the current source and any existing Cytech/Firebase records?

---

## 7. Lessons learned

> Populated at the end of each phase. Surprises, anti-patterns discovered, things to do differently next time.

_Empty until Phase 1 completes._
