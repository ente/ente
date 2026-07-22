# Synchronize This Fork with Official Ente

This is the canonical operator runbook for bringing official `ente/ente` changes
into `vanton1/ente`. The workflow preserves both Git histories, the configurable
self-hosted Android and iOS applications, and a reviewable fork pull request.
It never merges the pull request or publishes an application release.

For the design and security boundaries behind these commands, see the
[upstream synchronization architecture](living_docs/UpstreamEnteSynchronizationArchitecture.md).
The first large manual catch-up remains available as historical evidence in
the [implementation record](living_docs/UpstreamEnteSynchronization.md).
The pull request created by this runbook is enforced by the five checks in the
[fork GitHub Actions architecture](living_docs/ForkGitHubActionsArchitecture.md).

## 1. Automated drift notice

The `Upstream sync drift` GitHub workflow runs daily and can also be dispatched
manually. It is guarded to this fork and has only `contents: read` and
`issues: write` permissions. When official Ente is ahead, it creates or updates
one issue titled **Official Ente changes are ready to synchronize**. The issue
contains the exact official SHA and a pinned local command. When fork `main`
later contains that official history, the linked PR normally closes the issue;
a subsequent detector run closes it if it remains open.

The workflow only reports drift. It cannot create source commits, branches,
pull requests, releases, or deployments.

## 2. Local prerequisites

Use the trusted development Mac with the repository's current mobile
toolchain. The default validation requires Git, GitHub CLI, Flutter/Dart,
rustup Cargo, and CocoaPods. `--with-builds` additionally requires the current
JDK/Android toolchain and Xcode. The exact Flutter, Rust, CocoaPods, JDK, SDK,
and platform requirements come from the merged repository; the
[mobile build guide](mobile/apps/photos/SELF_HOSTED_BUILD_GUIDE.md) documents
the currently verified baseline.

Authenticate GitHub CLI and verify the remote quarantine once:

```sh
gh auth status --hostname github.com
git remote get-url --all origin
git remote get-url --all --push origin
git remote get-url --all upstream
git remote get-url --all --push upstream
```

Every `origin` URL must identify `vanton1/ente`, every upstream fetch URL must
identify `ente/ente`, and the only upstream push URL must be `DISABLED`. Repair
the official push boundary if necessary:

```sh
git remote set-url --push upstream DISABLED
```

Begin on a clean local `main` that exactly matches `origin/main`. Commit or
move unrelated work elsewhere before synchronization. The command deliberately
refuses dirty state, another branch, mismatched fork `main`, missing tools, or
unsafe remotes.

## 3. Normal one-command path

First inspect the exact drift without changing source history:

```sh
git switch main
./scripts/sync_upstream.sh check
```

Then use the exact command shown in the tracking issue. Its form is:

```sh
./scripts/sync_upstream.sh run --official-sha OFFICIAL_40_CHARACTER_SHA
```

Add full guarded platform builds when desired:

```sh
./scripts/sync_upstream.sh run \
  --official-sha OFFICIAL_40_CHARACTER_SHA \
  --with-builds
```

The command:

1. repeats the remote, branch, worktree, fork-SHA, and official-SHA preflight;
2. creates `sync/upstream-YYYY-MM-DD-<official-sha-prefix>` from fork `main`;
3. merges the exact official commit with a two-parent `--no-ff` merge;
4. verifies locked dependencies, stable Rust generation, CocoaPods, focused
   self-hosted behavior in three endpoint modes, formatting, and full mobile
   analysis;
5. optionally builds only the guarded Android debug and iOS Simulator apps
   against `https://photos.example.com`;
6. discovers zero or one open marker-based drift issue and checks for branch
   or pull-request collisions;
7. prints the fork, branch, commit, official SHA, build status, and issue;
8. requires the exact typed confirmation `PUSH <branch>`;
9. repeats the complete publication preflight after confirmation;
10. pushes only the validated branch to the canonical fork SSH URL and verifies
    its remote SHA; and
11. creates one pull request into fork `main`, linking the drift issue when one
    exists, without merging it.

If fork `main` already contains official `main`, `run` reports that no change is
needed and performs no mutation.

## 4. Paused and recovery paths

Every failure stops closed and preserves the integration branch and terminal
evidence. Do not reset, rebase, force-push, or hide generated drift.

### Merge conflict

`run` prints every unresolved file and leaves `MERGE_HEAD` intact. Resolve the
conflicts semantically, stage the complete resolution, then continue:

```sh
git status --short
git diff --name-only --diff-filter=U
git add PATHS_YOU_REVIEWED
./scripts/sync_upstream.sh resume
```

`resume` refuses unresolved files, unstaged resolution work, an empty staged
resolution, whitespace errors, or a non-sync branch. After it creates the merge
commit, make any compatibility repairs as ordinary reviewed commits on the
same branch. Repair commits above the verified merge are supported.

If the chosen official SHA or scope was wrong and the merge is still in
progress, inspect the evidence before explicitly abandoning it:

```sh
git merge --abort
```

The preserved branch name cannot be silently reused. A deliberate new attempt
must use a different date after the old attempt has been reviewed and retained
or removed according to owner policy.

### Validation or generation failure

Inspect the named failing gate. Pin the current repository toolchain, initialize
submodules, and review every generated change. Commit only an intentional
compatibility repair; do not hand-edit generated files merely to make the tree
clean. Then run:

```sh
./scripts/sync_upstream.sh validate
./scripts/sync_upstream.sh publish
```

Use `--with-builds` on both commands if platform builds are part of the
acceptance evidence. `publish` always reruns validation for the exact current
commit, even if `validate` just passed.

### Confirmation or GitHub failure

- A missing or mismatched `PUSH <branch>` confirmation performs no push and
  creates no pull request.
- If repository or GitHub state changes while confirmation is pending, the
  second preflight stops before pushing.
- If upload succeeds but pull-request creation fails, rerun `publish`. A
  matching remote branch is verified and reused without uploading again.
- A matching open pull request is returned without another confirmation or
  mutation.
- A remote branch at another SHA, a closed pull request using the same branch,
  multiple matching pull requests, or multiple marker issues requires manual
  inspection and a new synchronization branch; the command never overwrites
  or guesses.
- If `origin/main` moves after integration began, preserve the branch and start
  a new synchronization from the newly accepted fork `main`.

## 5. Review and merge boundary

The generated pull request contains exact fork, official, and validated SHAs
plus the validation/build summary. Review the complete change in GitHub. The
automation never approves or merges it. Merge into `vanton1/ente:main` only
after owner review and normal branch protection checks.

Source synchronization does not authorize signing or publishing Android/iOS
artifacts, incrementing Firebase build ledgers, notifying testers, registering
Apple devices, changing certificates or profiles, installing on devices, or
changing Museum, object storage, DNS, TLS, or Tailscale. Begin those operations
later from the accepted pushed source using the platform distribution guides.

## 6. Command reference and self-test

```sh
./scripts/sync_upstream.sh check [--no-fetch] [--json]
./scripts/sync_upstream.sh start [--official-sha SHA] [--date YYYY-MM-DD]
./scripts/sync_upstream.sh resume
./scripts/sync_upstream.sh validate [--with-builds]
./scripts/sync_upstream.sh publish [--with-builds] [--issue NUMBER]
./scripts/sync_upstream.sh run [--with-builds] [--issue NUMBER] [--official-sha SHA]
```

Run `COMMAND --help` for the exact options. Exit `0` means the requested command
completed; exit `2` means an unsafe/not-ready state stopped the operation;
exit `64` means invalid usage; and exit `70` means an underlying command failed
outside a classified safety gate.

The complete deterministic automation suite requires no network or external
mutation:

```sh
./scripts/test_upstream_sync.sh
```

Keep real server origins, Firebase identifiers, tester identities, Apple
device/profile/team data, credentials, private artifacts, and receipts out of
issues, pull requests, terminal captures, and Git.
