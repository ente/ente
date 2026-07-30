# Photos desktop release process

Photos desktop uses the shared [app release process](../../.github/docs/app-release.md) as the app `photos-desktop`.

The main difference is that stable releases live in [ente/photos-desktop](https://github.com/ente/photos-desktop), not here, because electron-builder's auto updater doesn't work within a monorepo.

Currently the electron-updater feed, the website and the `brew cask` track that repository's latest release.

Apart from that, it is mostly as documented in the [app release process](../../.github/docs/app-release.md). Still, here is a brief recap.

> For simplicity, the following assumes that main is `1.7.25-beta`, we want to release `1.7.25` and move main to `1.7.26-beta`.

## Normal development

Nightly builds of `main` are published by a scheduled workflow automatically, and can also be triggered by manually triggering the `photos-desktop-build.yml` workflow.

Nightly and RC builds go to [ente/nightly](https://github.com/ente/nightly) like the other apps.

## In-app "What's new"

Separate from the GitHub and help-site notes: for a release with user-facing changes, update [WhatsNew.tsx](../../web/packages/new/photos/components/WhatsNew.tsx) and bump `changelogVersion` in [changelog.ts](../../web/packages/new/photos/services/changelog.ts) on `main` before cutting the RC.

The dialog shows once when the installed `changelogVersion` is newer than the one the user last saw.

## Start release

```sh
gh workflow run app-release.yml -f action=start -f app=photos-desktop -f version=1.7.25
```

Cherry-pick fixes to the release branch to rebuild the candidate.

## Promote release

> [!IMPORTANT]
>
> Edit the release notes for the `v1.7.25` draft release in `ente/photos-desktop` into the final user-facing changelog before promoting.

```sh
gh workflow run app-release.yml -f action=promote -f app=photos-desktop -f version=1.7.25
```

Publishes the `v1.7.25` draft in `ente/photos-desktop` as the latest release, pushes the `photos-desktop-v1.7.25` source tag, removes the `photos-desktop-v1.7.25-rc` pre-release from `ente/nightly`, and deletes the release branch. The website and the brew cask pick up the new latest release automatically.

It also opens a PR for updating the changelog in the docs.

## Details

The build runs on Windows, Linux and macOS, producing the artifacts configured in [electron-builder.yml](../electron-builder.yml): an NSIS installer (Windows), an AppImage and `.rpm`/`.deb`/`.pacman` packages (Linux), and a universal DMG (macOS). The macOS DMG is notarized and signed; Windows is signed via Azure Trusted Signing.

The Windows `exe`, the Linux AppImage, and the macOS DMG check `ente/photos-desktop`'s latest release for auto updates; the other formats don't auto update yet.
