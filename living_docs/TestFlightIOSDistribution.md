# TestFlight iOS Distribution for the Self-Hosted Photos App

**Status:** Migration abandoned; safe TestFlight-only cleanup completed. Firebase iOS remains active.
**Started:** 2026-07-23
**Owner:** vanton
**Planning doc:** n/a
**Companion docs:** [iOS distribution runbook](../mobile/apps/photos/SELF_HOSTED_IOS_DISTRIBUTION_GUIDE.md); the planned TestFlight architecture document was cancelled

---

## 1. Phase / Task tracker

| Phase | Task | Title                                                                               | Size | Status         | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| ----: | ---: | ----------------------------------------------------------------------------------- | :--: | -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
|     1 |  1.1 | Audit App Store Connect and TestFlight prerequisites without changing them          |  S   | 🟢 done        | Completed a read-only repository, local-tooling, and owner-guided account audit. The Ente team can create apps, has clear agreements, and has App Store Connect API access. Bundle `me.vanton.ente.photos.selfhosted` initially had no app record, TestFlight groups, beta metadata, builds, or export-compliance state. Xcode 26.6 supplies official upload tools. An initial sandbox-scoped keychain check could not see signing identities; the elevated read-only audit in Task 1.2 confirmed that the valid repository-pinned distribution identity already exists. App Manager is the least role for the selected external-testing pipeline. The unrelated exposed `.p8` key is excluded and must be rotated by its owning team. No Apple state changed. |
|     1 |  1.2 | Establish the App Store Connect app record and App Store signing assets             |  M   | 🟢 done        | Created the limited-access iOS record `Ente Photos Self-Hosted` for `me.vanton.ente.photos.selfhosted`, English (U.S.), SKU `ente-photos-selfhosted-ios`, Apple ID `6793832882`. Reused only the existing pinned `Apple Distribution: Cytech Ltd (68FYC2874Z)` certificate expiring 2027-07-17 and generated App Store profile `Ente Photos Self-Hosted App Store` (UUID `26b73280-34d2-44fb-8794-d9a69466738d`). The downloaded profile is outside Git with mode `0600` and SHA-256 `2e0dfb366956c14cc92ba4d27b1521824b658e124e05e5968e86404bb370c4d3`; inspection confirmed the exact app/team, one pinned certificate, no devices, `get-task-allow=false`, and `beta-reports-active=true`. No certificate, API key, group, tester, build, capability, or Firebase state was changed. |
|     1 |  1.3 | Establish a least-privilege App Store Connect publication credential                |  S   | 🔴 cancelled   | Abandoned by the owner before any user invitation or API-key creation. Task 5.1 removed the TestFlight-only setup while preserving the existing Firebase iOS distribution path.                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
|     1 |  1.4 | Add an App Store distribution export mode while retaining Ad Hoc fallback           |  M   | 🔴 cancelled   | Cancelled when the owner abandoned the migration in Task 5.1. The guarded iOS builder remains Ad Hoc-only.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
|     1 |  1.5 | Prepare and audit an immutable TestFlight IPA and manifest                          |  M   | 🔴 cancelled   | Cancelled when the owner abandoned the migration in Task 5.1. No TestFlight IPA or manifest was prepared.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
|     2 |  2.1 | Add App Store Connect JWT authentication and read-only preflight                    |  M   | 🔴 cancelled   | Cancelled when the owner abandoned the migration in Task 5.1. No App Store Connect publication credential was created.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
|     2 |  2.2 | Add exact confirmation, one-shot upload, and partial-attempt evidence               |  M   | 🔴 cancelled   | Cancelled when the owner abandoned the migration in Task 5.1. No Apple upload was attempted.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
|     2 |  2.3 | Add resumable processing, group assignment, review submission, and success receipts |  M   | 🔴 cancelled   | Cancelled when the owner abandoned the migration in Task 5.1. No TestFlight group, review submission, or receipt was created.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
|     2 |  2.4 | Reconcile an existing Apple upload without uploading again                          |  M   | 🔴 cancelled   | Cancelled when the owner abandoned the migration in Task 5.1. There is no Apple upload to reconcile.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
|     3 |  3.1 | Configure the private external group and temporary review Museum                    |  S   | 🔴 cancelled   | Cancelled when the owner abandoned the migration in Task 5.1. No tester group or review Museum was created.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
|     3 |  3.2 | Prepare, preflight, and publish the first TestFlight candidate                      |  M   | 🔴 cancelled   | Cancelled when the owner abandoned the migration in Task 5.1. No TestFlight build was published.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
|     3 |  3.3 | Verify external installation, private Museum use, and an in-place update            |  M   | 🔴 cancelled   | Cancelled when the owner abandoned the migration in Task 5.1. Firebase/Ad Hoc remains the tested distribution path.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
|     4 |  4.1 | Rewrite iOS distribution and tester documentation for TestFlight                    |  M   | 🔴 cancelled   | Cancelled when the owner abandoned the migration in Task 5.1. The Firebase/Ad Hoc runbook remains current.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
|     4 |  4.2 | Remove the iOS Firebase publisher and distribution contracts                        |  M   | 🔴 cancelled   | Cancelled when the owner abandoned the migration in Task 5.1. All iOS Firebase distribution surfaces remain in place.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
|     4 |  4.3 | Mark the Firebase iOS design records historical and preserve release evidence       |  S   | 🔴 cancelled   | Cancelled when the owner abandoned the migration in Task 5.1. Firebase iOS records remain operative rather than historical.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
|     4 |  4.4 | Document the as-built TestFlight distribution architecture                          |  S   | 🔴 cancelled   | Cancelled when the owner abandoned the migration in Task 5.1 because no TestFlight system was built.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
|     5 |  5.1 | Remove TestFlight-only setup and retain Firebase iOS distribution                    |  S   | 🟢 done        | Removed Apple Developer profile `VL92TFRG6Z` (`Ente Photos Self-Hosted App Store`) and moved its downloaded copy from Downloads to Trash. Retained dormant App Store Connect app `6793832882` to preserve its name and SKU. Verified that there are no TestFlight builds, testers, or groups; the Ad Hoc profile `Ente Photos Self-Hosted Owner Ad Hoc 2`, bundle ID, pinned distribution certificate, registered devices, Firebase projects, groups, releases, scripts, tests, documentation, and Android distribution remain untouched. All 51 focused iOS identity, Ad Hoc build, preparation, and Firebase publication tests passed with pinned Flutter 3.38.10/Dart 3.10.9. |

**Legend:** ⚪ not started · 🟡 working · 🟢 done · 🔴 blocked / cancelled
**Size:** XS · S · M · L · XL (never days or weeks).

---

## 2. Goal

> Historical goal. The owner abandoned this migration in Task 5.1 before any
> TestFlight build, tester, or group was created. Firebase App Distribution with
> Ad Hoc signing remains the active iOS delivery path.

Replace Firebase App Distribution and Ad Hoc device provisioning as the delivery
path for the configurable self-hosted Ente Photos iOS application with an
invitation-only external TestFlight workflow. V1 is complete when the owner and
one trusted external tester can install the exact audited application without an
App Store Connect role or registered device identifier, select and use their
private Museum service, retain application state through an in-place TestFlight
update, and leave immutable evidence tying the uploaded build to pushed source.
The first external build must also pass Beta App Review through a temporary
publicly reachable Museum containing only synthetic review data. Android
Firebase distribution and unrelated Firebase runtime behavior must remain
unchanged.

The observable success metric is one accepted external TestFlight baseline plus
one accepted higher-build update, with both installations verified on real
devices against the intended private Museum before the iOS Firebase publishing
path is removed.

---

## 3. Architecture / approach

> Historical proposed architecture. It was not implemented; the Firebase/Ad Hoc
> architecture documented in the operative iOS distribution runbook remains
> current.

### Selected delivery model

The implementation extends the existing guarded local release workflow instead
of introducing Fastlane or a continuous-integration publishing service.
Preparation remains an offline, non-mutating operation over a clean detached
checkout. Publication is a separate Dart command authenticated to App Store
Connect with a local JSON Web Token (JWT) API key.

```text
pushed source
    |
    v
isolated build + App Store export
    |
    v
read-only IPA + manifest outside Git
    |
    +--> native re-audit
    +--> App Store Connect read-only preflight
    |
    v
exact PUBLISH <release-id> confirmation
    |
    v
one official Apple upload
    |
    v
processing --> validated build --> external group --> Beta App Review
    |                                                    |
    +---------------- resumable reconciliation <---------+
                                                         |
                                                         v
                                                invited testers
                                                         |
                                                         v
                                               private Museum origin
```

The App Store Connect application record, agreements, fixed external tester
group, initial beta metadata, review contact, and review Museum are configured
manually. Automation must validate those resources but must not create or
silently replace them. After upload, automation may operate only on the exact
processed build: assign it to the configured group, submit it for Beta App
Review, and reconcile its state.

The publisher uses Apple's supported upload and App Store Connect interfaces
directly. Task 2.1 must verify the currently supported binary-upload mechanism
and minimum API-key role before Task 2.2 fixes that interface in the release
contract. No Fastlane dependency is introduced.

### Build and identity invariants

- The application bundle remains `me.vanton.ente.photos.selfhosted`.
- The self-hosted target remains core-only and configurable; the official Ente
  application targets and identities do not change.
- Every candidate uses a marketing version and strictly increasing
  `CFBundleVersion` that agree across source, archive, IPA, manifest, Apple
  processing state, and receipts.
- TestFlight candidates use App Store distribution signing and export. The Ad
  Hoc export mode remains available only as a fallback until Task 3.3 succeeds.
- Preparation accepts only a clean pushed commit, regenerates required ignored
  sources in the isolated checkout, audits the resulting IPA as untrusted
  input, and writes collision-safe read-only artifacts outside Git.
- The manifest binds the exact source commit, artifact hash and size,
  application identity, version/build, architecture, entitlements, signing
  mode, configurable endpoint policy, and review Museum origin.
- The publisher never builds or signs. It consumes only the immutable manifest
  and sibling IPA, repeats their audit before and after confirmation, and
  refuses any changed input.

### Review Museum and tester path

External TestFlight builds may require Beta App Review, including the first build
added to an external group. The candidate therefore starts with a temporary,
publicly reachable HTTPS Museum containing a synthetic library and a dedicated
demo account. Review contact details, credentials, beta description, feedback
email, and review notes are entered through App Store Connect and remain valid
until Apple approval.

The build stays configurable. Trusted testers use the existing endpoint
selection flow to move from the review Museum to their private Tailscale-reached
Museum before the temporary service is retired. The review service remains
available until Beta App Review approval and the owner plus external-tester
acceptance in Task 3.3 have both succeeded. It contains no personal library,
production credentials, or route into the private Museum.

### Publication state and evidence

Publication is a state machine rather than one long-running command:

```text
prepared
  -> preflight-passed
  -> upload-authorized
  -> upload-attempted
  -> Apple-processing
  -> processed-and-validated
  -> assigned-to-external-group
  -> waiting-for-beta-review
  -> approved-for-external-testing
  -> tester-accepted
```

Every invocation reads current local evidence and current App Store Connect
state, advances only a valid transition, and exits with an actionable next
command. A processing or review wait is not treated as a failed upload.

The evidence ledger contains:

- the immutable IPA and preparation manifest;
- a preflight snapshot naming only non-secret Apple resource identifiers and
  validated state;
- a partial-attempt receipt written before or immediately around the upload
  mutation;
- processing, group-assignment, and Beta App Review transition evidence; and
- one immutable success receipt after the exact build is externally available.

Receipts may contain opaque Apple identifiers, statuses, timestamps, hashes,
source links, version/build data, and sanitized command results. They must not
contain the API private key, demo password, tester email addresses, private
Museum credentials, or personal Apple account data.

### Failure visibility, rollback, and operational limits

| Failure                                                                                        | Detection and operator-visible result                                                                 | Recovery                                                                                                  |
| ---------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Wrong app, bundle, team, version, group, agreement, metadata, role, or export-compliance state | Read-only preflight fails before confirmation and names the mismatched field without printing secrets | Correct the manual App Store Connect or local configuration, then rerun preflight                         |
| IPA or manifest changed after preparation                                                      | Hash, permission, source, or native IPA audit fails                                                   | Discard the candidate and prepare a new immutable release                                                 |
| Upload result is missing or ambiguous                                                          | An immutable partial-attempt record exists without a success receipt                                  | Query App Store Connect and use no-upload reconciliation; never retry blindly                             |
| Apple is still processing the build                                                            | Reconciliation reports the current processing state and exits without mutation                        | Resume reconciliation later against the same attempt                                                      |
| Processed build differs from the manifest                                                      | Bundle, version, build, or other returned identity fails validation                                   | Stop; do not assign or submit the build, and prepare a higher-build correction                            |
| Beta App Review rejects the candidate                                                          | Review state and reason are preserved; no automatic resubmission occurs                               | Correct the app, metadata, or review environment and submit a distinct higher build                       |
| Review Museum is unreachable or credentials fail                                               | Preflight health check, Apple review feedback, or acceptance check fails                              | Restore the isolated review service or prepare a corrected higher build; do not expose the private Museum |
| Accepted build has a release defect                                                            | Device acceptance or private Museum behavior fails                                                    | Stop external testing and publish the last known-good source as a higher build                            |
| API key is missing, over-privileged, expired, or compromised                                   | Local permission audit or App Store Connect authentication fails                                      | Stop publication, revoke or replace the key, and re-run read-only preflight                               |

Phases 1 and 2 are pause-safe because the existing Firebase/Ad Hoc process
remains intact. An uploaded Apple build and consumed build number cannot be
rewritten or reused; rollback is forward-only through a higher build, while
testing of a bad build can be stopped. Phase 4 begins only after Task 3.3, so
the prior Firebase iOS release remains the operational fallback until the new
channel has proved both installation and update.

There is no throughput target because this is a single-operator release
workflow. Local validation and App Store Connect preflight must be bounded and
must not wait indefinitely. Apple processing and review are asynchronous
external states, so the SLO is resumability without duplicate upload rather
than completion latency.

The API `.p8` key, issuer and key configuration, signing material, review
credentials, tester identities, private endpoints, and release artifacts stay
outside Git. Child processes receive only the environment values they require,
and logs are sanitized before becoming evidence. Export-compliance answers and
Beta App Review information must agree with the built application; the public
AGPL source link for the exact commit remains part of release evidence.

Operational behavior is checked against Apple's
[TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview),
[external tester workflow](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers),
[beta test information requirements](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information),
[build upload guidance](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds),
[export-compliance workflow](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-export-compliance-information-for-beta-builds),
and [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi/).

---

## 4. Future work / out-of-scope

> Single source of truth for everything that is NOT in V1. Items move from here
> to V1 only with explicit owner approval and a decision-log entry.

| Item                                                                                                       | Status       | Why                                                                                                                                          |
| ---------------------------------------------------------------------------------------------------------- | ------------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Automate creation of the App Store Connect app, tester groups, agreements, or initial beta metadata        | V1.1 backlog | V1 deliberately validates manually established resources so the release key has a smaller mutation boundary.                                 |
| Move TestFlight signing or publication into continuous integration                                         | V1.1 backlog | V1 keeps Apple credentials and release authority on the guarded operator machine until the local workflow is proven.                         |
| Keep a permanent public review Museum                                                                      | V1.1 backlog | V1 uses a temporary isolated service with synthetic data; a durable service needs its own hosting, monitoring, patching, and abuse controls. |
| Add richer notifications for Apple processing, review, or build expiry                                     | V1.1 backlog | V1 exposes resumable status through the publisher and App Store Connect; remote alerting needs a separate credential and delivery design.    |
| Release the application publicly or privately through the production App Store                             | Out of scope | This initiative is an invitation-only external TestFlight beta for trusted testers.                                                          |
| Give testers App Store Connect roles or use internal TestFlight testing as the primary channel             | Out of scope | Trusted external testers must install without organization access.                                                                           |
| Change Android Firebase App Distribution                                                                   | Out of scope | Android continues using its existing Firebase application, group, publisher, and documentation.                                              |
| Remove Firebase runtime services from any Ente application                                                 | Out of scope | This migration changes only iOS binary distribution, not application runtime integrations.                                                   |
| Delete the Firebase project, iOS application record, historical releases, artifacts, attempts, or receipts | Out of scope | Historical evidence is retained; code and current instructions are retired only after TestFlight acceptance.                                 |
| Expose the private Tailscale Museum to Apple or the public internet                                        | Out of scope | Apple reviews only against the isolated synthetic review service.                                                                            |

---

## 5. Decision log

> Append-only. Newest entries on top. Never delete; if a decision is reversed,
> add a new entry explaining the reversal.

### 2026-07-23 — Abandon TestFlight and retain Firebase iOS distribution

**Decision:** Stop the TestFlight migration before credential creation, build
work, upload, tester-group setup, or documentation cutover. Remove the exact
TestFlight-only App Store provisioning profile and move its downloaded copy to
Trash. Keep the empty App Store Connect app record dormant so its name and SKU
remain reserved. Preserve the existing Firebase/Ad Hoc iOS distribution system
and every shared Apple signing resource.

**Why:** The owner explicitly reversed the initiative. Because the migration
was sequenced pause-safely, no TestFlight build, tester, group, publisher, or
Firebase replacement exists. The cleanup can therefore remove the one
TestFlight-only signing asset without changing the working production
distribution path.

**Alternatives considered:** Remove the App Store Connect app record as well,
which would release the app name and permanently consume its SKU; or continue
the migration despite the reversal. The owner selected the safer cleanup that
retains the dormant record.

### 2026-07-23 — Create the fixed Ente record and profile, but defer the API credential

**Decision:** Create a limited-access iOS App Store Connect record named
`Ente Photos Self-Hosted`, with primary language English (U.S.), bundle
`me.vanton.ente.photos.selfhosted`, and SKU
`ente-photos-selfhosted-ios`. Reuse the valid repository-pinned Cytech
distribution certificate to generate one manual App Store provisioning profile.
Move API-key selection and creation into its own Task 1.3 and require a separate
approval after the credential scope is understood.

**Why:** App Store Connect assigned Apple ID `6793832882`, and the generated
profile binds the exact team and bundle to the pinned certificate without
devices or development signing. The available certificate already has its local
private identity, so replacing it would add production risk without benefit.
Apple team API keys reach every app in the team, while an individual key follows
the user's app access; that trust-boundary choice should not be hidden inside app
or profile creation.

**Alternatives considered:** Give the app full user access, create or revoke a
distribution certificate, reuse the unrelated exposed key, or create a broad
team key in the same operation. Each would expand access or production mutation
beyond the prerequisites needed for App Store export.

### 2026-07-23 — Treat the Ente account as authorized but unprovisioned

**Decision:** Close the read-only readiness audit with the account control plane
ready and move app-record, signing, profile, and credential creation into Task
1.2.

**Why:** The owner confirmed that New App is enabled, agreements require no
action, and App Store Connect API access is enabled. The bundle has no app
record, while the local audit found no currently visible valid signing identity
or matching App Store profile. These are explicit setup deliverables rather
than authorization blockers.

**Alternatives considered:** Leave the audit open until resources are created,
which would mix read-only discovery with external mutations; or begin export
tooling against invented identifiers, which would weaken the guarded contract.

### 2026-07-23 — Use App Manager as the least publication role

**Decision:** The eventual App Store Connect publication credential must have
the App Manager role, not Developer or Admin.

**Why:** Apple permits a Developer to upload builds, but creating external
TestFlight groups, adding builds to them, inviting external testers, and
starting external testing require Account Holder, Admin, or App Manager. App
Manager is therefore the least role that covers the selected end-to-end
pipeline.

**Alternatives considered:** Developer is sufficient for build upload but not
external-group operations; Admin and Account Holder are broader than the
publisher requires.

### 2026-07-23 — Establish the missing App Store Connect application before build tooling

**Decision:** Add a separate setup task to create the App Store Connect iOS app
record for `me.vanton.ente.photos.selfhosted`, restore a usable local Apple
Distribution identity, and establish its manual App Store provisioning profile
before implementing App Store export.

**Why:** The owner verified that the bundle has no App Store Connect app record,
and the local audit found neither a valid code-signing identity nor a matching
App Store profile. TestFlight groups, beta metadata, builds, and export
compliance cannot exist for this bundle until those prerequisites are
established.

**Alternatives considered:** Hide account and signing creation inside the export
tooling task, which would combine external Apple mutations with repository code;
or begin publisher work without a destination app, which would encode
unverified identifiers and permissions.

### 2026-07-23 — Exclude the unrelated Apple key from the migration

**Decision:** Do not use the downloaded Apple `.p8` key for Ente. It belongs to
another application/team and must be rotated and revoked separately by that
team because its private material was exposed during the local audit.

**Why:** A scoped App Store Connect authentication check rejected the key, and
the owner confirmed that it has no relationship to the Ente team. Reusing or
testing it further would cross application and team boundaries.

**Alternatives considered:** Continue testing the unrelated key against App
Store Connect, which would be unauthorized and cannot establish Ente readiness;
or leave the exposed key active indefinitely, which would preserve a compromised
credential.

### 2026-07-23 — Keep the reference set operational

**Decision:** Link the operative iOS distribution runbook, the planned as-built
TestFlight architecture, and official Apple references. Record the planning
document as `n/a`.

**Why:** Future operators need current procedures and authoritative platform
behavior without carrying every predecessor design into the active migration
record.

**Alternatives considered:** A focused migration lineage including related
living docs, and a full historical lineage including locked-build, upstream,
and continuous-integration records. Both were rejected as unnecessary context
for this operational document.

### 2026-07-23 — Use a guarded hybrid App Store Connect boundary

**Decision:** Configure the app record, agreements, external group, initial beta
metadata, and review environment manually. Automation validates them and may
upload, assign the exact build, submit Beta App Review, and reconcile status.

**Why:** This keeps resource creation and broad account changes under direct
operator control while preserving a repeatable and evidenced release path.

**Alternatives considered:** Fully automate App Store Connect setup, which
requires broader mutation rights; or automate upload only, which fragments the
release state and evidence across manual steps.

### 2026-07-23 — Give Apple an isolated temporary review Museum

**Decision:** Build the configurable candidate with a publicly reachable
review-only Museum containing synthetic data and a demo account. Keep it
available through review and external acceptance, then retire it after testers
have selected their private Museum.

**Why:** Apple cannot reach the private Tailscale service, while external
TestFlight builds can require Beta App Review. The isolated service satisfies
review access without exposing private data or infrastructure.

**Alternatives considered:** Add a bundled offline demo mode, which expands the
application surface and may not represent real behavior; or submit the
Tailscale-only build with explanatory notes, which leaves the reviewer unable
to exercise the application.

### 2026-07-23 — Split publication work at mutation boundaries

**Decision:** Separate authentication and read-only preflight, one-shot upload,
post-upload lifecycle handling, and no-upload reconciliation into distinct
reviewable tasks.

**Why:** Each task has a clear safety boundary, and ambiguous Apple state can be
recovered without mixing a second upload into the same change.

**Alternatives considered:** Split by App Store Connect API layer, which hides
operator outcomes across abstractions; or build vertical publication slices,
which repeats mutation and recovery logic.

### 2026-07-23 — Sequence the migration risk-first and pause-safe

**Decision:** Audit prerequisites first, prove App Store export second, build
the publisher third, prove a real external TestFlight release while Firebase
remains available, and remove iOS Firebase only after installation and update
acceptance.

**Why:** Apple authorization, signing, review access, and asynchronous upload
state are the principal unknowns. Every phase boundary must leave a coherent
release option.

**Alternatives considered:** A thin end-to-end slice would reach upload sooner
but cross unresolved signing and review risks; a documentation-first cutover
would remove the known channel before its replacement is proven.

### 2026-07-23 — Extend the guarded Dart tooling without Fastlane

**Decision:** Reuse the isolated preparation and immutable evidence model, add
App Store distribution signing, and implement App Store Connect JWT,
preflight, upload, lifecycle, and reconciliation behavior in the local Dart
publisher using official Apple interfaces.

**Why:** The repository already has auditable Dart release contracts, native IPA
inspection, exact confirmation, and partial-attempt recovery. Extending that
model avoids a second release framework and preserves the current trust
boundary.

**Alternatives considered:** Fastlane adds mature actions but another dependency
and abstraction over the evidence contract; a mostly manual Xcode/Transporter
workflow reduces code but loses reproducibility and guarded reconciliation.

### 2026-07-23 — Perform a guarded TestFlight cutover

**Decision:** Build the complete App Store Connect pipeline, onboarding,
recovery, and immutable evidence path; prove it with real external installation
and update; then remove iOS Firebase distribution code and current
instructions while retaining historical receipts.

**Why:** Upload alone does not prove that external review, tester installation,
private-server selection, state retention, or updates work.

**Alternatives considered:** A narrow upload-only migration leaves most of the
Firebase operating process intact; a broader App Store release initiative adds
production listing, review, and release concerns that are not needed for the
trusted beta.

### 2026-07-23 — Serve trusted testers through external TestFlight

**Decision:** Replace Firebase/Ad Hoc delivery for the current trusted iOS
testers with invitation-only external TestFlight. Testers do not receive App
Store Connect roles and do not register device identifiers.

**Why:** This removes provisioning-profile refreshes and Firebase installation
steps while retaining a controlled tester population.

**Alternatives considered:** Internal TestFlight requires organization roles;
public links broaden access beyond the trusted group; retaining Firebase/Ad Hoc
does not solve the distribution burden.

---

## 6. Open questions

_None. The owner abandoned the migration in Task 5.1, so its unresolved
implementation questions were cancelled._

---

## 7. Lessons learned

> Populated at the end of each phase. Surprises, anti-patterns discovered, and
> things to do differently next time.

- Keeping the existing Firebase/Ad Hoc path intact through the risky Apple
  prerequisites made the reversal a cleanup-only operation.
- Separating the App Store Connect app record from the App Store provisioning
  profile allowed the TestFlight-only signing asset to be removed without
  touching the bundle ID, distribution certificate, registered devices, or Ad
  Hoc profile.
- Verify the exact authentication and permission boundary before creating an
  App Store Connect publication credential; no credential was needed or left
  behind when the migration stopped.
