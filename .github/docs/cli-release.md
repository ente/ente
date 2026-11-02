# CLI releases

Releases run from `main` every Wednesday afternoon (IST) when there are change entries in `rust/apps/cli/changes`.

To release manually:

```sh
gh workflow run ente-cli-release.yml --ref main
```

After release, merge the PR that bumps the patch version, updates the changelog and removes shipped change entries.
