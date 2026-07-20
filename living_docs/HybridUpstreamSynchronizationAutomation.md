# Hybrid Upstream Synchronization Automation

**Status:** Implementation complete; awaiting owner review through the fork pull request.
**Started:** 2026-07-20
**Owner:** vanton
**Planning doc:** n/a
**Companion docs:** `living_docs/UpstreamEnteSynchronization.md`, `living_docs/UpstreamEnteSynchronizationArchitecture.md`, `mobile/apps/photos/SELF_HOSTED_BUILD_GUIDE.md`

---

## 1. Phase / Task tracker

| Phase | Task | Title | Size | Status | Notes |
|------:|----:|-------|:----:|--------|-------|
| 1 | 1.1 | Add a read-only command that reports upstream drift and local readiness | M | 🟢 done | Added `./scripts/sync_upstream.sh check` with optional `--no-fetch` and `--json` output. It validates the exact fork/official GitHub identities and disabled upstream push URL before network reads; checks branch/worktree and local-versus-origin `main`; resolves fork, official, and merge-base SHAs; reports left/right divergence and ancestry; and exits distinctly when not ready. Five deterministic tests with 17 assertions cover supported Git URL forms, non-GitHub rejection, healthy drift, dirty state, and unsafe upstream push. Syntax/help checks pass, and a real non-mutating invocation correctly rejected the feature branch and dirty implementation tree while reporting five current upstream-only commits. |
| 1 | 1.2 | Add guarded integration-branch creation and exact-SHA merge | M | 🟢 done | Added `start` and `resume`. Start repeats the full preflight, optionally pins the expected official SHA, creates `sync/upstream-YYYY-MM-DD-<official-sha>` only when absent, merges with `--no-ff`, and verifies official ancestry. Conflicts remain on the new branch with explicit file, resume, and abort guidance; no automatic abort exists. Resume accepts only a sync branch, refuses unresolved or unstaged work, checks staged/unstaged whitespace, commits the preserved merge only after a complete staged resolution, and verifies an already completed merge before validation. Six new deterministic cases cover clean merge, branch collision, conflict preservation, SHA mismatch, unresolved resume, and staged resume; all 11 tests/38 assertions and CLI syntax/help checks pass. |
| 2 | 2.1 | Add dependency, test, analysis, and optional platform-build gates | M | 🟢 done | Added `validate` with streamed named gates and `--with-builds`. It accepts only a completed clean sync merge, verifies the official second parent/ancestry, initializes recursive submodules, restores the enforced Flutter lock, runs Rust generation twice with drift checks, verifies CocoaPods in deployment mode, runs the 10-file regression suite plus four endpoint files in configurable and locked modes, formats tracked Dart files in bounded batches, and analyzes the full mobile workspace. Optional builds use only the guarded Android debug and iOS Simulator wrappers with `https://photos.example.com`. Tool resolution honors pinned executable overrides and stops on missing inputs. Three new validator cases cover the default 10-step plan, guarded optional builds/public endpoint, and immediate source-drift stop; all 14 tests/52 assertions and warning-level syntax/help checks pass. |
| 2 | 2.2 | Add confirmed push, pull-request creation, and issue handoff | M | 🟢 done | Added `publish` and the conflict-free `run` fast path. Publication always reruns validation, binds its evidence to the current branch/commit/official merge, verifies every fork/official fetch and push URL, refetches unchanged fork `main`, authenticates GitHub CLI, rejects remote-branch or PR ambiguity, and resolves zero or one marker-based drift issue. It prints exact SHAs and requires `PUSH <branch>`, then repeats the complete preflight before mutation. Upload uses the canonical fork SSH URL directly, verifies the remote SHA, creates one fork PR with validation evidence and optional `Closes #N`, and never merges. Matching remote branches and open PRs are safely resumable. Repair commits above the verified upstream merge are supported without weakening second-parent provenance. Seven new cases cover merge provenance, confirmation refusal, fork-only SSH push/linked PR, push-resume, mismatched remote state, and duplicate issues; all 21 tests/78 assertions plus warning-level syntax, help, and whitespace checks pass. |
| 3 | 3.1 | Add scheduled GitHub drift detection with one tracking issue | M | 🟢 done | Added a daily 06:17 UTC and manual workflow guarded to `vanton1/ente`, with only `contents: read` and `issues: write`, full-history checkout, disabled official push, a ten-minute timeout, non-cancelling concurrency, and SHA-pinned checkout/GitHub-script actions. It runs the same guarded read-only checker into runner-temporary storage, then a dependency-free reconciler validates the schema and commit evidence. One invisible marker identifies the open tracker: official drift creates or updates it with exact SHAs/counts and the pinned local command; zero drift comments and closes it; duplicate markers or invalid evidence fail closed. The workflow security checker passes across all 40 workflow/action files, YAML and Node syntax load successfully, the report/body smoke check passes, and whitespace is clean. |
| 3 | 3.2 | Test safe runs, failures, issue idempotency, and recovery | M | 🟢 done | Added one executable offline test entry point and expanded standard-library coverage to 33 Ruby cases/141 assertions plus six Node cases. Real temporary Git repositories prove clean exact-SHA merge ancestry, conflict preservation with `MERGE_HEAD` and markers intact, and safe resume after a reviewed repair commit. Unit cases now cover no-change, dirty state, unsafe upstream push, branch collision, SHA mismatch, unresolved/staged resume, source and post-generation drift, optional guarded builds, missing complete toolchain, mismatched validation, typed-confirmation refusal, state changes during confirmation, canonical SSH push, upload/PR retry, existing PR reuse, and duplicate issue refusal. Node tests prove create/update/close/no-op issue idempotency and invalid/duplicate fail-closed behavior. Workflow contract tests pin exact triggers, fork identity, permissions, action SHAs, disabled upstream push, absent source mutation, and shared marker. `./scripts/test_upstream_sync.sh` passes syntax, 39 behavioral cases, workflow security across 40 files, and whitespace checks without network or external writes. |
| 3 | 3.3 | Document the one-command operator and recovery workflow | S | 🟢 done | Added root-level `UPSTREAM_SYNC.md` as the canonical operator runbook and linked it from the self-hosted index and architecture. It documents the daily/manual issue lifecycle, trusted-Mac prerequisites, exact remote quarantine, read-only check, issue-pinned one-command path, optional builds, all eleven guarded stages, conflict/resume/repair behavior, validation and generation recovery, confirmation/state-change refusal, upload-without-PR retry, existing PR reuse, collision handling, review/merge and release boundaries, command/exit reference, offline self-test, and privacy boundary. The documentation ownership table now separates the command runbook from explanatory architecture and historical records. Two new documentation contract cases verify every local link and all six operator states, hard merge boundary, public build origin, and test entry point; all six combined workflow/documentation cases/67 assertions, CLI help, syntax, and whitespace checks pass. |
| 3 | 3.4 | Update the as-built synchronization architecture | S | 🟢 done | Replaced the obsolete manual-sequence companion with the as-built hybrid architecture while retaining the first full catch-up evidence. It now records all system invariants; workflow/reconciler/CLI/library/test components; remote and two-parent merge provenance; repair-commit-aware integration discovery; direct canonical fork SSH upload; complete local state machine; ten default and two optional validation gates; double preflight and exact confirmation; upload/PR retry semantics; daily detector identity, concurrency, temporary report, marker lifecycle, and exact permission matrix; failure/evidence/rollback paths; observability/privacy/release separation; and current offline verification scope. Cross-links distinguish architecture, operator procedure, mobile operations, and historical execution. The full suite passes 35 Ruby cases/184 assertions plus six Node cases, all syntax checks, workflow security across 40 files, whitespace, link/command contracts, and targeted private-value scan. |

**Legend:** ⚪ not started · 🟡 working · 🟢 done · 🔴 blocked / needs decision
**Size:** XS · S · M · L · XL (never days or weeks).

One task = one row = one reviewable step. Mark a row 🟡 working before starting
it and 🟢 done only after its acceptance evidence passes. Task naming follows
`Task <phase>.<sub> — <short imperative title>` and commits, when requested,
mirror that title.

---

## 2. Goal

Make recurring official Ente catch-up fast for the fork owner without allowing
automation to mutate fork `main` or hide integration risk. V1 is complete when
a minimal-permission GitHub workflow persistently reports official upstream
drift through exactly one issue, and one local command can safely inspect,
merge, validate, push, and open a reviewable fork PR on the conflict-free path.
Dirty state, conflicts, generated drift, failed checks, missing tools, unsafe
remotes, or ambiguous GitHub results stop closed with the integration branch
and diagnostics preserved. Success is observable through an idempotent drift
issue, a clean source-preserving PR, deterministic local test evidence, and no
automatic merge or application/distribution/server mutation.

The primary user is the fork owner running occasional maintenance from the
trusted development Mac. The GitHub detector runs unattended only to report
drift; it never authors source history. There is no production latency or
throughput SLO. The detector should use one full-history checkout/fetch and
bounded issue pagination, while the local command reports each long-running
gate so failures are diagnosable.

---

## 3. Architecture / approach

The selected hybrid splits observation from mutation:

```text
scheduled/manual GitHub workflow
        |
        | fetch official main, compare ancestry
        v
one marker-based drift issue
        |
        | owner runs local command
        v
read-only preflight -> exact-SHA sync branch -> merge -> validation
                                                    |
                                      typed confirmation only
                                                    v
                                         origin branch + PR
                                                    |
                                          owner reviews/merges
```

The GitHub workflow is fork-specific, action-SHA pinned, and guarded by exact
repository identity. Its default token receives only `contents: read` and
`issues: write`. It reads official history and manages one issue recognized by
a stable invisible marker. It neither checks out untrusted issue/PR content nor
receives pull-request, release, package, deployment, or administration write
permissions.

The local implementation will use repository-contained standard-library code
behind one executable wrapper. Its read-only preflight verifies:

- current branch and worktree are safe;
- local fork `main` equals fetched `origin/main`;
- `origin` is the configured personal fork and the only push target;
- `upstream` fetches official Ente and its push URL is disabled;
- exact fork, official, and merge-base SHAs plus left/right divergence;
- required Git, GitHub CLI, Flutter/Dart, rustup Rust/Cargo, CocoaPods, Xcode,
  Android, and JDK inputs for the selected gates; and
- whether official history is already contained in fork `main`.

The mutating path records the official SHA, creates a collision-safe dated
branch, and merges that SHA without rebasing, squashing, or force operations.
Conflict or validation failure leaves the branch and evidence intact. The
command never auto-resolves semantic conflicts, hand-edits generated output,
deletes a failure branch, or changes `main`. Dependency commands run in
verification-oriented modes; unexpected tracked drift pauses for review.

The validation path uses `https://photos.example.com`, reuses existing focused
self-hosted tests and guarded platform wrappers, and keeps expensive Android
debug and iOS Simulator builds opt-in. Successful validation permits—but does
not perform—push/PR mutation until the owner types the exact displayed
confirmation. PR creation targets only fork `main`, includes the exact SHAs and
validation summary, and links the open marker issue when exactly one exists.

The workflow and local command emit concise state summaries and distinct exit
codes. Logs and PR/issue content exclude private endpoints, Firebase bindings,
Apple identifiers, credentials, tester identities, artifacts, and receipts.
There is no new personal-data flow, compliance obligation, or application
runtime behavior.

---

## 4. Future work / out-of-scope

> Single source of truth for everything that is NOT in V1. Items move into V1
> only with explicit owner approval and a decision-log entry.

| Item | Status | Why |
|---|---|---|
| Add resumable machine-readable run manifests and historical dashboards | V1.1 backlog | V1 preserves human-readable branch and terminal evidence; structured execution history is useful only after the stable command states are proven. |
| Automatically clean merged or abandoned synchronization branches | V1.1 backlog | Failure evidence must be preserved in V1, and deletion policy is safer after real operating experience. |
| Automatically create a draft merge branch or PR in GitHub | Out of scope | Source mutation belongs to the trusted local command; unattended branch creation weakens provenance and conflict handling. |
| Automatically merge a synchronization PR | Out of scope | Owner review is a hard boundary because upstream changes can be semantically incompatible despite passing Git checks. |
| Publish applications or advance Android/iOS build ledgers | Out of scope | Source synchronization and closed-beta distribution have separate signing, server-health, evidence, and approval contracts. |
| Change Apple, Firebase, Tailscale, Museum, object storage, devices, or accounts | Out of scope | None of these external systems is required to detect or integrate source history. |
| Rewrite, squash, rebase, force-push, or reset published fork history | Out of scope | Full ancestry and existing source/release provenance must remain valid. |

**Status values:**

- `V1.1 backlog` — deferred but planned for the next milestone.
- `Out of scope` — will not be done in this initiative; distinct from deferred
  work.

---

## 5. Decision log

> Append-only. Newest entries stay on top. Never delete an entry; if a decision
> changes, add a newer entry explaining the reversal.

### 2026-07-20 — Link existing source-sync records and update the established architecture

**Decision:** Create a focused automation living record, link the completed
manual synchronization record and canonical build guide, and update the
existing upstream-synchronization architecture as the final task.

**Why:** Automation has its own permissions, CLI states, issue lifecycle, and
tests, while the existing architecture is already the canonical settled
description of upstream catch-up.

**Alternatives considered:** Extend the completed manual execution record,
which would mix two initiatives; or create a second architecture companion,
which would duplicate the same maintenance system.

### 2026-07-20 — Fail closed and preserve failure evidence

**Decision:** Every unsafe precondition, merge conflict, unexpected generated
change, failed gate, or ambiguous GitHub result stops the command while leaving
the integration branch and diagnostics available for inspection.

**Why:** Automatic rollback can erase the exact evidence needed to reconcile a
large upstream change. A failed local branch does not affect accepted `main`.

**Alternatives considered:** Automatically abort and delete the branch, which
loses evidence; or push a failing draft PR, which externalizes unvalidated
source and creates noisy recovery states.

### 2026-07-20 — Implement risk-first, pause-safe phases

**Decision:** Prove read-only local inspection first, then guarded merge,
validation, confirmed publication, GitHub detection, full failure tests, and
documentation.

**Why:** The local mutating boundary is the highest source-history risk. Each
phase remains useful and leaves fork `main` untouched if work pauses.

**Alternatives considered:** Add notifications first, which initially points to
a manual remedy; or build a thin end-to-end path before guards, which exposes a
temporarily weak synchronization command.

### 2026-07-20 — Use one marker-based tracking issue

**Decision:** The scheduled workflow opens or updates one persistent issue when
upstream is ahead. The local PR links that issue; a later zero-drift detector
run closes it.

**Why:** An issue provides durable, visible state without allowing unattended
source branches or merge commits.

**Alternatives considered:** Automatic draft PR creation, which complicates
provenance and conflicts; or Actions-summary-only reporting, which is easy to
miss and has no durable handoff.

### 2026-07-20 — Deliver the thorough validation scope

**Decision:** Include scheduled/manual detection, a guarded local command,
dependency/generation verification, focused tests, full analysis, optional
platform builds, confirmed push, PR creation, recovery guidance, and current
documentation.

**Why:** A fast merge-only command would recreate the semantic and toolchain
drift found during the first 1,014-commit catch-up.

**Alternatives considered:** Lightweight merge/PR checks, which leave important
validation manual; or resumable manifests and cleanup automation, which add
state machinery before the core workflow is proven.

### 2026-07-20 — Reverse the initial local-only framing in favor of hybrid detection

**Decision:** Use GitHub only for minimal-permission drift detection and issue
state, while all source mutation remains in a manually invoked local command.

**Why:** The owner wants proactive awareness without entrusting merge conflict
resolution, toolchains, or source publication to an unattended runner.

**Alternatives considered:** A fully local command, which depends on the owner
remembering to check; or full GitHub automation, which makes conflicts,
workflow permissions, and long mobile validation harder to control.

---

## 6. Open questions

_None. Later permission or platform constraints that cannot preserve the
fail-closed boundary stop the applicable task before scope changes._

---

## 7. Lessons learned

- Remote identity validation must precede even a read-only fetch. Treating
  remote-reference updates as harmless before confirming both GitHub slugs and
  the disabled official push URL would let a misconfigured checkout inspect or
  later merge the wrong repository.
- A dated branch name alone is not collision-safe when a failed run is
  preserved. Adding the official SHA makes the attempted source explicit, and
  refusing to reuse the name prevents a later run from overwriting conflict
  evidence.
- Dependency regeneration is safest as verification, not silent repair. Using
  enforced/deployment modes and checking Git after every mutating generator
  keeps the fast path automatic while forcing semantic or generated changes
  into an explicit reviewed repair commit.
