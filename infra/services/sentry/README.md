# Sentry

- [Data flow](#understanding-the-data-flow)
- [Setting up a new instance](#setting-up-a-new-instance)

## Data flow

### Overview

Clients tunnel events to sentry-reporter.ente.io, and include the DSN in the request. At the other end of the tunnel is a Cloudflare Worker which unwraps the event, remaps the DSN if needed, and sends it to our actual self-hosted Sentry instance, sentry.ente.io.

Among other things, this indirection allows us to treat the Sentry instance as disposable, and recreate it from scratch anytime. The existing DSN's change, but that is not a problem because we remap DSNs in the worker that handles the tunneled requests.

### DSN

Sentry identifies each project with a unique ID it calls **DSN** (Data Source Name). The DSN is a URL that includes the project ID. For example, here is the DSN for the debug builds of the photos mobile app:

    https://ca5e686dd7f149d9bf94e620564cceba@sentry.ente.io/3

The DSN is considered public information and is included as part of the client's code. The DSN has 3 parts:

    https://<public-key-for-project>@<host>/<project-id>

The `<host>` for our case is sentry.ente.io.

Each client has a separate project, and some clients have multiple projects (e.g. production / debug). Each of these get a separate DSN.

### Reporting crashes

Sentry supports [tunnels](https://docs.sentry.io/platforms/javascript/configuration/options/#tunnel). The idea is to encapsulate the entire "original" HTTP event which would've been reported to some Sentry instance, and instead send this encapsulated event to a URL that is hosted alongside the app itself (say, example.org/sentry). At the other end of the tunnel is a service that unwraps the original payload and forwards it to the actual Sentry instance.

Usage on the client is simple - the mobile SDKs for Sentry support a `tunnel` parameter which can be set to "https://sentry-reporter.ente.io"

The other end of the tunnel is handled by a Cloudflare Worker that listens for incoming requests to 'https://sentry-reporter.ente.io', and forwards the requests to `sentry.ente.io`. Before forwarding, it also remaps the DSNs sent by the client with the latest ones. This allows us to hardcode the DSN in the client - if the DSN on the Sentry backend changes, we can just update or add a new mapping in the worker.

The source code for this worker is in [workers/sentry-reporter](../../workers/sentry-reporter).

## Setting up a new instance

### Overview

The upstream documentation is at https://develop.sentry.dev/self-hosted/.

We follow their steps (clone their setup, modify the configuration, and run the `./install.sh` that they provide). This results in a Sentry installation being available at localhost:9000.

Then, we install an nginx service that terminates the Cloudflare TLS and reverse proxies to localhost:9000.

To update Sentry just fetch the latest upstream and re-run `./install.sh`.

### Steps

> The following assumes that you have already provisioned new instances using our standard process.

- `cd /home/ente && git clone https://github.com/getsentry/self-hosted.git`
- Checkout the latest tag, e.g. `git checkout 26.5.0` (Sentry uses CalVer, so this'll be the latest `year.month.0`)
- Run `sudo ./install.sh`

The rest of this section describes the remaining three steps:

- Modify configuration
- Configure and start external nginx
- Start the cluster

### Configuration

Modify `sentry/config.yml`, adding relevant bits from the contents of `config.yml` (from this repository) and the mail credentials.

Next, modify `.env`, setting

```dotenv
SENTRY_EVENT_RETENTION_DAYS=30
```

### Configure external nginx

Add the nginx service (See [services/nginx](../services/nginx/README.md)) to the instance.

Add the Sentry nginx conf and certificates (since this instance will be running only sentry, we can use sentry specific certificates instead of our general wildcard ones).

```sh
sudo mv sentry.nginx.conf /root/nginx/conf.d
sudo tee /root/nginx/cert.pem
sudo tee /root/nginx/key.pem
```

### Start Sentry

Sentry should automatically start when the instance boots. If needed (and for the first time), it can be started manually by

```sh
cd /home/ente/self-hosted
sudo docker compose up -d
```

The (external) nginx service will also start automatically on boot, but if neded it can be manually started by

```sh
sudo systemctl start nginx
```

In their docs Sentry sometimes refers to commands like `sentry createuser`. To run them, prefix the command with `docker compose exec web`. e.g.

```sh
cd /home/ente/self-hosted
sudo docker compose exec web sentry createuser
```

If needed, Sentry can be stopped by using

```sh
cd /home/ente/self-hosted
sudo docker compose stop
```

## Backup / Restore

> [!NOTE]
>
> [Upstream docs](https://develop.sentry.dev/self-hosted/backup/#restore)

To backup an existing instance

```sh
sudo ./scripts/backup.sh
```

Then retain the following files

```
sentry/backup.json
sentry/config.yml
.env
```

To restore, run the fresh install. Once it completes, add our custom config back, ensuring we don't overwrite anything that the new version has

```sh
git diff --no-index ../.env .env
git diff --no-index ../config.yml sentry/config.yml
```

Copy back the backup and run the restore script

```sh
cp ../sentry-backup/backup.json sentry
sudo ./scripts/restore.sh
```

Now start sentry

```sh
sudo docker compose up -d
```
