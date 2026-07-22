# Fork GitHub Actions Architecture

**Status:** Current as-built architecture  
**Effective:** 2026-07-22  
**Repository:** `vanton1/ente`  
**Implementation record:** [Fork GitHub Actions Maintenance](ForkGitHubActions.md)

## Purpose and boundary

GitHub Actions in this fork protect the configurable self-hosted Ente Photos
applications, dependency and workflow security, and guarded synchronization
with official `ente/ente`. They do not reproduce Ente's production CI.

No allowed workflow signs or publishes an application, uploads to Firebase,
deploys a service or website, writes translations, publishes a container,
changes Museum or network state, registers an Apple device, or receives a
private operational secret. Android and iOS release operations remain guarded
local owner procedures.

## Exact automation allowlist

The trusted checker permits exactly these files:

| Workflow | Trigger | Required pull-request check | Expensive work | Permissions |
|---|---|---|---|---|
| `self-hosted-mobile-linux.yml` | Every PR; manual | `Linux mobile gate` | Only for Photos mobile, relevant Rust, setup-action, or validator changes | `contents: read`, `pull-requests: read` |
| `self-hosted-mobile-macos.yml` | Every PR; manual | `macOS mobile gate` | macOS runner only for Photos/iOS dependency and validator changes | `contents: read`, `pull-requests: read` |
| `dependency-review.yml` | Every PR | `Dependency review gate` | Always invokes GitHub's dependency-diff API; normally completes in seconds | `contents: read` |
| `codeql.yml` | Every PR; Monday 01:22 UTC; manual | `Actions CodeQL gate` | PR analysis only when workflow or composite-action code changed; scheduled/manual analysis always runs | `contents: read`, `pull-requests: read`, `security-events: write` |
| `workflow-security-checks.yml` | Every PR | `Workflow security gate` | Trusted validation only when workflow, action, or checker policy changed | `contents: read`, `pull-requests: read` |
| `upstream-sync-drift.yml` | Daily 06:17 UTC; manual | Not a PR check | Always calculates official-upstream drift | `contents: read`, `issues: write` |

The only allowed composite action is
`.github/actions/setup-flutter/action.yml`. It installs Flutter 3.38.10 from
the official release archive after verifying the platform-specific SHA-256.

An upstream merge that restores another workflow or action fails the allowlist
until the owner explicitly reviews and adopts it. The historical disposition
of every inherited workflow is recorded in the
[implementation record](ForkGitHubActions.md#task-11-workflow-disposition-inventory).

## Pull-request flow

```text
pull request
   |
   +-- Linux gate -------- path API -- relevant? -- Flutter/Rust/test/analyze
   |                                      `------ no: stable green gate
   +-- macOS gate -------- path API -- relevant? -- macOS iOS tests + Pods
   |                                      `------ no: skipped validation + green gate
   +-- dependency gate --- GitHub dependency diff and advisory policy
   +-- Actions CodeQL ---- path API -- relevant? -- Actions analysis
   |                                      `------ no: stable green gate
   `-- workflow gate ----- path API -- relevant? -- approved trusted checker
                                          `------ no: skipped validation + green gate
```

Path detection uses the GitHub pull-request files API and paginates all files.
It is performed before Flutter, Ruby/CocoaPods, macOS, or CodeQL setup. Manual
and scheduled runs treat their owned scope as relevant. Every PR workflow
starts even for irrelevant files, because a top-level `paths` filter can leave
a required check permanently pending when GitHub skips the whole workflow.

The macOS and workflow-security workflows use a final `always()` gate. The gate
accepts a successful relevant validation or an intentional irrelevant skip,
but fails on path-detection, validation, cancellation, or ambiguous state.

## Validation responsibilities

### Linux mobile

`scripts/test_self_hosted_mobile_linux.sh` restores the locked Flutter graph,
regenerates Flutter-Rust-Bridge bindings, rejects generated drift, and runs:

- standard endpoint and Linux-portable Android release-tool contracts;
- configurable endpoint contracts with a public example HTTPS origin;
- locked endpoint contracts with the same safe example origin;
- tracked Dart formatting; and
- full mobile `flutter analyze`.

No signing key, Firebase binding, app artifact, or real server address is used.

### macOS mobile

`scripts/test_self_hosted_mobile_macos.sh` requires macOS and exactly CocoaPods
1.17.0, matching the checked-in lockfile. The workflow pins Ruby 3.3, runs the
four iOS Ad Hoc/preparation/publication/identity contract suites, and executes
`pod install --deployment` only for Photos. It does not archive, sign, register,
or publish an IPA.

### Dependency and code security

Dependency review fails closed on vulnerable dependency changes in runtime,
development, or unknown scopes. GitHub vulnerability alerts and the dependency
graph are enabled for the public fork; the graph's SBOM and comparison API were
verified before making the check required.

Enabling the graph reported 22 vulnerabilities already present on fork `main`
(16 high and six moderate). Dependency review prevents new vulnerable changes;
it does not retroactively repair that baseline. Product-scoped alert triage is
tracked as follow-up work rather than silently upgrading unrelated monorepo
dependencies in this cleanup.

CodeQL scans only the `actions` language. Broad Go and JavaScript/TypeScript
analysis remains upstream-owned and is intentionally absent from this
self-hosted mobile boundary.

### Workflow security

`.github/scripts/check_workflow_security.rb` is loaded from the pull request's
base SHA by the approval-gated validation job and inspects the proposed tree.
It rejects:

- missing or unexpected workflow/action files and job identities;
- privileged triggers or top-level PR path filters;
- permission, runner, timeout, fork-guard, environment, or stable-check drift;
- non-SHA external actions or unapproved local actions;
- checkout steps that persist credentials; and
- repository/environment secret references.

Fixture tests prove both the accepted repository and representative failing
cases. `scripts/test_upstream_sync.sh` runs the checker and its tests alongside
the complete upstream-sync contract suite.

### Upstream drift

The drift workflow is the only allowed workflow with issue-write authority. It
runs no pull-request code, cannot push source, and reconciles one marker-based
tracking issue. See the [upstream synchronization architecture](UpstreamEnteSynchronizationArchitecture.md).

## Main-branch enforcement

The `main` branch is protected with:

- strict, up-to-date required checks;
- the five exact gate names above, bound to the GitHub Actions app;
- enforcement for administrators;
- required conversation resolution;
- force pushes disabled; and
- branch deletion disabled.

A separate approving reviewer is not required, so the owner can merge a clean
fork-maintenance PR. Direct pushes cannot bypass the required GitHub Actions
evidence. Branch protection can be inspected with:

```sh
gh api repos/vanton1/ente/branches/main/protection
```

Repository settings are not stored in Git. If protection is deliberately
replaced, preserve the five exact check names and GitHub Actions app binding.
Removing protection or vulnerability alerts is an explicit owner rollback,
not a workflow operation.

## Failure and recovery

1. Open the failed gate and identify whether path detection, setup, validation,
   or aggregation failed.
2. Reproduce portable checks with
   `scripts/test_self_hosted_mobile_linux.sh` and the policy/sync suite with
   `scripts/test_upstream_sync.sh`.
3. Reproduce the macOS lane only on a Mac with Flutter 3.38.10, Ruby 3.3, and
   CocoaPods 1.17.0.
4. Repair source, generation, lockfiles, action pins, or policy explicitly.
   Never add secrets or disable a gate to make a PR green.
5. Push the repair and wait for all five required checks on the new head SHA.

Cancellation is fail-closed. Concurrency cancels superseded runs for the same
workflow/ref; branch protection evaluates the latest PR commit.

## Adopting future upstream automation

When official Ente adds or changes automation during synchronization:

1. leave the new file blocked by the allowlist;
2. identify its product, trigger, permissions, secrets, services, mutations,
   runner cost, and fork relevance;
3. prefer extending an existing fork workflow over importing official release
   or deployment machinery;
4. pin every external action to a full commit SHA, remove secrets, add the exact
   fork guard and timeout, and retain only minimal permissions;
5. update the checker rules and fixture tests in the same reviewed PR;
6. update this architecture if triggers, gates, settings, or authority change;
   and
7. prove relevant and irrelevant PR behavior before accepting the change.

Production Ente releases, deployments, translations, cache warming, unrelated
product CI, and signing/distribution credentials remain out of scope unless the
fork owner starts a new explicitly designed initiative.

## Acceptance evidence

The complete relevant-path set passed on
[PR #5](https://github.com/vanton1/ente/pull/5): workflow security in 11 seconds,
dependency review in 8 seconds, Actions CodeQL in 44 seconds, macOS mobile in
5m43s, and Linux mobile in 13m56s. All five stable gates were successful.

A disposable Markdown-only [PR #6](https://github.com/vanton1/ente/pull/6)
proved irrelevant-path behavior: all five gates passed in 2–5 seconds,
macOS/workflow validation was explicitly skipped, and Linux/CodeQL performed
only path detection. The probe PR was closed and both probe branches were
deleted without merging its file.
