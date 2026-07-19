# Self-Hosted Ente Photos iOS Distribution Architecture

This document describes the iOS distribution system as it exists after the owner baseline and first in-place update were verified. It is an operator-facing architecture companion, not a place to store signing identities, tester details, Firebase bindings, private hostnames, or credentials.

The central design is simple: build one auditable Ad Hoc IPA from pushed source, preserve it as immutable evidence, and publish those exact bytes through Firebase only after a separate guarded confirmation. Firebase delivers the application; it does not participate in application runtime, authentication, media encryption, or server access.

## 1. System at a glance

```text
 public fork                 owner-controlled Mac
 pushed source  ──────────> isolated release checkout
                                  │
                                  │ local Apple signing authority
                                  v
                         audited Ad Hoc IPA + manifest
                                  │
                                  │ exact typed confirmation
                                  v
 Apple organization <──── device/profile authorization ────> Firebase delivery
                                                               │
                                                               v
                                                          trusted iPhone
                                                               │
                                             private network + HTTPS
                                                               │
                                                               v
                                                  Museum + object storage
```

The arrows cross separate trust boundaries:

- The public fork supplies reviewable source and an immutable commit identity.
- The operator Mac holds the private signing key, provisioning profile, toolchains, and Firebase CLI authentication.
- The Apple organization owns the App ID, distribution certificate authorization, registered-device list, and Ad Hoc profile.
- The external artifact store holds read-only IPAs, manifests, publication attempts, API evidence, and success receipts outside Git.
- Firebase App Distribution controls invitations and delivers already signed IPAs to a dedicated tester group.
- The iPhone enforces Apple signing, provisioning, and Developer Mode requirements.
- The private network controls reachability to the self-hosted services.
- Museum controls accounts and encrypted library access; object storage holds the encrypted media objects.

Compromise or approval at one boundary does not imply approval at another. A Firebase tester cannot install on an Apple-unauthorized device, an installed app cannot reach the server without private-network access, and network access does not grant a Museum account or its recovery material.

## 2. Application and signing identity

The distributed application has these fixed properties:

| Property | As-built value or rule |
|---|---|
| Apple bundle identifier | `me.vanton.ente.photos.selfhosted` |
| Xcode application target | `SelfHostedRunner` |
| Entitlements | Core-only empty self-hosted entitlement file |
| Extensions | None |
| Signing style | Manual Ad Hoc signing for releases |
| Provisioning scope | Only explicitly registered trusted devices |
| Update identity | Same bundle identifier and strictly increasing `CFBundleVersion` |

The official Ente `Runner` target and its identity, entitlements, extensions, and release behavior remain unchanged. The self-hosted target does not inherit app groups, push notifications, associated domains, iCloud, or other Ente-operated capabilities.

The Apple Team ID, certificate material, profile UUID, device identifiers, and provisioning profile stay in private operator storage. The IPA necessarily embeds its Ad Hoc provisioning profile and authorized-device list, so the IPA itself is restricted to trusted recipients even though the public source is AGPL-licensed.

Relevant configuration:

- [`SelfHosted.xcconfig`](../mobile/apps/photos/ios/Flutter/SelfHosted.xcconfig)
- [`SelfHostedRunner.entitlements`](../mobile/apps/photos/ios/Runner/SelfHostedRunner.entitlements)
- [`build_self_hosted_ios.sh`](../mobile/apps/photos/scripts/build_self_hosted_ios.sh)

## 3. Immutable preparation pipeline

Preparation turns a pushed source commit into one auditable, read-only IPA/manifest pair without contacting Firebase.

```text
pushed commit
    │
    ├─ prove critical scripts match that commit
    ├─ create clean detached checkout
    ├─ resolve locked dependencies
    ├─ generate localizations, FRB, and filtered Dart outputs
    ├─ prove tracked source stayed clean
    ├─ archive and export with guarded manual Ad Hoc signing
    ├─ audit the exported IPA as untrusted input
    └─ finalize mode-0444 IPA + manifest outside Git
```

The isolated checkout prevents uncommitted primary-worktree files from entering a release. Preparation accepts only explicit toolchain/cache paths and local signing inputs, removes Firebase and unrelated cloud credentials from the build environment, owns its temporary archive/export locations, refuses output reuse, and never invokes Firebase.

The release environment is pinned to the proven toolchain family, including Flutter 3.38.10, Dart 3.10.9, rustup-managed Rust/Cargo 1.97, the reviewed Xcode release, and its compatible CocoaPods installation. Every invocation must carry the complete pinned Flutter, Dart, rustup, Cargo, and supporting PATH/cache environment into the isolated checkout. The first build-2161 attempts demonstrated that relying on an interactive shell's default Flutter or Cargo fails safely but wastes a release attempt.

Generation happens inside the detached checkout before archive creation:

1. Resolve the committed Flutter dependency lock.
2. Generate shared and Photos localizations.
3. Run the repository's official Flutter–Rust Bridge generator.
4. Run the narrowly filtered shared/Photos builders for required ignored and tracked generated Dart outputs.
5. Verify every required output and its localization import closure.
6. Verify that tracked files remain unchanged.

The exported IPA is then independently checked for safe ZIP structure, one application, the exact bundle/version/build, intended compiled HTTPS endpoint policy, arm64 Mach-O content, release rather than debug state, zero extensions, core-only entitlements, correct application/team binding, a device-scoped non-expired profile, the expected authorized-device count, the pinned valid distribution certificate, and valid code-signature structure.

Only after that audit does preparation copy the exact bytes to an owner-only external directory, write the manifest, make both files read-only, and finalize them without overwrite. The manifest binds the IPA hash and size to the pushed commit, clean-checkout evidence, generation provenance, build identity, endpoint policy, architectures, signing contract, profile scope, and certificate validity without recording device identifiers.

Implementation:

- [`prepare_self_hosted_ios_release.sh`](../mobile/apps/photos/scripts/prepare_self_hosted_ios_release.sh)
- [`prepare_self_hosted_ios_release.dart`](../mobile/apps/photos/scripts/prepare_self_hosted_ios_release.dart)
- [`build_self_hosted_ios.sh`](../mobile/apps/photos/scripts/build_self_hosted_ios.sh)

## 4. Guarded publication and evidence ledger

Publication consumes only an immutable preparation manifest and its sibling IPA. It cannot build, sign, or change Apple state.

```text
immutable manifest + IPA
          │
          ├─ hash and native IPA re-audit
          ├─ success-ledger check: build number must increase
          ├─ verify exact Firebase iOS app and tester group
          ├─ render public-source release notes
          └─ stop after read-only preflight
                         │
                 PUBLISH <release-id>
                         │
          ┌──────────────┴──────────────┐
          v                             v
 repeat every mutable check       confirmation rejected
          │                        or evidence changed
          v                             │
 exactly one Firebase call              └─ stop, no upload
          │
     ┌────┴──────────────────────┐
     v                           v
 complete references       failure or ambiguous success
     │                           │
 read-only receipt         read-only partial-attempt record
```

Before confirmation, all checks are non-mutating. The operator must enter `PUBLISH <release-id>` exactly. Publication then reloads and re-audits the files, rechecks the build ledger and Firebase destination, and permits one fixed distribute call. The Firebase child process receives only the credentials needed for that operation; Apple signing inputs and unrelated cloud credentials are removed.

Only a complete Firebase response with the required release references creates the normal mode-`0444` success receipt. That receipt binds the Firebase release to the exact IPA, manifest, source, build, notes, application, tester group, and response evidence. Only success receipts advance the strictly increasing build ledger.

An exit code alone is not proof. If upload may have occurred but the response is incomplete, the publisher writes a distinct immutable attempt record and forbids a blind retry. Recovery obtains an immutable response from Firebase's official read-only release-list interface and runs no-upload reconciliation. Reconciliation requires one exact match across app resource, version, build, release notes, creation window, and all release references before it writes the ordinary receipt with both evidence hashes.

This was exercised in both recovery modes:

- Build 2160 reached Firebase but initially returned incomplete JSON evidence. It was reconciled once without another upload.
- Build 2161 returned complete references and wrote its success receipt directly after one upload.

Future publication uses reference-bearing Firebase CLI text output rather than the JSON-only output that caused the first ambiguity.

Implementation:

- [`publish_self_hosted_ios_release.sh`](../mobile/apps/photos/scripts/publish_self_hosted_ios_release.sh)
- [`publish_self_hosted_ios_release.dart`](../mobile/apps/photos/scripts/publish_self_hosted_ios_release.dart)

## 5. Installation and in-place updates

Firebase provides the tester invitation, device-registration profile/web experience, and signed IPA download. Apple still decides whether the phone is present in the IPA's embedded Ad Hoc profile. On supported iOS versions, the tester must also enable Developer Mode before launching an Ad Hoc application.

The owner installation path is:

```text
Firebase group membership
        │
        v
device registration in Firebase
        │
        v
private Apple device registration + refreshed Ad Hoc profile
        │
        v
higher-build IPA published to the same Firebase application
        │
        v
install over the existing bundle identity
```

The baseline and update proved the important state transition. Build 2160 was installed from Firebase, then build 2161 with the same bundle identifier and higher build number installed in place. The update preserved authentication, selected local server, encrypted cloud library, and readable media. A new iPhone upload reached the web application, a different web upload synchronized and decrypted on the phone, and a forced process restart preserved the state.

Firebase is deliberately absent from runtime. The app contains no Firebase App Distribution SDK, Analytics, Crashlytics, Google service configuration, or in-app updater. Removing a tester from Firebase prevents future deliveries but does not uninstall an existing build.

## 6. Runtime and data boundary

After installation, the application communicates directly with the configured self-hosted server over HTTPS through the private Tailscale network. Museum provides the Photos API and account service; the configured object-storage service holds encrypted media objects. Firebase and Apple are not in this runtime data path.

```text
iPhone app
   │
   │ configurable private HTTPS origin over Tailscale
   v
Museum API  ───────────> object storage
   │
   └─ account, metadata, and encrypted-media coordination
```

Changing servers is an account-bound transition. If local application state belongs to the currently selected server, the guard completes local logout before activating the new endpoint and starting its login flow. This prevents one server's session state from being interpreted as a session on another server.

The runtime endpoint architecture is documented separately in [`ConfigurableSelfHostedMobileServerArchitecture.md`](ConfigurableSelfHostedMobileServerArchitecture.md). The operator runbook requires private Museum and object-storage health checks before a release and private route checks on the tester device before an app defect is assumed.

## 7. Evidence and privacy model

Evidence is intentionally split by sensitivity and authority:

| Location | Evidence | Privacy rule |
|---|---|---|
| Public Git repository | Source, tests, build/publish tools, guides, architecture, public commit links | No tester identities, device IDs, team IDs, Firebase App ID, private hostname, signing profile, or credentials |
| Private Apple account and Keychain | App ID ownership, certificates, private key, devices, provisioning profiles | Never copied into Git; disclose only the minimum needed to the operator |
| External owner-only artifact store | Immutable IPA, manifest, attempts, official API evidence, receipts | Directory is owner-only; finalized evidence is read-only |
| Firebase | App registration, tester group, invitations, release records, IPA delivery | Treat tester identities and release URLs as private |
| Physical iPhone and server observations | Installed build, selected server, sync, decryption, restart persistence | Record acceptance outcomes without media names, account data, or device identifiers |

Public release notes point to the exact public AGPL source commit and build instructions. They exclude the private server address, tester email, device identifier, Apple team identity, Firebase binding, credentials, invitations, and recovery material.

The IPA is not public evidence. Its embedded provisioning profile necessarily contains Apple authorization data, including the authorized-device set. Distribution is therefore limited to the trusted group even though the corresponding source is public.

## 8. Failure detection and recovery

| Failure | Detection | Recovery |
|---|---|---|
| Wrong Flutter, Dart, Rust, Cargo, Xcode, or CocoaPods | Preparation version checks, dependency failure, or generation mismatch | Stop before artifact creation; restore the complete pinned environment and prepare again. |
| Dirty or unpushed release source | Commit reachability, critical-script equality, detached-checkout cleanliness | Push the intended source, then prepare from that commit. Never release primary-worktree dirt. |
| Wrong bundle, team, entitlement, certificate, profile, or device count | Archive/export preflight and native IPA audit | Correct the private Apple inputs, assign a higher build if any IPA bytes were distributed, and prepare again. |
| Expired certificate or profile | Local signing and manifest validity checks | Renew the organization-controlled asset, refresh the profile, use a higher build number, and re-release. |
| Tester phone absent from profile | Firebase device collection plus private Apple/profile comparison | Register the device privately, regenerate the profile, build a higher version, and publish a distinct IPA. |
| Firebase may have accepted an upload but response is incomplete | Partial-attempt record or missing release references | Preserve all evidence, query the official read-only release list, and reconcile. Never retry blindly. |
| Museum, object storage, HTTPS, or private network unavailable | Server health probes, device route checks, web app, and server logs | Restore infrastructure or network access. Do not publish unchanged app bytes for a server outage. |
| Bad application release | Installed build evidence, controlled sync test, logs, or reproducible defect | Rebuild known-good source with a higher build number and publish it as a forward rollback. |
| Distribution private key lost | Keychain/signing-identity preflight | Issue a new organization-authorized distribution certificate and profile while keeping bundle/team ownership stable. |
| Tester access must end | Independent Firebase, Apple, Tailscale, and Museum review | Remove future delivery, revoke private-network access, disable the Museum account as policy requires, and refresh future profiles. Existing Ad Hoc apps are not remotely uninstalled. |

Rollback is always forward: every changed IPA, including a profile-only rebuild or reversion to known-good source, receives a higher `CFBundleVersion`. Reusing a build number would allow multiple byte sequences to share one release identity and break the receipt ledger.

## 9. Operator checklist

### Before preparation

- Confirm the intended source commit is pushed to the fork.
- Confirm the private Museum, object-storage, HTTPS, and Tailscale paths are healthy.
- Confirm the intended Apple distribution identity and private key are available.
- Confirm the Ad Hoc profile matches the bundle, team, certificate, expected device set, and validity window.
- Load the complete pinned Flutter/Dart, rustup Rust/Cargo, Xcode, and CocoaPods environment.
- Choose a new, strictly higher build number and unused external output location.

### Prepare and preflight

- Run the immutable preparation command from the intended pushed commit.
- Verify the command produced exactly one mode-`0444` IPA/manifest pair outside Git.
- Review the manifest's source, version/build, endpoint policy, profile device count, certificate validity, and artifact hash.
- Run publication preflight and review the exact Firebase app, group, release notes, and prior-receipt ledger.

### Publish

- Enter the release-specific `PUBLISH <release-id>` only after the complete summary matches.
- Allow one upload attempt.
- Require a normal immutable success receipt before treating the release as published.
- If evidence is ambiguous, preserve the attempt and reconcile read-only; do not upload again.

### Install and accept

- Confirm the tester has the Firebase invitation and device-registration flow.
- Confirm Apple privately authorizes that exact device in the embedded profile.
- Confirm Developer Mode and private-network access on the phone.
- Confirm the tester uses an individual Museum account and controls its recovery material.
- Verify the visible build/server, one controlled encrypted upload, one controlled download/decrypt, and forced-restart persistence.
- Record only the outcome; keep identities, device values, media names, and private addresses out of Git.

### Maintain and recover

- Monitor certificate/profile expiry during every preparation and before planned releases.
- Keep finalized artifacts, manifests, attempts, API evidence, and receipts read-only and owner-only.
- Offboard Firebase delivery, Apple profile membership, Tailscale access, and Museum access independently.
- Recover a bad release through a higher-build forward rollback.
- Re-audit the architecture and runbook when Apple, Firebase, Xcode, Flutter, Rust, or the server topology changes.

## 10. Deferred V1.1 proof

The owner baseline, Firebase install, and in-place update are verified. A real non-owner device is intentionally deferred until a tester and iPhone are available. V1.1 must complete the whole dependency chain rather than infer success from the owner device:

1. Register one invited non-owner tester device privately.
2. Refresh the Ad Hoc profile, prepare a higher-build IPA, audit it, and publish it through the guarded path.
3. Verify invitation, installation, Developer Mode, private-network access, individual Museum login, encrypted upload/download, and restart persistence on that physical phone.

Until those steps are observed, the system is proven for owner operation and updates, not for non-owner onboarding.

## 11. Implementation and operations references

- [`FirebaseIOSDistribution.md`](FirebaseIOSDistribution.md) — task history, decisions, evidence, and deferred work
- [`SELF_HOSTED_IOS_DISTRIBUTION_GUIDE.md`](../mobile/apps/photos/SELF_HOSTED_IOS_DISTRIBUTION_GUIDE.md) — operational onboarding, publication, offboarding, and recovery runbook
- [`SELF_HOSTED_BUILD_GUIDE.md`](../mobile/apps/photos/SELF_HOSTED_BUILD_GUIDE.md) — supported self-hosted mobile build commands
- [`ConfigurableSelfHostedMobileServerArchitecture.md`](ConfigurableSelfHostedMobileServerArchitecture.md) — runtime server-selection architecture
- [`build_self_hosted_ios_adhoc_test.dart`](../mobile/apps/photos/test/scripts/build_self_hosted_ios_adhoc_test.dart) — archive/export guard tests
- [`prepare_self_hosted_ios_release_test.dart`](../mobile/apps/photos/test/scripts/prepare_self_hosted_ios_release_test.dart) — immutable preparation tests
- [`publish_self_hosted_ios_release_test.dart`](../mobile/apps/photos/test/scripts/publish_self_hosted_ios_release_test.dart) — guarded publication and reconciliation tests
- [`self_hosted_ios_identity_test.dart`](../mobile/apps/photos/test/scripts/self_hosted_ios_identity_test.dart) — self-hosted identity and core-only target tests

