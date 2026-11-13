# Publishing images

## Internal

Run the "Release (Server)" workflow from GitHub Actions or with:

```sh
gh workflow run server-release.yml
```

By default, it publishes the latest `main` commit to our Scaleway registry. See [deploy/README](../scripts/deploy/README.md) for deployment instructions.

## GHCR

The "Publish GHCR (Server)" workflow runs on the 15th of each month. It publishes the commit currently deployed in production to `ghcr.io/ente/server`, tagged with both the commit SHA and `latest`.

To run it manually:

```sh
gh workflow run server-publish-ghcr.yml
```
