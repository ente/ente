# Firebase Android Distribution for the Self-Hosted Photos App

**Status:** Living document. Updated at the end of every task.
**Started:** 2026-07-16
**Owner:** vanton
**Planning doc:** n/a
**Companion docs:** `living_docs/ConfigurableSelfHostedMobileServer.md`, `living_docs/ConfigurableSelfHostedMobileServerArchitecture.md`, `living_docs/LockedSelfHostedAndroid.md`, `mobile/apps/photos/SELF_HOSTED_BUILD_GUIDE.md`, `mobile/apps/photos/SELF_HOSTED_ANDROID_DISTRIBUTION_GUIDE.md`, `mobile/apps/photos/README.md`

---

## 1. Phase / Task tracker

| Phase | Task | Title | Size | Status | Notes |
|------:|----:|-------|:----:|--------|-------|
| 1 | 1.1 | Rename the self-hosted Android application ID | M | 🟢 done | Changed only the `selfhosted` flavor to release ID `me.vanton.ente.photos.selfhosted`; retained namespace `io.ente.photos`, the `.debug` suffix, signing inputs, iOS identity, and official flavor configuration. Forced Gradle to regenerate manifests after an initial stale-output pass and verified release `me.vanton.ente.photos.selfhosted`, debug `me.vanton.ente.photos.selfhosted.debug`, and unchanged independent debug `io.ente.photos.independent.debug`, all at version `1.3.59+2158`. Updated current README/build-guide identity, clean-install, upgrade, and rollback guidance while preserving historical living-doc evidence. The guarded endpoint validator and `git diff --check` pass. |
| 1 | 1.2 | Build, sign, and audit the replacement APK | S | 🟢 done | Built the configurable release for `https://macbook-pro-2.tailcfdac8.ts.net` and audited the fresh APK as package `me.vanton.ente.photos.selfhosted`, version `1.3.59` (`2158`), min/target SDK `26`/`36`, non-debuggable, and limited to `arm64-v8a` plus `armeabi-v7a`. APK Signature Scheme v2 verifies with the expected certificate SHA-256 `9f0a5f39668e7098d097745931bcb8fc392d50da877cf349a2b20e2db1a4ce69`; archive integrity passes and APK SHA-256 is `57d90841070903430374bb4dda3339b737a4980cfafa9659f73e6e2a235c50ae`. Preserved the exact 262,750,609-byte artifact at `/Users/vanton/projects/ente-android-toolchain/artifacts/ente-photos-me-vanton-selfhosted-1.3.59-2158-release.apk` without overwriting the legacy-package artifact or changing installed application state. |
| 2 | 2.1 | Provision Firebase and the trusted tester group | S | 🟢 done | Installed Firebase CLI `15.24.0` in the external Android toolchain and authenticated it as the intended operator with Gemini and optional telemetry disabled. Created dedicated project `vanton-ente-photos-selfhosted` (display name `Ente Photos Self-Hosted`), registered active Android app `1:221853227327:android:805cc5a53b5ccede489b8a` with exact audited package `me.vanton.ente.photos.selfhosted`, initialized App Distribution and confirmed its contact email in the console, and verified group alias `trusted-testers`. Added no Android Firebase configuration, runtime integration, credential, tester identity, or project binding to Git. During verification, Firebase CLI `login:list --json` unexpectedly printed OAuth tokens; the session was immediately revoked and replaced through a fresh browser login, which was safely verified through project visibility. |
| 2 | 2.2 | Add an audited release-preparation command | M | 🟢 done | Added `scripts/prepare_self_hosted_android_release.sh` with an importable Dart implementation. It requires a clean committed source reachable from `origin/*`, keeps one HEAD throughout the build, rejects repository-local output, strips Firebase/Google credential variables from the build environment, deletes stale build output, and delegates only to the guarded configurable ARM release wrapper. Final-APK gates pin package, pubspec version, release state, SDKs, ABIs, exact compiled HTTPS origin, archive integrity, one signer, APK Signature Scheme v2, and certificate fingerprint. Success atomically writes a collision-resistant read-only APK and schema-versioned JSON manifest outside Git; an existing release is never overwritten. Documented operation and added 16 focused tests covering real accepted and legacy-package APKs plus wrong version, endpoint, signer, debug state, source URL, endpoint syntax, immutable finalization, and collision handling. Focused analysis, Bash syntax, the dirty-worktree gate, and `git diff --check` pass; the preparation path contains no Firebase invocation or upload. |
| 2 | 2.3 | Add a guarded Firebase publication command | M | 🟢 done | Added a publication-only shell command backed by importable Dart. It accepts the prepared manifest, receipt directory, Firebase project, and Android App ID through local inputs; pins `trusted-testers`; re-hashes and fully re-audits the APK; validates the active Firebase package and group; generates release notes with one exact AGPL commit URL; shows a complete summary; and requires `PUBLISH <release-id>` before mutation. It repeats file and Firebase checks after confirmation, strips token/signing variables from all child processes, never calls Flutter, Gradle, signing inputs, or preparation, and writes collision-safe read-only success or partial-failure receipts outside Git. Successful receipts preserve Firebase references and form the guarded version ledger. Fifteen focused tests plus the combined 32-test real-artifact suite pass. A live `--preflight-only` run accepted release `ente-photos-selfhosted-1.3.59-2158-cab67ff1c2f6`, the exact active registration, and `trusted-testers`; it uploaded nothing and left the receipt directory empty. |
| 2 | 2.4 | Document releases, tester onboarding, and recovery | S | 🟢 done | Added `mobile/apps/photos/SELF_HOSTED_ANDROID_DISTRIBUTION_GUIDE.md`, a dedicated closed-beta operator runbook covering private local inputs; Docker, Museum `/ping`, and object-storage health; immutable preparation and non-mutating publication preflight; tester-group management; typed-confirmation publication and receipt reconciliation; Firebase and Tailscale onboarding; controlled encrypted upload/download acceptance; legacy application-ID cutover; in-place updates; three-layer Firebase/Tailscale/Museum offboarding; forward rollback; partial Firebase failure; invitation/release expiry; server outage; wrong-server recovery; signing-key loss; and operator-account compromise. The build guide and Photos README link to it, while the living-document companion list records it. The guide stores no real tester identity, invite, credential, Firebase binding, personal path, or private hostname. Its local links and referenced command files exist, required workflow/recovery topics are present, current primary Firebase/Tailscale behavior was verified on 2026-07-17, and `git diff --check` passes. |
| 3 | 3.1 | Publish the baseline release and replace the owner's old app | M | 🟢 done | Museum, PostgreSQL, MinIO, and the private HTTPS routes passed health checks before the audited `1.3.59` (`2158`) baseline was published to `trusted-testers`. Firebase returned incomplete references, so the publisher preserved a read-only partial attempt; the owner verified the exact release and group assignment in Firebase, and no retry occurred. When the physical Android device became available, private package inventory found the legacy identity installed and the replacement absent. After the owner confirmed cloud recovery, password, second-factor, and recovery material, the legacy package was uninstalled and build `2158` was installed through Firebase. A second inventory verified the exact replacement package/version/build and legacy-package absence. The app opened on the intended local server, authenticated to the local Museum account, uploaded a non-sensitive photo that appeared in the local web app, reopened the cloud copy after removal of only the device-local copy, and preserved the account, server binding, cloud library, and readable media after an ADB force-stop and relaunch. |
| 3 | 3.2 | Publish and verify an in-place Firebase update | M | ⚪ not started | Prepare a release with a higher version code and the same package/signing certificate, publish it through the guarded path, install it as an update from Firebase, and verify the account, active server binding, and cloud media remain intact. |
| 3 | 3.3 | Verify a non-owner tester's fresh installation | S | ⚪ not started | Invite one trusted non-owner through the Firebase group, confirm invitation acceptance and download status, join the device to the authorized Tailscale network, install the new package, sign in to an individual local-server account, and verify one controlled upload/download flow. Store no tester identity in this repository. |

**Legend:** ⚪ not started · 🟡 working · 🟢 done · 🔴 blocked / needs decision
**Size:** XS · S · M · L · XL (never days or weeks).

One task = one row = one reviewable step. Mark a row 🟡 working before starting it and 🟢 done only after its acceptance evidence passes. Describe each task and wait for approval before implementation.

Task naming convention: `Task <phase>.<sub> — <short imperative title>`. If a commit is opened for a task, mirror that title.

---

## 2. Goal

Distribute pre-release builds of the configurable self-hosted Ente Photos Android application to a small, trusted, mostly nontechnical group through Firebase App Distribution. V1 is complete when the application has the final release identity `me.vanton.ente.photos.selfhosted`; a local two-stage pipeline prepares and audits a signed APK separately from publishing it; Firebase invitations install the exact prepared binary; every release points recipients to its corresponding AGPL source commit; the owner replaces the old package and then receives an in-place update without losing the new app's account, server binding, or cloud library; and one non-owner tester completes a fresh install and encrypted media round trip against the private server.

The observable success metric is one Firebase baseline installation, one higher-version in-place update on the same package, and one non-owner fresh installation, all using the pinned signing identity and private Tailscale-accessible server. Operator success also requires that wrong packages, stale or modified APKs, dirty source trees, signer mismatches, invalid endpoints, and non-increasing update versions fail before upload.

---

## 3. Architecture / approach

### Identity cutover

The current configurable Android release uses application ID `com.vanton1.ente.photos.selfhosted`, version `1.3.59+2158`, and an external RSA-4096 release keystore whose certificate SHA-256 is `9f0a5f39668e7098d097745931bcb8fc392d50da877cf349a2b20e2db1a4ce69`. The target Firebase release identity is:

| Build | Application ID |
|---|---|
| Release | `me.vanton.ente.photos.selfhosted` |
| Debug | `me.vanton.ente.photos.selfhosted.debug` |

The Android `namespace` and Kotlin/Java packages remain `io.ente.photos`; only the install identity of the `selfhosted` flavor changes. Official flavors and the iOS bundle identity do not change. Android treats the old and new application IDs as unrelated applications, so app-local databases, preferences, keys, and sessions do not migrate. Encrypted cloud data remains associated with the Museum account and can be downloaded after login.

The owner chose an immediate replacement rather than side-by-side validation. Pause safety still requires building and auditing the new APK before removing the old package. At the Task 3.1 cutover, the old package is uninstalled first and the new Firebase package is then installed; reverting to the old identity requires reinstalling it and logging in again.

### Two-stage local release pipeline

The distribution path deliberately separates access to signing material from access to Firebase:

```text
clean source commit
        |
        v
prepare command -> existing configurable build wrapper -> signed release APK
        |                                                |
        +---- identity / endpoint / version / signer ----+
        |
        v
external immutable APK + release manifest
        |
        v
publish command -> revalidate hash and Firebase app -> explicit confirmation
        |
        v
Firebase App Distribution -> trusted-testers -> invitation / install / update
        |
        v
Tailscale -> private Museum -> signed private object-storage URLs
```

The preparation command owns release creation. It requires a clean Git worktree, records the exact commit and fork source URL, delegates the application build to `scripts/build_self_hosted_android.sh --release`, and accepts signing inputs only through the existing ignored Gradle properties, environment variables, and macOS login Keychain flow. It verifies the final APK rather than trusting build arguments. The external release manifest records at least:

- APK absolute path and SHA-256
- Git commit and corresponding source URL
- package name, version name, and version code
- minimum and target Android API levels
- included application binary interfaces
- release/debug state
- compiled configurable default HTTPS origin
- signing certificate SHA-256
- preparation tool version/schema

The publication command owns Firebase mutation. It receives the Firebase App ID and stable group alias through local configuration, uses the locally authenticated Firebase CLI, verifies that the Firebase Android registration names the manifest package, re-hashes and re-inspects the APK, rejects an already-used or non-increasing version when detectable, shows the complete publication summary, and requires an explicit confirmation. It never invokes Flutter, Gradle, signing tools, or the preparation command. A retry therefore uploads the same audited bytes rather than silently producing a different artifact.

The as-built publisher fixes the group alias to `trusted-testers` while keeping the project and Firebase App ID as local operator inputs. Its `--preflight-only` mode runs every file, package, signer, endpoint, version-ledger, Firebase-app, and group check without prompting, uploading, or writing a receipt. A real publication repeats the file audit and Firebase queries after the typed confirmation to close the review-to-upload race. It generates commit-pinned release notes, passes them through a temporary file, and strips signing, legacy Firebase-token, and Google credential-file variables from every child process.

Every successful upload finalizes a read-only `<release-id>.firebase-release.json` outside Git containing the prepared-manifest hash, artifact hash, version, package, endpoint, source link, Firebase target, group, release notes, upload disposition, and returned console/tester/download references. These receipts form the locally detectable version ledger and prevent the guarded workflow from reusing a version code. If Firebase fails after mutation may have begun, a separate read-only `.firebase-attempt-*.json` preserves the output and directs the operator to inspect Firebase before retrying; it is not treated as a successful version entry.

App Distribution is an external delivery channel only. The Android app gains no Firebase runtime SDK, Analytics, Crashlytics, in-app update API, or `google-services.json`. Tester membership and email addresses live in Firebase rather than repository files. Firebase CLI user credentials and signing secrets remain outside Git. The Firebase App ID is not a secret, but local configuration avoids coupling this public fork to one operator's project.

### Release and source invariants

- Firebase must be registered only after Task 1.2 proves the final case-sensitive package. Firebase documents that a registered Android package name cannot be changed for that Firebase app.
- Every uploaded APK must be signed. All updates under the new identity must use the same signing certificate.
- The first new-identity build may retain current version code `2158`; every in-place update must increase it.
- A release is prepared only from committed source. Release notes link to `https://github.com/vanton1/ente/commit/<commit>` and identify the build instructions needed to reproduce the corresponding source.
- The publish stage consumes the exact manifest hash and cannot repair, resign, rename, or rebuild an artifact.
- Firebase release retention is not an application kill switch. An installed APK continues running after Firebase removes its release; access to the private server remains controlled separately by Tailscale and Museum accounts.

Current Firebase behavior and limits are referenced from the official [Android CLI distribution guide](https://firebase.google.com/docs/app-distribution/android/distribute-cli), [tester and group management guide](https://firebase.google.com/docs/app-distribution/add-remove-testers), [tester onboarding guide](https://firebase.google.com/docs/app-distribution/get-set-up-as-a-tester), and [retention and troubleshooting guide](https://firebase.google.com/docs/app-distribution/troubleshooting).

### Failure visibility, security, and rollback

Preparation and publication use nonzero exits with actionable local messages. The release manifest and command output are the operator evidence; Firebase's release page, invitation acceptance, and download state are the delivery evidence; installed package metadata and the app's visible server/version are the device evidence; and Museum request logs provide the private-server package/version and media-flow evidence. V1 adds no remote crash telemetry or performance target because it changes distribution rather than runtime behavior.

The most consequential failures and recoveries are:

| Failure | Detection | Recovery |
|---|---|---|
| Wrong package or Firebase registration | Preparation audit or publication registration check | Stop before upload; create/use the correct Firebase Android app. A registered package cannot be renamed in place. |
| Modified or stale prepared APK | Manifest SHA-256 or metadata mismatch | Discard it and prepare again from clean committed source. |
| Non-increasing version code | Publication preflight or Android installer rejection | Prepare the intended source with a higher version code. |
| Firebase fails after upload begins | Nonzero CLI result or missing returned release references | Preserve an immutable partial-attempt record, inspect the Firebase console, and reconcile the external release before any retry. |
| Bad runtime release | Tester report, device evidence, or Museum logs | Rebuild the last known-good source with a higher version code and publish it as a forward rollback. |
| Lost or mismatched signing key | Certificate audit or Android update rejection | Existing installations cannot be upgraded under the same identity; uninstall and install a newly signed package, losing app-local state. The owner has accepted having no encrypted off-machine keystore backup. |
| Firebase invitation or release expired | Firebase console/tester experience | Resend the invitation or prepare/republish the same intended release according to Firebase's current rules. Installed copies keep running. |
| Tailscale DNS/routing unavailable | Private hostname resolution and VPN state | Restore tailnet membership, VPN connectivity, MagicDNS, and access rules before app login. |
| Museum host unavailable | HTTPS `/ping`, Docker state, and reverse-proxy status | Restore the existing Museum, PostgreSQL, MinIO, and proxy path; do not republish an unchanged app for a server outage. |

The Firebase account controls tester delivery, not access to encrypted photos. Each tester uses an individual Museum account and an explicitly authorized Tailscale identity. Release notes must not contain server credentials, signing secrets, tester addresses, access tokens, or recovery keys.

---

## 4. Future work / out-of-scope

> Single source of truth for everything that is NOT in V1. Items move into V1 only with explicit approval and a decision-log entry.

| Item | Status | Why |
|---|---|---|
| Automate Firebase publication in GitHub Actions or another continuous-integration service | V1.1 backlog | V1 deliberately proves the release contract locally before introducing service credentials and remote signing or artifact transfer. |
| Distribute the iOS application through Firebase | V1.1 backlog | Apple provisioning, tester-device registration, and iOS artifact signing are a separate initiative. |
| Long-term binary archive beyond the local prepared artifact and Firebase retention | V1.1 backlog | Exact source and local artifacts cover the trusted beta; durable binary archival needs a separate retention and access decision. |
| Add Firebase Crashlytics, Analytics, tester alerts, or in-app update SDKs | Out of scope | Firebase is a delivery channel only; adding runtime Google services changes privacy, dependencies, and application behavior. |
| Publish through Google Play, F-Droid, an unlisted store, or a public download page | Out of scope | V1 targets an invitation-only Firebase beta. |
| Keep building the legacy `com.vanton1.ente.photos.selfhosted` identity | Out of scope | The owner chose an immediate replacement rather than maintaining two Android packages. |
| Automate Tailscale enrollment or Museum account creation | Out of scope | Private-network and server identities remain explicit administrative actions outside the application release pipeline. |
| Decide public Ente branding or trademark rights | Out of scope | This plan authorizes only a closed beta and makes no determination about broader public distribution or branding permission. |
| Separate distribution architecture companion document | Out of scope | The two-stage flow and trust boundaries are fully captured here and in the operator guide planned by Task 2.4. |

**Status values:**
- `V1.1 backlog` — deferred but planned for the next milestone.
- `Out of scope` — will not be done in this initiative; distinct from deferred work.

---

## 5. Decision log

> Append-only. Newest entries stay on top. If a decision changes, add a new entry instead of rewriting history.

### 2026-07-17 — Revoke delivery, network, and server access independently

**Decision:** Treat Firebase App Distribution membership, Tailscale reachability, and Museum accounts as three independent access controls in the operator runbook. Onboarding verifies all three; offboarding removes the tester from the Firebase group/project as appropriate, revokes the Tailscale share or membership, and handles the Museum account according to a separate data-retention decision.

**Why:** Firebase only controls release delivery and cannot uninstall or disable an existing APK. Tailscale only controls private routing, while Museum owns authentication and encrypted server data. Treating any one of them as a kill switch would leave another access path or destroy data without explicit approval.

**Alternatives considered:** Treat Firebase removal as complete offboarding, revoke only Tailscale, or automatically delete the Museum account with either action. Each collapses distinct trust boundaries and either leaves access behind or couples identity removal to destructive data handling.

### 2026-07-16 — Make immutable receipts the guarded Firebase version ledger

**Decision:** Keep the Firebase project and App ID as local inputs, pin publication to `trusted-testers`, and make the publisher consume only an immutable prepared manifest/APK pair. Require a release-specific typed confirmation, repeat the audit and Firebase registration checks immediately afterward, and preserve each successful Firebase result as a read-only external receipt. Use those receipts to reject non-increasing versions that this guarded workflow can detect; preserve a distinct partial-attempt record if Firebase may have mutated before failing.

**Why:** Firebase CLI `15.24.0` exposes uploads but no release-list command, so the command cannot reliably preflight releases created through every external path. A local immutable ledger provides deterministic protection for all guarded releases, while partial-attempt evidence prevents a blind retry after an ambiguous external failure. Keeping receipts and Firebase identifiers out of normal build configuration preserves the separation between public source, signing, and distribution access.

**Alternatives considered:** Query App Distribution through an additional custom REST/auth client, trust the operator to remember prior version codes, store Firebase binding and release history in Git, or treat every failed CLI result as safe to retry. The custom client expands credential handling, memory is not auditable, repository state would couple the public fork to one Firebase project, and an upload can succeed before later release-note or group distribution steps fail.

### 2026-07-16 — Make preparation an offline final-artifact gate

**Decision:** Use a small shell entry point backed by an importable Dart implementation that builds only through the configurable wrapper, inspects the finished APK with Android and ZIP tooling, and atomically finalizes one read-only APK/JSON pair outside Git. Pin the release package, SDKs, ABIs, signature policy, and signer certificate in reviewed source; derive version and endpoint from the committed application inputs; require the commit to be reachable from `origin/*`; and remove Firebase/Google credential variables from the build subprocess.

**Why:** Build arguments and generated Gradle outputs are not sufficient evidence after the stale-APK behavior found in Phase 1. Inspecting the exact bytes, binding them to a real source URL, and refusing overwrite gives the later publisher one immutable artifact contract while keeping Firebase credentials outside the signing stage.

**Alternatives considered:** Extend the existing build wrapper with a manual audit checklist, combine preparation and Firebase upload in one command, or couple release policy to Gradle/Fastlane. The checklist is not machine-verifiable, the combined command collapses the credential boundary, and build-system integration makes retrying an unchanged prepared artifact harder.

### 2026-07-16 — Verify Firebase CLI access without listing login JSON

**Decision:** Never run `firebase login:list --json` in this workflow. Verify authentication through a harmless resource query such as `firebase projects:list`, and immediately log out and re-authenticate if CLI credentials appear in output.

**Why:** Firebase CLI `15.24.0` included live access, refresh, and identity tokens in the JSON result of `login:list` during Task 2.1. The affected session was immediately revoked with `firebase logout`, a fresh browser login replaced it, and project access was confirmed without printing credential material. No token or Firebase credential was written to the repository.

**Alternatives considered:** Trust the command name to return identity metadata only, or inspect the Firebase credential-store file directly. Both can expose reusable credentials and are unnecessary for an access check.

### 2026-07-16 — Provision a dedicated Firebase distribution identity

**Decision:** Use Firebase project `vanton-ente-photos-selfhosted`, Android App ID `1:221853227327:android:805cc5a53b5ccede489b8a`, exact package `me.vanton.ente.photos.selfhosted`, and stable tester-group alias `trusted-testers` for this closed beta.

**Why:** A dedicated project isolates tester access and releases from unrelated Firebase applications, while registration only after the signed APK audit prevents an immutable package-name mistake.

**Alternatives considered:** Reuse one of the operator's unrelated Firebase projects, or register Firebase before auditing the renamed APK.

### 2026-07-16 — Track Firebase distribution in a focused living document

**Decision:** Use `living_docs/FirebaseAndroidDistribution.md`, link the existing configurable and locked Android records plus the build guides and official Firebase documentation, and skip a separate architecture companion.

**Why:** Distribution has its own identity, credential, tester, retention, and rollback lifecycle. Extending a completed locked-build record would erase its historical boundary, while a generic Android distribution document would pull unchosen stores into scope.

**Alternatives considered:** Extend `LockedSelfHostedAndroid.md`, or create a broader multi-channel `AndroidDistribution.md`.

### 2026-07-16 — Fail closed before every Firebase upload

**Decision:** Use strict local preparation and publication gates with exact package, signer, version, endpoint, source, and hash validation; require an explicit confirmation before Firebase mutation; and roll back bad releases by publishing known-good source with a higher version code.

**Why:** Nontechnical testers need stable artifacts, and Android package/signature mistakes cannot be repaired after installation. The manifest and separate publication process make the exact distributed bytes reviewable and retryable.

**Alternatives considered:** A console-assisted manual checklist, or signed provenance plus dedicated service identity and workload federation.

### 2026-07-16 — Use a balanced nine-task tracker

**Decision:** Separate identity, artifact audit, Firebase provisioning, preparation, publication, documentation, owner baseline, owner update, and non-owner onboarding into nine reviewable tasks.

**Why:** These boundaries isolate code, credentials, irreversible external registration, device state, and human coordination without creating excessive micro-tasks.

**Alternatives considered:** A compact five-task tracker that mixes concerns, or a granular eleven-task tracker with more workflow overhead.

### 2026-07-16 — Sequence the work identity first and pause safe

**Decision:** Prove the renamed signed artifact before registering Firebase, then build the two-stage release tooling, document operations, and finish with owner and non-owner rollouts. Keep the old app installed until the replacement APK exists.

**Why:** Firebase package registration is immutable, and the owner should not lose the current working client while no audited replacement is available.

**Alternatives considered:** Provision Firebase before the package build, or manually upload a vertical-slice release before implementing the final pipeline.

### 2026-07-16 — Replace the old Android identity at cutover

**Decision:** Rename the self-hosted release package to `me.vanton.ente.photos.selfhosted`, keep namespace `io.ente.photos` and the existing signing identity, uninstall the old package before installing the first Firebase release, and do not maintain a legacy flavor or app-local migration.

**Why:** The owner explicitly prefers a clean immediate replacement. Server-side encrypted data survives, while retaining two application identities would add permanent packaging and testing work.

**Alternatives considered:** Verify both packages side by side before removing the old one, or maintain both identities indefinitely.

### 2026-07-16 — Separate release preparation from publication

**Decision:** Build and audit into an external artifact plus manifest in one command, then use a second command to revalidate and publish those exact bytes through the locally authenticated Firebase CLI.

**Why:** Signing and Firebase credentials stay separated, accidental publication is harder, and an upload retry cannot silently rebuild a different APK.

**Alternatives considered:** One command that builds and immediately uploads, or Gradle/Fastlane integration coupled directly to the Android build.

### 2026-07-16 — Deliver a thorough local Firebase V1

**Decision:** Include the configurable release, guarded two-stage tooling, external credentials, one stable group, release/source metadata, tester and Tailscale guidance, fresh install, in-place update, rollback, and signing-key-loss documentation. Keep CI and iOS distribution deferred.

**Why:** A manual one-off upload does not provide a safe repeatable path for nontechnical testers, while CI introduces unnecessary credentials before the workflow is proven.

**Alternatives considered:** A narrow manual-upload MVP, or a strategic V1 with continuous-integration automation and approval infrastructure.

### 2026-07-16 — Optimize for a trusted closed beta

**Decision:** Design for a small group of invited, mostly nontechnical friends or collaborators receiving occasional stable self-hosted Android updates.

**Why:** Tester onboarding, predictable updates, private-server access, and clear recovery matter more than high-frequency developer feedback or production-scale operations.

**Alternatives considered:** A technical rapid-build test group, or a long-lived private service with production-grade support and release operations.

---

## 6. Open questions

- Which non-owner trusted tester will complete Task 3.3? Keep their email address and identity in Firebase and private coordination, not in this document.

---

## 7. Lessons learned

### Phase 2

- Firebase CLI authentication status is sensitive output, not harmless metadata. Resource queries such as project, app, and group listing verify access without printing the reusable OAuth material exposed by `login:list --json` in CLI `15.24.0`.
- A two-stage release boundary is only useful when both halves fail closed. The prepared manifest binds immutable bytes to package, endpoint, signer, version, and source; the publisher repeats those checks and the Firebase registration query after typed confirmation.
- Firebase CLI exposes upload and distribution but no release-list command in the installed version. Read-only external success receipts therefore provide the deterministic version ledger for guarded releases, while separate partial-attempt records prevent blind retries after ambiguous external mutation.
- Distribution access is not runtime access. The operator workflow must reconcile Firebase delivery, Tailscale routing, and Museum authentication separately during both onboarding and offboarding.
- A real `--preflight-only` run against the production-sized APK and live Firebase registration found a missing `node` path in the first test environment without uploading anything. Re-running with the complete tool path proved the command, package, group, and no-mutation guarantee before baseline publication.

### Phase 1

- Generated Gradle manifests and APK outputs can survive an application-ID edit. A forced per-variant regeneration exposed correct manifests, while the first full build attempt left a July 13 APK with the legacy package at the expected output path. Moving that stale file aside and requiring a fresh modification time plus final-artifact inspection prevented a false success.
- Android install identity and code namespace are independent for this application. The self-hosted release now installs as `me.vanton.ente.photos.selfhosted` while the shared namespace remains `io.ente.photos`, avoiding an unnecessary Kotlin/Java migration and changes to official flavors.
- The new-identity release retains version `1.3.59` (`2158`) and the existing signing certificate, but Android still treats it as unrelated to `com.vanton1.ente.photos.selfhosted`. Keeping the old installation and artifact untouched until the audited replacement existed preserved a safe pause point; app-local state will intentionally reset at the later cutover.
- Restricting Flutter's release target platforms to Android ARM and ARM64 avoids compiling an unused x86_64 application binary. Final ZIP inspection remains authoritative: this APK contains only `arm64-v8a` and `armeabi-v7a` native libraries.
