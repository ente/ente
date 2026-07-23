## Desktop app for Ente Photos

The sweetness of Ente Photos, right on your computer. Linux, Windows and macOS.

You can [**download** a pre-built binary from releases](https://github.com/ente/photos-desktop/releases/latest).

To know more about Ente, see [our main README](../README.md) or visit [ente.com](https://ente.com).

## Building from source

Clone this repository

```sh
git clone https://github.com/ente/ente
cd ente
```

Install the web dependencies

```sh
cd web
npm ci
```

Install the desktop dependencies

```sh
cd ../desktop
npm ci
npm run postinstall
```

Now you can run in development mode (supports hot reload for the renderer process)

```sh
npm run dev
```

Or create a binary for your platform

```sh
npm run build
```

That's the gist of it. For more development related documentation, see [docs](docs/README.md).

> [!NOTE]
>
> If the relevant `package-lock.json` has not changed since your last `npm ci`, you can use `npm install` as a faster incremental alternative. For caveats, see [docs/dev.md](docs/dev.md#npm-ci-npm-install).

> [!NOTE]
>
> `npm run dev` will automatically do a `npm run postinstall` if needed. `npm run build` however requires an explicit `npm run postinstall` prior to it.
