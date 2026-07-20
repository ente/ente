# Upstream Ente Synchronization Architecture

**Status:** As-built hybrid maintenance architecture, verified 2026-07-20

This document explains how the fork detects and absorbs official Ente changes
without losing the configurable self-hosted mobile applications, rewriting
published history, or entrusting semantic integration to an unattended runner.
It describes components, state, permissions, provenance, and failure behavior.
Use the [operator runbook](../UPSTREAM_SYNC.md) for current commands.

Related documents:

- [Canonical operator runbook](../UPSTREAM_SYNC.md)
- [Self-hosted mobile documentation index](../mobile/apps/photos/SELF_HOSTED_DOCUMENTATION.md)
- [Configurable-server architecture](ConfigurableSelfHostedMobileServerArchitecture.md)
- [First full synchronization record](UpstreamEnteSynchronization.md)
- [Hybrid automation implementation record](HybridUpstreamSynchronizationAutomation.md)
- [Mobile build guide](../mobile/apps/photos/SELF_HOSTED_BUILD_GUIDE.md)

## 1. System invariants

Every detector and local synchronization preserves these properties:

- Official Ente history and the fork's published history remain reachable.
- `origin` identifies only `vanton1/ente`; `upstream` fetches only `ente/ente`
  and its sole push URL is the disabled sentinel `DISABLED`.
- Fork `main` remains the last owner-accepted state while integration occurs on
  `sync/upstream-YYYY-MM-DD-<official-sha-prefix>`.
- Unattended GitHub automation observes history and manages one issue. It does
  not create source branches, commits, pull requests, or releases.
- Local source mutation merges one recorded official SHA with `--no-ff`. It
  never rebases, squashes, force-pushes, resets accepted history, or
  automatically resolves a conflict.
- Android keeps release package `me.vanton.ente.photos.selfhosted` and the
  normal debug `.debug` suffix.
- iOS keeps bundle `me.vanton.ente.photos.selfhosted` on the core-only
  `SelfHostedRunner` target and shared `selfhosted` scheme.
- Both platforms retain the configurable HTTPS Museum policy, authoritative
  stored binding, fail-closed startup, logout-before-switching transaction,
  and same-origin authenticated Museum networking.
- Validation uses the public non-operational origin
  `https://photos.example.com`; no private deployment binding enters source,
  issues, pull requests, or logs.
- Synchronization does not sign or publish mobile releases, advance Firebase
  build ledgers, change Apple/Firebase/server state, or install on devices.
- The generated fork pull request remains open until the owner reviews and
  merges it through the normal GitHub path.

## 2. Component model

The hybrid design separates persistent observation from trusted mutation:

```text
GitHub schedule / manual dispatch
              |
              v
  read fork main + official main
              |
              v
 one marker-based drift issue
              |
              | exact official SHA and local command
              v
 trusted Mac: check -> merge -> validate -> confirm -> fork PR
                                                    |
                                                    v
                                             owner review/merge
                                                    |
                                                    v
                              linked PR or next detector closes issue
```

| Component | Responsibility | Mutation boundary |
|---|---|---|
| `.github/workflows/upstream-sync-drift.yml` | Daily/manual fork-only orchestration, full-history checkout, official fetch, guarded drift report, issue reconciliation | May write issues only |
| `.github/scripts/upstream-sync-issue.cjs` | Validate schema/SHA/count evidence; create, update, no-op, or close exactly one marker issue | GitHub issue API only |
| `scripts/sync_upstream.sh` | Stable operator entry point for `check`, `start`, `resume`, `validate`, `publish`, and `run` | Depends on selected state; never writes fork `main` directly |
| `scripts/upstream_sync.rb` | CLI parsing, diagnostics, exit classification, and command composition | Delegates to guarded library objects |
| `scripts/lib/upstream_sync.rb` | Remote inspection, exact-SHA integration, merge provenance, validation, confirmation, upload, and PR creation | Local sync branch, canonical fork branch, and one fork PR |
| `scripts/test_upstream_sync.sh` | Offline unit, real-Git integration, issue, workflow-contract, syntax, security, and whitespace verification | Temporary local repositories only |

All subprocesses use argument arrays rather than shell-composed GitHub data.
Long validation and push operations stream named output; recent failure output
is retained in classified diagnostics.

## 3. Remote and provenance model

The read-only inspector validates repository identities before fetching. It
requires a clean local `main`, resolves local `main`, `origin/main`, and
`upstream/main`, and reports merge base, fork-only count, upstream-only count,
and official ancestry. Local `main` must exactly equal fetched `origin/main`.
JSON output uses a versioned schema shared by the scheduled detector.

The integration branch begins at the recorded fork SHA and merges the recorded
official SHA with an explicit message:

```text
Merge official Ente main at <40-character-official-sha>
```

`IntegrationState` does not trust the current commit to be the merge. It scans
first-parent merge history for that exact message, requires exactly two
parents, and requires the recorded official SHA to be the second parent. This
supports reviewed compatibility commits above the merge while rejecting a
lookalike message or unrelated parent.

Publication tightens the boundary again. It checks every configured fetch and
push URL, refetches `origin/main`, and requires it to remain the merge's first
parent. Both fork and official SHAs must be ancestors of the validated commit.
The remote synchronization branch must be absent or already equal to that
commit; another SHA is never overwritten.

The upload addresses `git@github.com:vanton1/ente.git` directly after validating
the configured fork identity. This avoids broadening GitHub CLI OAuth workflow
scope while making the only push destination explicit. The pushed SHA is read
back through `origin` before PR creation. No force option exists.

## 4. Local state machine

```text
CLEAN_FORK_MAIN
      |
      | check/fetch/remotes/SHAs
      v
READY --------------------------> ALREADY_SYNCHRONIZED
      |
      | start exact SHA
      v
MERGING -------- conflict ------> PAUSED_MERGE
      |                                |
      | clean merge                    | manual resolve + stage + resume
      +-------------------------------+
      v
INTEGRATED
      |
      | dependency/generation/behavior/analysis gates
      +-------- failure ----------> PAUSED_REPAIR
      |                                |
      |                                | reviewed repair commit + validate
      +--------------------------------+
      v
VALIDATED
      |
      | GitHub/remote preflight + typed PUSH confirmation
      +-------- mismatch/change --> PAUSED_PUBLICATION
      |
      | repeat preflight, upload/verify, PR create
      v
OPEN_FORK_PR ---- owner merge ----> ACCEPTED_FORK_MAIN
        |                             |
        | Closes #N                  | next detector fallback
        +-----------------------------+
                                      v
                                CLOSED_DRIFT_ISSUE
```

Branch-name collisions preserve earlier evidence and stop. A merge conflict
keeps the new branch, conflict markers, unresolved paths, and `MERGE_HEAD`.
`resume` accepts only the sync prefix, refuses unresolved or unstaged work,
checks staged and unstaged whitespace, and commits only a complete resolution.
It can also verify an already completed merge and later repair commits.

The one-command `run` covers the conflict-free path. The staged commands expose
the same state transitions for recovery. No automatic rollback erases a
failure branch; explicit `git merge --abort` remains an owner action only while
the merge is active.

## 5. Validation architecture

Validation accepts only a clean completed sync branch and binds its result to
the exact branch, current commit, verified official SHA, build choice, and
ordered successful steps. The default gates are:

1. initialize recursive submodules and prove no source drift;
2. restore the locked Flutter workspace with `--enforce-lockfile` and prove no
   drift;
3. generate Rust/Flutter bindings with rustup Cargo and prove no drift;
4. generate the same bindings again and prove byte-stable source;
5. verify Photos CocoaPods with `pod install --deployment` and prove no drift;
6. run the combined ten-file self-hosted regression suite;
7. run endpoint behavior in configurable mode using the public example;
8. run the same endpoint behavior in locked compatibility mode;
9. check all tracked Dart formatting in bounded argument batches; and
10. analyze the complete mobile workspace.

`--with-builds` adds only the guarded Android debug wrapper and iOS Simulator
wrapper, again with source-drift checks. It does not build signed release
artifacts. Missing Git, GitHub CLI, Flutter/Dart, Cargo, CocoaPods, or selected
platform tools stops before publication. Environment overrides allow pinned
`FLUTTER_BIN`, `DART_BIN`, `CARGO_BIN`, `POD_BIN`, and `GH_BIN` paths without
recording workstation locations in Git.

Unexpected generator, dependency, formatter, test, analysis, or build output
never becomes an implicit fix. The operator must inspect and commit an
intentional compatibility repair, after which validation discovers the same
verified merge beneath that repair commit.

## 6. Publication and idempotence

Standalone `publish` reruns the complete selected validation, so evidence from
another commit cannot be reused. `run` performs validation once immediately
before the same publication preflight. Publication resolves GitHub state before
showing this sole mutation authorization:

```text
PUSH <exact-sync-branch>
```

There is no `--yes`, environment bypass, or automatic confirmation. After the
operator types it, the complete local, remote, ancestry, GitHub-auth, branch,
PR, and issue preflight runs again. Any change stops before upload.

The PR targets `vanton1/ente:main` and records fork base, official SHA,
validated commit, validation count, and optional-build result. If exactly one
open marker issue exists, `Closes #N` creates the durable handoff. The command
does not approve or merge the PR.

Publication is retry-safe at its two partial boundaries:

- If a matching remote branch already exists but no PR does, it is verified and
  reused without upload before creating the PR.
- If one matching open PR already exists, its URL is returned without another
  confirmation or mutation.

A mismatched remote SHA, non-open PR with the same branch, mismatched PR head,
multiple PRs, or multiple marker issues is ambiguous and fails closed. This
preserves evidence instead of guessing whether to overwrite or duplicate it.

## 7. Scheduled detector and permission model

The detector runs daily at 06:17 UTC and through `workflow_dispatch`. Its job
condition is the exact repository identity `vanton1/ente`; copied upstream or
another fork skips the job. Concurrency is non-cancelling so a newer scheduled
event cannot interrupt an issue mutation halfway through. Runtime is capped at
ten minutes.

The workflow checks out fork `main` with complete history and
`persist-credentials: false`, creates an official HTTPS fetch remote, sets its
push URL to `DISABLED`, and uses the local `check --no-fetch --json` contract.
The report is written under runner-temporary storage so the repository remains
clean. Both external actions are pinned to full 40-character SHAs.

| GitHub token permission | Level | Purpose |
|---|---|---|
| `contents` | `read` | Check out fork source and compare Git history |
| `issues` | `write` | Create, update, comment on, or close the one drift tracker |
| Pull requests, workflows, actions, checks, statuses, packages, releases, deployments, administration | none | Not required and intentionally unavailable |

The issue reconciler validates schema version, readiness, three full SHAs, and
non-negative integer divergence before reading issues. It paginates all open
issues, excludes pull requests, and recognizes the invisible marker
`<!-- ente-upstream-sync -->`. Zero markers permits create/no-op, one permits
update/close, and more than one stops without mutation. When drift becomes
zero, the detector comments with the contained official SHA and closes the
tracker. A later new drift creates a new open tracker rather than reopening
historical evidence.

## 8. Failure, evidence, and rollback boundaries

| Failure | Preserved evidence | Allowed recovery |
|---|---|---|
| Unsafe remote, branch, dirty tree, stale fork `main`, or requested-SHA mismatch | Existing repository untouched plus exact diagnostic | Correct the precondition and rerun `check`; never bypass identity checks |
| Integration branch collision | Existing branch and attempt untouched | Inspect it; resume it or deliberately start a distinct later attempt |
| Merge conflict | Sync branch, conflict files, `MERGE_HEAD`, official SHA | Resolve/stage/review, then `resume`; explicitly abort only if the merge selection was wrong |
| Dependency or generated drift | Working changes and named failing gate | Pin merged tools, inspect changes, commit intentional repairs, revalidate |
| Test, analysis, or optional build failure | Clean/repair branch and streamed command evidence | Repair on the same branch and revalidate; do not publish failing source |
| Confirmation mismatch or state change | Validated local branch; no external mutation | Reinspect and run `publish` again |
| Push succeeds, PR creation fails | Exact verified fork branch | Rerun `publish`; reuse the same SHA without uploading |
| Ambiguous issue/branch/PR | All local and GitHub evidence untouched | Resolve ambiguity manually and use a new branch where required |
| Owner rejects PR | Open/closed PR and source branch remain review evidence | Close without merging; future sync starts from accepted fork `main` |

No recovery path rewrites accepted or published history. Branch deletion is an
owner retention decision outside the synchronizer.

## 9. Observability, privacy, and release separation

Readiness text and schema-v1 JSON expose repository root, branch, remote URLs,
fetch status, fork/official/merge-base SHAs, divergence, ancestry, and problems.
Validation streams step names and pass/fail state. Publication prints only
public repository coordinates, source SHAs, build-choice status, issue number,
and PR URL. The drift issue exposes the same public source evidence and pinned
operator command.

The system does not need or emit Museum credentials, recovery keys, real server
or object-storage origins, tester identities, Firebase project/App IDs, Apple
team/device/profile data, signing material, artifacts, receipts, or user media.
It introduces no application runtime path, personal-data flow, telemetry,
storage retention, or compliance obligation.

An accepted synchronization only updates fork source. Signed Android/iOS
preparation, Firebase distribution, tester notification, device registration,
and server changes remain governed by their separate runbooks and approvals.
They must start from a later accepted, clean, pushed source commit and advance
their own immutable build/evidence ledgers.

## 10. Verification evidence

The first manual full synchronization on 2026-07-20 integrated fork commit
`ed63fc138d88d9855e1ad1c10cea50747d5d0c0b` with official commit
`e184e77116dbffd825b755c0fb2e4b924f837569` from merge base
`dda1d1f790e2d9a7bd68b0cf84a7c97efb4f5374`. Its 1,014 upstream-only commits
produced one textual conflict in the generated Photos iOS lockfile. Semantic
audits also found removed framework references and an upstream iOS floor that
fork-only configurations needed to adopt. Stable generation, focused tests,
full mobile analysis, and guarded debug/Simulator builds then passed without
external mutation.

The hybrid automation is verified by `./scripts/test_upstream_sync.sh` using no
network or external writes. The current suite contains 35 Ruby cases with 184
assertions plus six Node issue cases. It covers URL identity, dirty/no-change
readiness, unsafe upstream push, collision and exact-SHA merge behavior,
preserved real-Git conflicts, staged and reviewed-repair resume, missing tools,
generator drift, endpoint modes, optional guarded builds, confirmation and
tampering, canonical fork upload, partial retry and existing-PR reuse,
issue create/update/close/idempotence/duplicates, workflow identity and minimal
permissions, action pinning, absent source mutation, documentation links,
syntax, workflow security, and whitespace.

This evidence demonstrates guard behavior and state transitions. Each future
real synchronization still requires owner review of the actual upstream diff
and the generated fork pull request.
