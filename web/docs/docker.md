# Docker

Automated Docker images for the self-hosting web apps are created every Wednesday, available from `ghcr.io/ente/web`.

These images expose web apps on the following ports:

- `3000` - Photos
- `3001` - Accounts
- `3002` - Albums
- `3003` - Auth
- `3004` - Cast
- `3005` - Share
- `3006` - Embed
- `3008` - Paste
- `3009` - Locker
- `3010` - Memories

For example, for selectively exposing only the photos web app on your port 8000:

```sh
docker run -it --rm -p 8000:3000 ghcr.io/ente/web
```

These images accept one environment variable:

- `ENTE_API_ORIGIN` - The API origin (scheme://host:port) for the custom API server. Default: "http://localhost:8080".

For example, if the API server is running at `https://api.example.org`:

```sh
docker run -it --rm -e ENTE_API_ORIGIN=https://api.example.org ghcr.io/ente/web
```

> [!TIP]
>
> Some of the web app origins (e.g. albums) also need to be configured in Museum's `apps` section.

### Dockerfile

For manually building the Docker image using `web/Dockerfile` instead of using prebuilt `ghcr.io/ente/web` image, the build must be run from the repo root since the context requires both the `web` and `rust` folders.

```sh
docker build -f web/Dockerfile .
```
