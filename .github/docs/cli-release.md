# CLI releases

To publish the version on main:

```sh
gh workflow run ente-cli-release.yml --ref main
```

This publishes the CLI binaries and release notes, then opens a PR to bump the patch version, add the changelog entry and remove the shipped change notes.
