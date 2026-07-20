# Upstream Ente Synchronization

**Status:** Living document. Updated at the end of every task.
**Started:** 2026-07-20
**Owner:** vanton
**Planning doc:** n/a
**Companion docs:** `mobile/apps/photos/SELF_HOSTED_DOCUMENTATION.md`, `living_docs/ConfigurableSelfHostedMobileServerArchitecture.md`, `living_docs/FirebaseAndroidDistribution.md`, `living_docs/FirebaseIOSDistribution.md`, planned `living_docs/UpstreamEnteSynchronizationArchitecture.md`

---

## 1. Phase / Task tracker

| Phase | Task | Title | Size | Status | Notes |
|------:|----:|-------|:----:|--------|-------|
| 1 | 1.1 | Create the isolated integration branch and record both source baselines | S | 🟢 done | Created `sync/upstream-2026-07-20` from clean pushed fork commit `ed63fc138d`; recorded fetched official commit `e184e77116`, merge base `dda1d1f790`, and divergence of 69 fork-only versus 1,014 upstream-only commits. Verified `origin` points to the personal fork, `upstream` fetches official Ente with push disabled, and the pre-merge application identities, configurable wrappers, SDKs, version, and fixed Firebase group aliases still match the audited documentation. No merge or external application/service state changed. |
| 1 | 1.2 | Merge all of official Ente `main` and resolve the atomic Git conflicts | L | 🟢 done | Merged exact official commit `e184e77116` with both histories intact. Eight previewed changed-on-both-sides files merged automatically; the only textual conflict was the generated Photos iOS `Podfile.lock`. Retained the merged upstream dependency graph for deterministic regeneration in Task 2.1 together with the auto-merged self-hosted Podfile target, Xcode target/configurations, Android flavor, endpoint/logout/startup code, localization, pubspec, and current documentation. Preserved upstream additions and deletions, found no unresolved entries or conflict markers, and did not touch either remote or external state. |
| 2 | 2.1 | Restore dependencies and generated-source compatibility | M | 🟢 done | Installed and checksum-verified Ente CI's exact Flutter 3.38.10/Dart 3.10.9 SDK in temporary storage. `flutter pub get --enforce-lockfile` completed without changing `mobile/pubspec.lock`; Rust binding generation completed twice with the matching rustup 1.97 compiler/formatter and produced no tracked diff. Regenerated Photos pods with temporary CocoaPods 1.17.0, retaining 61 Podfile dependencies and 78 installed pods; the second `pod install --deployment` reported `Verifying no changes`. Committed outputs refresh the local podspec and self-hosted Podfile checksums and remove two stale `dart_ui_isolate` framework entries from the Xcode project after upstream removed that dependency. Only established upstream license/base-configuration warnings remained; no external state changed. |
| 2 | 2.2 | Adapt endpoint, logout, startup, Server Settings, and focused tests to upstream APIs | M | 🟢 done | Reviewed the auto-merged configuration, startup/background entry points, network client/interceptor, account entry pages, landing page, settings surfaces, and endpoint policy/switcher against upstream APIs; no source adaptation was necessary. Ran the four focused endpoint/settings test files with Flutter 3.38.10 in standard, configurable (`https://photos.example.com`), and locked modes: all 50 tests passed in each mode (150 executions). Evidence covers fail-closed startup, persistent upgrade binding, anonymous credential-free/no-redirect probing, same-origin authenticated requests, mutation-free validation, cancellation and logout-failure recovery, incomplete-login cleanup, and local-logout-before-activation. |
| 3 | 3.1 | Reconcile Android flavor, identity, versioning, wrappers, and release contracts | M | 🟢 done | Reviewed the merged Gradle application, manifest overlay, source version, configurable build wrapper, and guarded prepare/publish tools. The existing self-hosted flavor remains additive to upstream: release package `me.vanton.ente.photos.selfhosted`, debug suffix `.debug`, source `1.3.59+2159`, SDK 26/36/36, NDK 28.2, ARMv7/ARM64 ABIs, and pinned signing-certificate contract all remain internally aligned. The wrapper canonicalized `https://Photos.Example.com/` to `https://photos.example.com` while owning the flavor and Dart defines. All 31 Android prepare/publication contract tests passed, including immutable artifacts/receipts, clean pushed provenance, app/group identity, signing/SDK/ABI audits, increasing build ledger, exact confirmation, partial-attempt recovery, and no-reupload reconciliation. No APK was built or uploaded in this task. |
| 3 | 3.2 | Reconcile iOS target, CocoaPods, Xcode signing, wrappers, and release contracts | M | 🟢 done | Raised the fork-only `SelfHostedRunner` xcconfig and three project configurations from iOS 14.0 to upstream's new 15.1 deployment floor, matching the merged Podfile and pods. Xcode enumerated the shared `selfhosted` scheme and resolved its Debug configuration to target/product `SelfHostedRunner`, bundle `me.vanton.ente.photos.selfhosted`, empty self-hosted entitlements, and iOS 15.1; the configurable wrapper canonicalized the example endpoint. All 51 iOS target-identity, Ad Hoc wrapper, prepare, and publication contract tests passed, covering the core-only graph, manual profile/team/certificate/device controls, immutable IPA/source audit, trusted iOS group, exact confirmation, and partial-attempt reconciliation. No archive, IPA, Apple state, Keychain state, device, or Firebase release changed. |
| 4 | 4.1 | Run analysis and focused automated tests and repair integration regressions | M | ⚪ not started | Run the endpoint, server-switch, packaging-identity, preparation, publication, and related upstream tests plus Photos analysis. Fix only failures caused by this integration and retain exact evidence in this record. |
| 4 | 4.2 | Build and audit the updated Android debug application | M | ⚪ not started | Build through the guarded configurable wrapper for a non-private example HTTPS origin, then inspect package, version, SDK, ABIs, debug state, compiled endpoint mode, archive integrity, and hash without installing or publishing it. |
| 4 | 4.3 | Build and audit the updated iOS Simulator application | M | ⚪ not started | Build the core-only configurable Simulator target, then inspect bundle identity, architecture, signature structure, compiled endpoint mode, and hash without Apple-account, device, Firebase, or server mutation. |
| 5 | 5.1 | Update current documentation and validate the complete integration diff | S | ⚪ not started | Update versions, toolchains, commands, source state, and release cautions in canonical documents. Validate links, privacy, scripts, whitespace, conflict-marker absence, upstream ancestry, and the final branch diff. |
| 5 | 5.2 | Document the repeatable as-built upstream synchronization architecture | S | ⚪ not started | Add `living_docs/UpstreamEnteSynchronizationArchitecture.md` with the settled remote/branch model, recurring merge sequence, conflict ownership, validation gates, release boundary, failure recovery, and maintenance checklist for the next upstream catch-up. |

**Legend:** ⚪ not started · 🟡 working · 🟢 done · 🔴 blocked / needs decision
**Size:** XS · S · M · L · XL (never days or weeks).

One task = one row = one reviewable step. Mark a row 🟡 working before starting
it and 🟢 done only after its acceptance evidence passes. Describe each task and
wait for approval before implementation.

Task naming convention: `Task <phase>.<sub> — <short imperative title>`. If a
commit is opened for a task, mirror that title.

---

## 2. Goal

Bring the entire fork up to the fetched official Ente `main` while preserving
the fork's reviewed self-hosted mobile behavior and all published source
history. V1 begins at fork commit `ed63fc138d88d9855e1ad1c10cea50747d5d0c0b`,
integrates official commit `e184e77116dbffd825b755c0fb2e4b924f837569`
from merge base `dda1d1f790e2d9a7bd68b0cf84a7c97efb4f5374`, and finishes on an isolated
branch whose full monorepo contains both histories. The observable success
criteria are clean upstream ancestry, no unresolved conflicts, passing
dependency generation, focused tests and Photos analysis, audited Android
debug and iOS Simulator artifacts, accurate privacy-safe documentation, and no
change to the fork's `main`, Firebase, Apple, private server, or physical
devices before explicit approval.

The primary user is the owner/maintainer performing occasional upstream
catch-up before preparing later closed-beta releases. Future maintainers should
be able to repeat the same merge without reconstructing today's decisions from
Git conflicts.

---

## 3. Architecture / approach

The repository keeps two deliberately separate remotes:

```text
official Ente                        personal fork
upstream/main                        origin/main
e184e77116...                        ed63fc138d...
      \                                  /
       \                                /
        +--> sync/upstream-2026-07-20 <-+
                 full Git merge
                       |
             repair and validation gates
                       |
                owner review / PR
                       |
                 fork main only
```

`origin` remains the only push destination. `upstream` is fetch-only and its
push URL remains disabled. The integration branch starts from the clean,
pushed fork `main`, then merges the exact fetched `upstream/main` commit with
`--no-ff`. This preserves the 69 fork commits, the 1,014 fetched upstream
commits, existing public source URLs, and future three-way merge information.
No rebase, squash, force-push, or selective mobile transplant is part of V1.

Captured Task 1.1 baseline:

| Property | Value |
|---|---|
| Integration branch | `sync/upstream-2026-07-20` |
| Fork source | `ed63fc138d88d9855e1ad1c10cea50747d5d0c0b` |
| Official source | `e184e77116dbffd825b755c0fb2e4b924f837569` |
| Merge base | `dda1d1f790e2d9a7bd68b0cf84a7c97efb4f5374` |
| Pre-merge divergence | 69 fork-only commits; 1,014 official-only commits |
| Push boundary | `origin` personal fork only; `upstream` push disabled |

Git's pre-merge three-way preview found approximately nine meaningful
changed-on-both-sides surfaces: the Photos README, Android Gradle application
configuration, iOS Podfile and lockfile, Xcode project, Photos account
configuration, English localization, application startup, and Photos
pubspec/dependencies. Upstream also removes or replaces many files that the
fork did not modify; those deletions belong to upstream and should merge
without restoring obsolete code. Custom self-hosted files added only by the
fork should remain unless their imports or contracts no longer match upstream.

The merge and later repair must retain these invariants:

- Android release package `me.vanton.ente.photos.selfhosted` and debug suffix
  `.debug` remain separate from official Ente variants.
- iOS bundle `me.vanton.ente.photos.selfhosted` remains on the core-only
  `SelfHostedRunner` target and shared `selfhosted` scheme without production
  extensions or Ente-operated entitlements.
- Both guarded wrappers own their platform/flavor selection and compile
  `configurableEndpoint=true` with one canonical HTTPS Museum default.
- A stored endpoint binding remains authoritative across in-place updates.
- Candidate server validation is anonymous, credential-free, no-redirect, and
  mutation-free. Signed-in switching completes local logout before activation.
- Authenticated Museum requests remain constrained to the active origin;
  Museum-provided object-storage URLs stay on their separate clients.
- Android signing identity and Apple organization/App ID continuity are not
  changed by source synchronization.
- Prepare/publish commands retain clean-pushed-source, immutable-artifact,
  re-audit, increasing-build-ledger, exact Firebase group, typed-confirmation,
  partial-attempt, and no-upload reconciliation guarantees.

Validation proceeds from cheapest to most expensive:

```text
merge structure and conflict audit
              |
dependency resolution and code generation
              |
focused self-hosted tests + Photos analysis
              |
Android guarded debug build and artifact audit
              |
iOS guarded Simulator build and artifact audit
              |
documentation, privacy, ancestry, and diff audit
```

This is strict branch quarantine. Failure leaves `main` and every published
artifact untouched. Before the merge commit, rollback is `git merge --abort`.
Afterward, rollback is abandoning the integration branch. No phase authorizes
a Firebase upload, tester notification, Apple device/profile change, signing
identity change, server upgrade, device installation, or force-push.

There is no new runtime performance target: upstream performance behavior is
accepted only after the existing application checks pass. The work adds no new
personal-data flow, compliance obligation, telemetry, or credential store.
Private endpoints, project/App IDs, signing inputs, tester identities, device
identifiers, artifacts, and receipts stay outside Git and command output.

---

## 4. Future work / out-of-scope

> Single source of truth for everything that is NOT in V1. Items move into V1
> only with explicit owner approval and a decision-log entry.

| Item | Status | Why |
|---|---|---|
| Automate recurring upstream fetches and integration pull requests | V1.1 backlog | First prove one full manual merge and identify stable conflict/validation boundaries before encoding automation. |
| Add continuous-integration builds for the private self-hosted variants | V1.1 backlog | Remote builds require a separate cache, signing, private-input, and artifact-retention design. |
| Upgrade the private Museum deployment | V1.1 backlog | Server compatibility is validated separately after source integration; this branch must not mutate the working private deployment. |
| Install the updated applications on physical Android or iOS devices | V1.1 backlog | V1 proves compile-time and Simulator/debug artifact compatibility without changing the currently working device installations. |
| Publish new Android or iOS Firebase releases | Out of scope | Distribution requires deliberate higher build numbers, private signing inputs, live server checks, and separate owner approval after this source branch is accepted. |
| Complete non-owner iOS device acceptance | Out of scope | That remains deferred until a real second iPhone or iPad exists and is not implied by source synchronization. |
| Rebase, squash, or force-push the fork's published history | Out of scope | Existing source references and release provenance must remain valid. |
| Selectively transplant only Photos code | Out of scope | The owner selected full-fork parity; partial monorepo state would make dependency compatibility and future merges harder to reason about. |
| Catalog every upstream commit in documentation | Out of scope | Git already stores that history; the living record captures only integration decisions, conflicts, and validation evidence. |

**Status values:**

- `V1.1 backlog` — deferred but planned for the next milestone.
- `Out of scope` — will not be done in this initiative; distinct from deferred
  work.

---

## 5. Decision log

> Append-only. Newest entries stay on top. Never delete an entry; if a decision
> changes, add a newer entry explaining the reversal.

### 2026-07-20 — Use a focused synchronization record and architecture companion

**Decision:** Track this integration in `UpstreamEnteSynchronization.md`, link
the current self-hosted architecture and distribution records, and finish with
a settled `UpstreamEnteSynchronizationArchitecture.md` companion.

**Why:** Upstream catch-up is recurring repository maintenance with its own
remote, history, conflict, validation, and release boundaries. It should not be
mixed into the completed configurable-endpoint feature record.

**Alternatives considered:** Extend the configurable-server record, which
would mix completed runtime design with repository maintenance; or catalogue
all upstream commits, which duplicates Git history and obscures actionable
conflicts.

### 2026-07-20 — Keep the integration branch quarantined until both platforms pass

**Decision:** Do not change fork `main` until the full merge, generation,
focused tests, analysis, Android build, iOS Simulator build, and final audits
pass and the owner explicitly approves integration.

**Why:** The current fork is releasable and backs working device installations.
A source catch-up should not convert its default branch into an incomplete
cross-platform repair area.

**Alternatives considered:** Gate Android and iOS separately, which permits a
temporarily one-platform branch; or merge early and repair on `main`, which
risks the last known-good source.

### 2026-07-20 — Resolve the real merge atomically

**Decision:** Keep Task 1.2 as one large but atomic Git merge task, then adapt
auto-merged API and build behavior in smaller follow-on tasks.

**Why:** Git cannot commit a partially resolved merge. The preview exposes a
small, known set of changed-on-both-sides files, while later compiler and test
repair can remain independently reviewable.

**Alternatives considered:** Pre-align old-base fork files before merging,
which creates immediately superseded compatibility commits; or reconstruct the
self-hosted patch on upstream, which abandons the selected history-preserving
architecture.

### 2026-07-20 — Sequence the integration risk first and pause safe

**Decision:** Establish the branch and baseline, complete the full merge, then
repair generation, runtime endpoint behavior, Android, iOS, validation,
artifacts, and documentation in that order.

**Why:** The merge and dependency changes reveal whether later platform work
is even viable. Every post-merge task has an evidence boundary and does not
require external release or device mutation.

**Alternatives considered:** Resolve and test everything in one pass, which is
hard to review; or trial a mobile-only merge first, which duplicates work and
does not prove full-monorepo integration.

### 2026-07-20 — Merge upstream into a dedicated branch

**Decision:** Branch from fork `main` and merge fetched `upstream/main` with
both histories intact.

**Why:** A true merge preserves published commit URLs, avoids force-pushing,
and gives future synchronizations a useful merge base.

**Alternatives considered:** Reapply a consolidated patch on upstream, which
risks losing historical fixes; or adopt a permanent rebased customization
branch, which rewrites the existing branch model and release history.

### 2026-07-20 — Deliver a thorough synchronization without distribution

**Decision:** Include full merge resolution, dependency/generation repair,
focused tests, analysis, Android debug and iOS Simulator artifacts, and current
documentation. Exclude Firebase publication and physical-device changes.

**Why:** Compilation and automated behavior are the minimum credible proof for
a 1,014-commit catch-up, while distribution would mix private signing and live
external state into source integration.

**Alternatives considered:** A merge-only trial leaves deep compatibility
unknown; a strategic automation V1 adds CI and credential design before one
manual integration establishes the stable workflow.

### 2026-07-20 — Synchronize the complete fork

**Decision:** Integrate the entire official Ente monorepo rather than only the
Photos subtree or a release-sized selection.

**Why:** The owner wants the fork to contain current Ente plus the self-hosted
changes. Photos depends on shared mobile packages, Rust crates, build tooling,
and repository-level conventions that evolve together.

**Alternatives considered:** A Photos-only transplant would leave an internally
mixed monorepo; rebasing all custom commits would rewrite published history.

---

## 6. Open questions

_None. New conflicts that cannot preserve both upstream behavior and the
self-hosted invariants stop the applicable task and are recorded here before a
scope change._

---

## 7. Lessons learned

- Platform floors stored only in fork-added configurations do not participate
  in ordinary three-way conflicts. The upstream Podfile moved to iOS 15.1
  while the self-hosted Xcode configurations remained on 14.0; comparing each
  custom target's resolved build settings against upstream exposed the drift.
- Auto-merged runtime changes can be valid even across a large API catch-up.
  Reviewing the semantic seams and compiling the same focused suite in all
  three endpoint modes showed that upstream's account/startup changes did not
  require a compatibility shim or weaken the self-hosted invariants.
- Exact tool versions are necessary but insufficient when multiple package
  managers are installed: escalated shells selected obsolete Homebrew
  `cargo`/`rustc` binaries until the rustup paths were made explicit. Running
  Rust binding generation twice with one explicit PATH proved the generated
  sources were byte-stable.
- The self-hosted Podfile necessarily has a different checksum from upstream,
  and the merged Xcode project retained stale framework paths that Git could
  not identify as conflicts. Regenerating with CocoaPods 1.17.0 updated local
  podspec checksums, removed those stale paths, and then passed deployment-mode
  verification without further tracked changes.
- Git's three-way preview correctly identified the areas requiring review but
  intentionally over-reported files that both sides changed compatibly. The
  real 1,014-commit merge produced only one textual conflict, in a generated
  lockfile.
- A true full-repository merge retained custom files and upstream deletions
  without manual transplantation. Reviewing auto-merged semantic hotspots is
  still required even when Git reports no conflict.
