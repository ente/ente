# Ente's web apps

Source code for Ente's web apps and supporting websites.

Live versions include:

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

By default, `npm run dev` builds the Photos app. To run the public albums app, use `npm run dev:albums`. To run auth, use `npm run dev:auth`.

To see the full list of apps you can run (and other scripts that you can use), use `npm run`.

> [!NOTE]
>
> If `package-lock.json` has not changed since your last `npm ci`, you can use `npm install` as a faster incremental alternative.

## Docker images

A Docker image containing the self-hosting web apps is available from `ghcr.io/ente/web`. See [docs/docker.md](docs/docker.md) for more details.

## Attributions

City coordinates from [Simple Maps](https://simplemaps.com/data/world-cities)

## 🌍 Translate

[![Crowdin](https://badges.crowdin.net/ente-photos-web/localized.svg)](https://crowdin.com/project/ente-photos-web)

The web apps can be translated in the [Ente Web Crowdin project](https://crowdin.com/project/ente-photos-web). See [docs/translations.md](docs/translations.md) for more details.

## 💚 Contribute

For more ways to contribute, see [CONTRIBUTING.md](../CONTRIBUTING.md).
