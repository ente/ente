---
title: Updated images - Self-hosting
description:
    Fixing container image pull errors after Ente's GitHub organization was
    renamed from ente-io to ente
---

# Updated images

---

**tldr; If your compose file references `ghcr.io/ente-io/`, replace it with `ghcr.io/ente/`, then run `docker compose pull && docker compose up -d`.**

---

We renamed our GitHub organization from `ente-io` to `ente`, so our repository
now lives at [github.com/ente/ente](https://github.com/ente/ente). Learn more
about the move on [our blog](https://ente.com/blog/ente-ente).

Web links to the old `ente-io` URLs continue to redirect, so most things keep
working unchanged. The GitHub Container Registry (GHCR) is the exception: it does
**not** redirect renamed paths, so our prebuilt images have moved.

| Old (no longer works)    | New                   |
| ------------------------ | --------------------- |
| `ghcr.io/ente-io/server` | `ghcr.io/ente/server` |
| `ghcr.io/ente-io/web`    | `ghcr.io/ente/web`    |

## Symptom

If your Compose file still references the old paths, `docker compose pull` fails
with a `denied` error, since `ghcr.io/ente-io/server` and `ghcr.io/ente-io/web`
no longer exist.

## Fix

Update the `image` references in your Compose file (for a quickstart setup, this
is the `compose.yaml` in your `my-ente` directory) from `ghcr.io/ente-io/` to
`ghcr.io/ente/`, then pull the new images and recreate your cluster:

```sh
docker compose pull && docker compose up -d
```

If you build from source instead of using the prebuilt images, there is nothing
to change here; pull the latest `main` and rebuild as usual.
