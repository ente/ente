# App release process

Photos, Auth, Locker, Ensu, and Photos desktop use the same release process, as described here.

> For simplicity, the following assumes we're trying to release Ensu, that main is `0.1.16-beta`, we want to release `0.1.16` and move main to `0.1.17-beta`.
>
> To do the same steps for another app, say "auth", you can just mechanically replace "ensu" with that "auth" in the steps.

## App specifics

- Photos desktop follows the same flow, but its stable releases live in [ente/photos-desktop](https://github.com/ente/photos-desktop). See [desktop/docs/release.md](../../desktop/docs/release.md) for more details.

## Normal development

Nightly builds of `main` are automatically created every weekday morning (IST), and can also be created by running `ensu-build.yml` manually.

The nightly builds are published to the `ensu-v0.1.16-beta` pre-release in [ente/nightly](https://github.com/ente/nightly); each nightly keeps updating the same pre-release.

> [!NOTE]
>
> All builds (nightly and RC) are also uploaded to Play Store internal testing (Android) and TestFlight (iOS).
>
> See [apple-signing.md](./apple-signing.md) for certificate, API key, and provisioning profile setup and rotation.

## Start release

```sh
gh workflow run app-release.yml \
  -f action=start \
  -f app=ensu \
  -f version=0.1.16
```

This:

1. Creates a release branch `release/ensu-v0.1.16` with the version set to `0.1.16`
2. Pushes the branch, which triggers `ensu-build.yml`, which creates the draft `ensu-v0.1.16-rc` GitHub release in `ente/ente` (and a pre-release in `ente/nightly`).
3. Removes the `ensu-v0.1.16-beta` pre-release from `ente/nightly` and the beta tag from `ente/ente`.

> [!TIP]
>
> You can trigger the workflow using GitHub's UI also.

The workflow also opens a PR to move `main` to `0.1.17-beta`. Merge that PR after it is created. Scheduled nightlies are skipped while the release branch exists.

## Update the RC if needed

Cherry pick fixes to the release branch and push to replace the current RC. For release branches the build number does not auto increment and needs to be manually incremented.

```sh
git switch release/ensu-v0.1.16
git cherry-pick <fix-sha>
node .github/scripts/app-version.mjs ensu bump-build-and-commit
git push
```

## Promote release

> [!IMPORTANT]
>
> Edit the release notes for the `ensu-v0.1.16-rc` draft release in `ente/ente` into the final user-facing changelog before promoting.

```sh
gh workflow run app-release.yml \
  -f action=promote \
  -f app=ensu \
  -f version=0.1.16
```

This does not create another build. It tags the last RC commit as `ensu-v0.1.16`, publishes it (renaming `ensu-v0.1.16-rc` to `ensu-v0.1.16`), removes the RC tag, deletes the `ensu-v0.1.16-rc` pre-release from `ente/nightly`, and deletes the release branch.

It also opens a PR for updating the changelog in the docs.

> [!NOTE]
>
> For auto updates, the desktop app checks https://ente.com/release-info/ensu-desktop.json. A workflow on the website updates that file every day at 9 AM IST to use the latest Ensu release (if you want to update it earlier, run that workflow manually).

## Retries

`ensu-build.yml` is safe to retry. Both nightly and RC builds update fixed releases (`ensu-v0.1.16-beta` and `ensu-v0.1.16-rc`), and reruns update the same ones.

> [!NOTE]
>
> Individual failed jobs can be re-run idempotently (e.g. if only the Android job failed, it can be re-run in place). Retrying the build as a whole is also fine, except when it has already reached Play Store or TestFlight, in which case it needs a fresh build number: for nightlies trigger a new workflow run, for RCs push a `bump-build-and-commit`.

`app-release.yml` changes release state. If it fails, inspect the failed step before re-running. After it has pushed a branch, created a tag, or moved a draft release, either finish the remaining step manually or undo the partial state first. Cleanup is intentionally late: `action=start` pushes the release branch before deleting the beta pre-release from `ente/nightly`, and `action=promote` deletes the release branch last.

## Hotfix release

To ship a fix on top of the last release when main has moved on, create the release branch by hand from the released tag instead of using `action=start`. Use the code for the `start` in `app-release.yml` as a checklist. The one deviation: in the PR moving main to the next version, delete only the changes entries that the hotfix shipped, since the others are still unreleased.

> In the PR moving main to the next version, delete only the changes entries that the hotfix shipped.

Once the release branch exists, `action=promote` works as usual.
