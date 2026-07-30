# Ente's web apps

Source code for Ente's various web apps and supporting websites.

Live versions are at:

- Ente Photos: [photos.ente.com](https://photos.ente.com)
- Ente Albums: [albums.ente.com](https://albums.ente.com)
- Ente Auth: [auth.ente.com](https://auth.ente.com)
- Ente Locker: [locker.ente.com](https://locker.ente.com)

To know more about Ente, see [our main README](../README.md) or visit [ente.com](https://ente.com).

## Building from source

Install [Node](https://nodejs.org) and [Rust](https://www.rust-lang.org/tools/install).

Install dependencies

```sh
npm ci
```

Start a local development server

```sh
npm run dev
```

That's it. The web app will automatically hot reload when you make changes.

> [!TIP]
>
> If you're new to web development and unsure about how to get started, or are facing some problems when running the above steps, see [docs/new.md](docs/new.md).

> [!NOTE]
>
> If `package-lock.json` has not changed since your last `npm ci`, you can use `npm install` as a faster incremental alternative. For caveats, see [docs/dev.md](docs/dev.md#npm-ci-npm-install).

## Other apps

By default, `npm run dev` builds the Photos app. To run the public albums app, use `npm run dev:albums`. To run auth, use `npm run dev:auth`.

To see the full list of apps you can run (and other scripts that you can use), use `npm run`.

For more details about development workflows, see [docs/dev](docs/dev.md).

## Directory structure

As a brief overview, this directory contains the following apps:

- `apps/photos`: A fully functional web client for Ente Photos.
- `apps/albums`: The public albums web app used for shared album and file links.
- `apps/auth`: A view only client for Ente Auth. Currently you can only view your 2FA codes using this web app. For adding and editing your 2FA codes, please use the Ente Auth [mobile/desktop app](../auth/README.md) instead.

Apart from these primary apps there are other smaller ones too (see `apps/` for the full list).

The apps take use various `packages/` to share code amongst themselves.

You might also find this [overview of dependencies](docs/dependencies.md) useful.

## Docker images

A Docker image containing the self-hosting web apps is available from `ghcr.io/ente/web`. See [docs/docker.md](docs/docker.md) for more details.

## Attributions

City coordinates from [Simple Maps](https://simplemaps.com/data/world-cities)

## 🌍 Translate

[![Crowdin](https://badges.crowdin.net/ente-photos-web/localized.svg)](https://crowdin.com/project/ente-photos-web)

If you're interested in helping out with translation, please visit our [Crowdin project](https://crowdin.com/project/ente-photos-web) to get started. Thank you for your support.

If your language is not listed for translation, please [create a GitHub issue](https://github.com/ente/ente/issues/new?title=Request+for+New+Language+Translation&body=Language+name%3A) to have it added.

## 💚 Contribute

For more ways to contribute, see [CONTRIBUTING.md](../CONTRIBUTING.md).
