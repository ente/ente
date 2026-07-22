# Fork GitHub Actions Maintenance

**Status:** Living document. Updated at the end of every task.
**Started:** 2026-07-22
**Owner:** vanton
**Planning doc:** n/a
**Companion docs:** [Fork overview](../FORK.md), [self-hosted mobile documentation index](../mobile/apps/photos/SELF_HOSTED_DOCUMENTATION.md), [upstream synchronization runbook](../UPSTREAM_SYNC.md), [upstream synchronization architecture](UpstreamEnteSynchronizationArchitecture.md), planned `ForkGitHubActionsArchitecture.md`

---

## 1. Phase / Task tracker

| Phase | Task | Title | Size | Status | Notes |
|------:|----:|-------|:----:|--------|-------|
| 1 | 1.1 | Inventory every inherited workflow and record an evidence-based disposition | M | 🟢 done | Audited all 38 active workflow files, their triggers, permissions, secret/service dependencies, recent runs, representative failure logs, and fork relevance. The disposition is 23 risk-first removals in Task 1.2, nine unrelated check removals in Task 3.2, four fork-focused replacements/repairs, and two retained fork workflows to harden. No workflow or GitHub setting changed. |
| 1 | 1.2 | Remove inherited deployment, release, translation, and scheduled runner automation | M | ⚪ not started | Remove workflows that depend on Ente production infrastructure or perform unrelated scheduled work, without changing external application, server, signing, or distribution state. |
| 2 | 2.1 | Add Linux CI for the self-hosted Photos mobile behavior and source quality | M | ⚪ not started | Run focused endpoint and release-tool contracts, tracked-Dart formatting, and full mobile analysis with fork-relevant triggers and no signing or publication secrets. |
| 2 | 2.2 | Add macOS CI for the self-hosted iOS contracts and deterministic CocoaPods state | M | ⚪ not started | Run iOS-specific tests with the required Apple tooling and verify the lockfile without archiving, signing, registering devices, or publishing an IPA. |
| 2 | 2.3 | Preserve and harden upstream-drift and workflow-security checks | S | ⚪ not started | Retain the fork-specific drift issue and workflow security boundary while minimizing permissions, credentials, triggers, and untrusted pull-request exposure. |
| 3 | 3.1 | Repair dependency review and retain only useful security scanning | M | ⚪ not started | Enable or adapt supported GitHub dependency features and keep CodeQL coverage only where it produces relevant, actionable results for this fork. |
| 3 | 3.2 | Remove remaining unrelated product and monorepo checks | S | ⚪ not started | Remove inherited Ensu, Auth, Locker, desktop, web, server, Rust, docs, infrastructure, and other checks that do not protect the self-hosted Photos mobile fork. |
| 3 | 3.3 | Enforce the exact fork workflow allowlist and security contract | M | ⚪ not started | Reject unapproved workflow files, unpinned actions, excessive permissions, unsafe triggers, or silently reintroduced upstream automation. |
| 4 | 4.1 | Validate the complete workflow set locally and in controlled GitHub runs | M | ⚪ not started | Prove relevant-path execution, irrelevant-path filtering, blocking failures, successful checks, and absence of release/deployment mutations through local contracts and owner-reviewed GitHub runs. |
| 4 | 4.2 | Document the as-built fork GitHub Actions architecture | S | ⚪ not started | Update fork navigation and write `ForkGitHubActionsArchitecture.md` with the final allowlist, triggers, jobs, permissions, failure behavior, rollback, and upstream-adoption procedure. |

**Legend:** ⚪ not started · 🟡 working · 🟢 done · 🔴 blocked / needs decision
**Size:** XS · S · M · L · XL (never days or weeks).

One task = one row = one reviewable step. Mark a row 🟡 working before starting
and 🟢 done only after its acceptance evidence passes. Task naming follows
`Task <phase>.<sub> — <short imperative title>`; commits, when requested, mirror
that title.

---

## 2. Goal

Give the owner and contributors of this self-hosted Ente Photos mobile fork a
quiet, trustworthy GitHub Actions surface. V1 is complete when every inherited
workflow has an evidence-based disposition; workflows tied to Ente production,
unrelated products, scheduled builds, translations, signing, or deployment are
gone; fork-owned mobile, dependency, workflow-security, and upstream-drift
checks pass on the paths they protect; relevant failures block merging; and an
exact allowlist prevents a future upstream synchronization from silently
reactivating automation.

Success is observable in GitHub: relevant pull requests receive only useful,
actionable checks; irrelevant changes do not consume expensive runners; the
Actions page no longer fills with expected missing-secret or missing-service
failures; the upstream drift workflow continues to manage its single tracking
issue; and no retained workflow can sign, publish, deploy, translate, or mutate
private operational state.

The work targets the fork owner and occasional contributors reviewing changes
or upstream synchronization pull requests. It does not recreate official
Ente's CI, release infrastructure, or organization secrets. There is no
application-runtime latency or throughput objective; CI must provide bounded,
non-duplicated feedback only for relevant changes.

---

## 3. Architecture / approach

The selected architecture replaces inherited automation with a small,
fork-owned allowlist:

```text
pull request or manual check
          |
          +--> Linux self-hosted mobile validation
          +--> macOS iOS contract + CocoaPods validation
          +--> dependency/security validation
          +--> workflow allowlist + security validation

daily/manual detector
          |
          +--> read official upstream history
          +--> create/update/close one fork drift issue

anything else
          |
          +--> no workflow file, no runner, no secret, no mutation
```

The intended retained set has separate responsibilities:

- a Linux workflow owns fork-specific Photos endpoint and release-tool tests,
  tracked-Dart formatting, and complete mobile analysis;
- a macOS workflow owns tests requiring Apple command-line tools and
  deterministic CocoaPods verification, without building a signed artifact;
- dependency review and only demonstrably useful code scanning own third-party
  and supported-language security evidence;
- the existing workflow-security check owns action pinning, minimal
  permissions, safe checkout/authentication, and the exact workflow allowlist;
  and
- the existing upstream-drift workflow retains its fork identity guard and
  narrow `contents: read` plus `issues: write` role.

Every retained pull-request check fails closed. External actions stay pinned to
full commit SHAs. Jobs default to read-only repository permissions and do not
receive signing, Firebase, Apple, Cloudflare, Crowdin, Tailscale, Museum,
container-registry, app-store, or deployment credentials. Pull requests are
treated as untrusted input; workflows must not execute mutable privileged
operations on their code.

Path filters and job boundaries keep Linux-only work off macOS and avoid
unrelated monorepo activity. Platform-specific tests run on the platform that
provides their real tools rather than weakening production scripts or tests to
make them pass on an incompatible runner. The allowlist is checked from the
repository itself so a later upstream merge that restores or adds a workflow
fails review before that workflow is accepted into fork `main`.

The implementation is sequenced risk-first. It records a complete inventory,
then removes production and scheduled automation, introduces the replacement
checks, repairs supported dependency security, removes the remaining unrelated
checks, enforces the final allowlist, and finishes with controlled live proof.
Each source change is reversible with Git. Repository security settings changed
for dependency review must also be individually reversible and recorded.

Preliminary evidence from 2026-07-21 and 2026-07-22 already shows the central
failure classes: Crowdin runs lack the official API token; Ente deployment and
release workflows expect official environments, signing material, or service
credentials; dependency review reports that the repository feature is not
enabled; and the broad Linux mobile lint invokes iOS-only `plutil` tests and
finds fork release-directory permission assumptions. Task 1.1 will turn the
sample into a complete, reviewable disposition matrix instead of treating it
as the final audit.

### Task 1.1 workflow disposition inventory

The inventory was captured on 2026-07-22 from the local YAML, the GitHub
workflow API, the latest available 100 fork runs, failed job/step metadata, and
representative failed logs from 2026-07-20 through 2026-07-22. GitHub reported
all 38 files as active. “No recent run” means no execution appeared in that
bounded fork history; it does not claim that the official repository never ran
the workflow. Secret names were classified without reading secret values.

| Workflow | Trigger and access boundary | Fork evidence | Disposition and reason |
|---|---|---|---|
| `app-release.yml` | Manual; `contents: write`, `pull-requests: write`; official GitHub App credentials | No recent fork run | **Remove in Task 1.2.** Official multi-application release orchestration is outside the fork and can mutate releases and pull requests. |
| `auth-build.yml` | Push, manual, schedule; `contents: write`; Android, Apple, Windows, Firebase, Azure, GitHub App, and notification secrets | Two scheduled failures; signing, token minting, and certificate steps failed | **Remove in Task 1.2.** Auth builds and official signed releases are unrelated and depend on unavailable production credentials. |
| `cli-release.yml` | Version-tag push; read-only token plus release commands; official-repository condition present inside the job | No recent fork run | **Remove in Task 1.2.** The fork does not publish the Ente CLI, and retaining dormant release logic adds unnecessary surface. |
| `codeql.yml` | Manual and weekly schedule; job grants `security-events: write` and `packages: read`; no repository secrets | No recent fork run | **Replace/adapt in Task 3.1.** Actions scanning is relevant, but broad Go and JavaScript/TypeScript analysis must earn its runner cost against fork scope. |
| `copycat-db-release.yml` | Manual; `contents: read`; external container-registry username/password | No recent fork run | **Remove in Task 1.2.** Publishing the server database image is unrelated and requires external release credentials. |
| `dependency-review.yml` | Dependency-changing pull requests; `contents: read`; no secrets | One PR failure: dependency review is unsupported until the repository dependency graph is enabled | **Repair in Task 3.1.** Dependency risk is in scope, but repository support and useful manifest coverage must be enabled and proven. |
| `desktop-lint.yml` | Desktop-changing pull requests; `contents: read`; no secrets | No recent fork run | **Remove in Task 3.2.** Desktop Photos is outside the self-hosted Android/iOS client boundary. |
| `docs-deploy-redirect.yml` | Docs redirect push and manual; `contents: read`; Cloudflare credentials | No recent fork run | **Remove in Task 1.2.** The fork does not control the official help-domain redirect or its Cloudflare account. |
| `docs-deploy.yml` | Docs push and manual; `contents: read`; production environment and Cloudflare credentials | One push failure in the publish step | **Remove in Task 1.2.** Official documentation-site deployment is not owned by the fork. |
| `docs-verify-build.yml` | Docs-changing pull requests; `contents: read`; no secrets | No recent fork run | **Remove in Task 3.2.** The official documentation site is outside V1; fork Markdown contracts will live in the replacement validation. |
| `ensu-android-build.yml` | Ensu Android pull requests; `contents: read`; no secrets | One successful PR run | **Remove in Task 3.2.** A green but unrelated Ensu build still consumes runners and does not protect self-hosted Photos. |
| `ensu-build.yml` | Push, manual, schedule; `contents: write`; signing, Apple, Azure, Firebase, GitHub App, updater, and notification secrets | Two scheduled failures across signed Android, iOS, and desktop jobs | **Remove in Task 1.2.** Official Ensu release automation is unrelated and credential-bound. |
| `ensu-ios-build.yml` | Ensu iOS pull requests on macOS; `contents: read`; no secrets | One successful PR run | **Remove in Task 3.2.** It consumes an expensive runner for an unrelated application. |
| `infra-deploy-staff.yml` | Staff-site push and manual; `contents: read`; production environment and Cloudflare credentials | One push failure in the publish step | **Remove in Task 1.2.** The fork neither owns nor deploys Ente staff infrastructure. |
| `infra-lint-staff.yml` | Staff-infrastructure pull requests; `contents: read`; no secrets | No recent fork run | **Remove in Task 3.2.** Staff infrastructure is unrelated to mobile self-hosting. |
| `locker-build.yml` | Push, manual, schedule; `contents: write`; Android, Apple, Firebase, GitHub App, and notification secrets | Two scheduled failures in Android and Apple signing steps | **Remove in Task 1.2.** Locker and its official signed distribution are outside fork scope. |
| `mobile-crowdin-push-sources-and-translations.yml` | Manual; `contents: read`; Crowdin token and GitHub token | No recent fork run | **Remove in Task 1.2.** The fork does not own the official Crowdin project or translation publication flow. |
| `mobile-crowdin-push-sources.yml` | Mobile source push; `contents: read`; Crowdin token and GitHub token | Two push failures; required Crowdin API token was absent | **Remove in Task 1.2.** It fails by design without the official translation service and runs on accepted fork changes. |
| `mobile-crowdin-sync.yml` | Manual and schedule; `contents: write`, `pull-requests: write`; Crowdin token | No recent fork run | **Remove in Task 1.2.** It can create translation commits/PRs using an official service the fork does not own. |
| `mobile-lint.yml` | Mobile-changing PR and manual; `contents: read`; no secrets; broad Linux Flutter/Rust/test workload | Two PR failures; latest run passed 416 tests but failed 12 fork release-tool tests because Linux lacks `plutil` and two temporary directories were not mode `0700` | **Replace in Task 2.1.** Formatting, analysis, and fork tests matter, but platform-specific contracts must not be forced through one broad Linux test sweep. |
| `mobile-podfile-lock.yml` | Mobile dependency/iOS changes and manual; `contents: read`; no secrets; macOS | One PR failure; Photos failed first because deployment mode recalculated Flutter plugin podspec checksums | **Replace in Task 2.2.** Deterministic self-hosted iOS dependencies matter, but the fork needs a focused, reproducible Photos contract rather than all official mobile apps. |
| `photos-build.yml` | Push, manual, schedule; `contents: write`; Android, Apple, Firebase, GitHub App, and notification secrets | Two scheduled failures; Android signing material was invalid/absent and iOS pod installation failed | **Remove in Task 1.2.** This is official signed Photos release automation, not the fork's guarded local build/distribution path. |
| `photos-desktop-build.yml` | Push, manual, schedule; nominally `contents: read`; GitHub App, Apple, Azure, and notification secrets | Two scheduled failures; nightly token minting failed | **Remove in Task 1.2.** Desktop release automation is unrelated and depends on official credentials. |
| `rust-e2e-test.yml` | Rust-changing pull requests; `contents: read`; no secrets | One successful PR run | **Remove in Task 3.2.** Broad Rust end-to-end server coverage exceeds the selected mobile-fork boundary; mobile-used Rust generation/analysis belongs in replacement CI. |
| `rust-lint.yml` | Rust-changing pull requests; `contents: read`; no secrets | One successful PR run | **Remove in Task 3.2.** Repository-wide Rust lint is outside V1; only Rust paths required by Photos mobile will be exercised by replacement validation. |
| `server-lint.yml` | Server-changing pull requests; `contents: read`; no secrets | One successful PR run | **Remove in Task 3.2.** The fork consumes a self-hosted server but does not maintain a divergent server product. |
| `server-publish-ghcr.yml` | Manual and schedule; `contents: read`, `packages: write`; GitHub token | No recent fork run | **Remove in Task 1.2.** Publishing server containers is an external mutation outside the local mobile fork. |
| `server-release.yml` | Manual; `contents: read`; external container-registry username/password | No recent fork run | **Remove in Task 1.2.** Official server release publication is not owned by the fork. |
| `stale.yml` | Manual and schedule; `issues: write`, `pull-requests: write`, `statuses: read`; no secrets | Two successful scheduled runs | **Remove in Task 1.2.** Automatic upstream PR lifecycle mutation is unnecessary for this low-volume personal fork. |
| `upstream-sync-drift.yml` | Daily and manual; `contents: read`, `issues: write`; exact fork guard; no secrets | No recent run in the bounded history; deterministic local contracts and prior implementation validation pass | **Keep and harden in Task 2.3.** It is fork-owned, reports official drift through one issue, and cannot change source or releases. |
| `warm-caches.yml` | Manual and schedule; `contents: read`; seven Linux/macOS cache jobs; no secrets | Two scheduled failures; latest failure occurred in Go server lint | **Remove in Task 1.2.** It spends runners across unrelated products to support upstream CI that the fork is removing. |
| `web-crowdin-push-sources-and-translations.yml` | Manual; `contents: read`; Crowdin token and GitHub token | No recent fork run | **Remove in Task 1.2.** The official web translation project is outside fork ownership. |
| `web-crowdin-sync.yml` | Web push, manual, schedule; `contents: write`, `pull-requests: write`; Crowdin token | One push failure consistent with absent official Crowdin credentials | **Remove in Task 1.2.** It can author source/PR changes through an unavailable official service. |
| `web-deploy-2of3.yml` | Manual; `contents: read`; production environment and Cloudflare credentials | No recent fork run | **Remove in Task 1.2.** The fork does not deploy the official 2of3 web application. |
| `web-deploy.yml` | Manual and schedule; `contents: read`; production environment and Cloudflare credentials | Two scheduled failures; latest failed while installing/running Wrangler | **Remove in Task 1.2.** Official web deployment is unrelated even when a failure is an upstream tool issue rather than only a missing secret. |
| `web-lint.yml` | Web-changing pull requests; `contents: read`; no secrets | One successful PR run | **Remove in Task 3.2.** A successful but unrelated web lint does not protect the self-hosted mobile applications. |
| `web-publish-ghcr.yml` | Manual and schedule; `contents: read`, `packages: write`; GitHub token | No recent fork run | **Remove in Task 1.2.** Publishing web containers is an external mutation outside fork scope. |
| `workflow-security-checks.yml` | Workflow/action-changing pull requests; `contents: read`; protected approval environment; no secrets | One successful PR run; the same trusted checker passes locally across all 40 workflow/action files | **Keep and harden in Tasks 2.3 and 3.3.** It is fork-owned and already protects action pinning and permissions; it will also enforce the final allowlist. |

The final count is internally consistent: 23 workflows are removed in the
risk-first Task 1.2; nine read-only but unrelated checks are removed in Task
3.2; `mobile-lint.yml`, `mobile-podfile-lock.yml`, `dependency-review.yml`, and
`codeql.yml` are replaced or adapted; and `upstream-sync-drift.yml` plus
`workflow-security-checks.yml` are retained and hardened. The replacement
Linux and macOS fork workflows do not exist yet and therefore are not included
in the 38-file inherited inventory.

---

## 4. Future work / out-of-scope

> Single source of truth for everything that is NOT in V1. Items move into V1
> only with explicit owner approval and a decision-log entry.

| Item | Status | Why |
|------|--------|-----|
| Add unsigned Android debug and iOS Simulator builds to pull-request CI | V1.1 backlog | The selected thorough V1 validates source and packaging contracts without the runner cost of complete platform builds; builds can be added after the stable check set is measured. |
| Add retained test artifacts, trend dashboards, or runner-cost reports | V1.1 backlog | V1 relies on concise Actions logs and summaries; historical reporting is useful only after the workflow set is stable. |
| Use private or self-hosted GitHub Actions runners | V1.1 backlog | Hosted runners avoid a new privileged machine and credential-maintenance boundary during cleanup. |
| Recreate official Ente deployment, release, app-store, container, translation, documentation-site, or cache-warming automation | Out of scope | Those workflows serve official Ente infrastructure and products rather than this private self-hosted mobile fork. |
| Preserve broad CI for Ensu, Auth, Locker, desktop Photos, web, server, Rust, documentation, or staff infrastructure | Out of scope | The selected problem framing protects the self-hosted Android and iOS Photos applications and their maintenance automation. |
| Put Firebase, Apple, signing, server, tester, Tailscale, Crowdin, Cloudflare, or deployment credentials in GitHub Actions | Out of scope | Private application distribution and operations remain guarded local owner workflows with secrets outside this public repository. |
| Automatically approve, merge, sign, publish, deploy, or synchronize source | Out of scope | Owner review and explicit local confirmations remain hard mutation boundaries. |

**Status values:**

- `V1.1 backlog` — deferred but planned for the next milestone.
- `Out of scope` — will not be done in this initiative; distinct from deferred
  work.

---

## 5. Decision log

> Append-only. Newest entries stay on top. Never delete an entry; if a decision
> changes, add a newer entry explaining the reversal.

### 2026-07-22 — Remove 32 inherited workflows and replace four broad checks

**Decision:** Remove 23 mutation-capable or scheduled workflows in the first
risk-reduction task and nine unrelated read-only checks after replacement CI
exists. Replace or adapt mobile lint, Podfile verification, dependency review,
and CodeQL; retain and harden only upstream drift and workflow security.

**Why:** The complete 38-file audit shows that official releases, deployments,
translations, cache warming, products, and monorepo checks either fail for
expected infrastructure reasons or succeed without protecting this fork.
Six workflows map directly to the selected mobile, dependency, workflow, and
upstream-maintenance scope.

**Alternatives considered:** Retain successful unrelated checks, which still
consume runners and enlarge the security surface; or disable files in GitHub
while keeping them in source, which hides rather than removes the ambiguity and
allows upstream edits to remain silently present.

### 2026-07-22 — Integrate workflow maintenance with current fork documentation

**Decision:** Link this effort and its as-built companion to the fork overview,
self-hosted mobile index, upstream synchronization runbook and architecture,
workflow security contracts, and relevant build/test scripts.

**Why:** GitHub Actions are part of the fork's maintenance and security model,
not an isolated subsystem. A future maintainer should reach the active policy
from the same entry points used for builds and upstream catch-up.

**Alternatives considered:** A workflow-only document, which would be easier to
miss, and minimal standalone records, which would duplicate existing context
and weaken traceability.

### 2026-07-22 — Fail closed on every fork-owned check

**Decision:** Treat retained mobile, dependency, workflow-security, and
allowlist failures as merge-blocking defects from V1, with least privilege,
SHA-pinned actions, and no operational secrets.

**Why:** A green check must mean the protected behavior passed. Advisory or
ignored failures would recreate the noisy Actions surface this initiative is
removing.

**Alternatives considered:** An advisory rollout, which permits regressions
during transition, and mixed enforcement, which protects workflows while
allowing mobile or dependency failures into `main`.

### 2026-07-22 — Produce an as-built GitHub Actions architecture companion

**Decision:** End V1 with `ForkGitHubActionsArchitecture.md` describing the
settled workflow set, triggers, permissions, path filters, failures, rollback,
and future upstream adoption process.

**Why:** Multiple workflows, repository settings, permission boundaries, and
an upstream-reintroduction guard interact. A settled companion will be more
useful than reconstructing the final system from task history.

**Alternatives considered:** Keep architecture only in this living record,
which would mix historical implementation decisions with current maintenance
instructions.

### 2026-07-22 — Implement risk-first with pause-safe task boundaries

**Decision:** Audit first; remove mutation-capable and scheduled inherited
automation before building the replacement; then harden security, prune the
remaining checks, enforce the allowlist, and run controlled live validation.

**Why:** The inherited set is actively producing scheduled failures and
contains official deployment and release surfaces. Each task should leave a
reviewable state that can be reverted without operational side effects.

**Alternatives considered:** Replacement-first, which keeps noisy and
potentially dangerous workflows active longer, and one atomic replacement,
which is harder to review, diagnose, and roll back.

### 2026-07-22 — Replace inherited automation with a fork-owned allowlist

**Decision:** Delete irrelevant inherited workflow files, introduce focused
fork workflows, and test the exact allowed set so upstream synchronization
cannot silently reactivate automation.

**Why:** Keeping or merely skipping dozens of official workflows leaves a
large security and maintenance surface and a confusing Actions page. Explicit
adoption makes each workflow intentional.

**Alternatives considered:** Repair inherited core workflows in place, which
retains broad upstream assumptions, and guard every inherited workflow to the
official repository, which preserves clutter and skipped runs.

### 2026-07-22 — Deliver a thorough source-validation V1 without platform builds

**Decision:** Retain upstream drift, workflow security, dependency security,
focused self-hosted mobile tests, formatting, full mobile analysis, and macOS
Podfile verification. Do not build signed or unsigned Android/iOS applications
in V1 CI.

**Why:** This catches the fork's likely source and dependency regressions while
avoiding long, unrelated official builds and all signing/publication state.

**Alternatives considered:** A narrow focused-test-only V1, which misses broad
Flutter or dependency regressions, and a strategic V1 with Android and iOS
builds, which adds substantial hosted-runner use before the core workflow set
is stable.

### 2026-07-22 — Frame CI around self-hosted Photos mobile reliability

**Decision:** GitHub Actions in this fork serve the self-hosted Android and iOS
Ente Photos clients, their documentation and security boundaries, and guarded
upstream synchronization.

**Why:** This is the fork's stated purpose. Most inherited failures come from
official Ente products, production infrastructure, and secrets the fork does
not own.

**Alternatives considered:** Broad monorepo integrity, which consumes runners
and maintenance effort on unrelated systems, and upstream CI parity, which
would require recreating official Ente infrastructure and credentials.

---

## 6. Open questions

_Add new questions as they arise. Move resolved questions to §5 once answered,
with the resolution as the decision._

- Which supported CodeQL languages and dependency manifests yield actionable
  coverage for the fork after repository security settings are audited?
- Does fork `main` already have branch protection or rulesets, and which final
  check names must become required after controlled live validation?
- Does deterministic self-hosted CocoaPods verification require a fork-owned
  lockfile preparation step, or only a corrected working directory and tool
  contract on the macOS runner?

---

## 7. Lessons learned

> Populated at the end of each phase. Surprises, anti-patterns discovered, and
> things to do differently next time.

_Empty until first phase completes._
