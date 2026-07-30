# Running Museum

You can run a Docker compose cluster containing museum, the web app, and the essential auxiliary services it requires (database and object storage). This is the easiest and simplest way to get started, and also provides an isolated environment that doesn't clutter your machine.

You can also run museum directly on your machine if you wish - it is a single static go binary.

This document describes these different approaches (you can choose any one), and also outlines configuration.

- [Run using pre-built Docker images](quickstart/README.md)
- [Run using Docker, building image from source](#build-and-run-using-docker)
- [Run with Docker, à la carte](#pre-built-images)
- [Run without Docker](#running-without-docker)
- [Configuration](#configuration)

## Run using pre-built Docker images

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ente/ente/main/server/quickstart.sh)"
```

For more details, see [docs/quickstart.md](docs/quickstart.md).

## Build and run using Docker

Start the cluster (in the `ente/server` directory)

```sh
docker compose up --build
```

Once the cluster has started, you should be able to do call museum

```sh
curl http://localhost:8080/ping
```

Or connect from the [web app](../web)

```sh
NEXT_PUBLIC_ENTE_ENDPOINT=http://localhost:8080 npm run dev
```

Or connect from the [mobile app](../mobile)

```sh
flutter run --dart-define=endpoint=http://localhost:8080
```

Or interact with the other services in the cluster, e.g. connect to the DB

```sh
docker compose exec postgres env PGPASSWORD=pgpass psql -U pguser -d ente_db
```

Or interact with the MinIO S3 API

```sh
AWS_ACCESS_KEY_ID=changeme AWS_SECRET_ACCESS_KEY=changeme1234 \
    aws s3 --endpoint-url http://localhost:3200 ls s3://b2-eu-cen
```

Or open the MinIO dashboard at http://localhost:3201

> [!NOTE]
>
> To avoid exposing unnecessary services, this port is not exposed by default. You'll need to uncomment the corresponding port in your `compose.yaml` first.

> [!WARNING]
>
> The default credentials are user changeme / password changeme1234. Goes without saying, but remember to change them!

> [!NOTE]
>
> While we've provided a MinIO based Docker compose file to make it easy for people to get started, if you're running it in production we recommend using an external S3.

### Cleanup

Persistent data is stored in Docker volumes and will persist across container restarts. The volume can be saved / inspected using the `docker volumes` command.

To remove stopped containers, use `docker compose rm`. To also remove volumes, use `docker compose down -v`.

### Multiple clusters

You can spin up independent clusters, each with its own volumes, by using the `-p` Docker Compose flag to specify different project names for each one.

### Pruning images

Each time museum gets rebuilt from source, a new image gets created but the old one is retained as a dangling image. You can use `docker image prune --force`, or `docker system prune` if that's fine with you, to remove these.

## Pre-built images

## server

If you have setup the database and object storage externally and only want to run Ente's server, you can just pull and run the image from **`ghcr.io/ente/server`**.

```sh
docker pull ghcr.io/ente/server
```

## web

Similarly, there is a pre-built Docker image containing all the web apps which you can just pull and run the from **`ghcr.io/ente/web`**.

```sh
docker pull ghcr.io/ente/web
```

For details about configuring the web image, see [web/docs/docker.md](../web/docs/docker.md).

## Running without Docker

The museum binary can be run by using `go run cmd/museum/main.go`. But first, you'll need to prepare your machine for development. Here we give the steps, with examples that work for macOS (please adapt to your OS).

### Install [Go](https://golang.org/dl/)

```sh
brew install go
```

### Install Postgres

```sh
brew install postgresql@15
```

> [!NOTE]
>
> Here we install same major version of Postgres as our production database to avoid surprises, but if you're using a newer Postgres that should work fine too.

Run the service:

```sh
brew services run postgresql@15
```

> [!TIP]
>
> To stop, use
>
> ```sh
> brew services stop postgresql@15
> ```
>
> You can also tell brew to automatically start the service on login by using `start` instead of `run`
>
> ```sh
> brew services start postgresql@15
> ```

Create the database and user (one time)

```sh
psql postgres -c "CREATE USER pguser WITH PASSWORD 'pgpass';"
psql postgres -c "CREATE DATABASE ente_db OWNER pguser;"
```

> [!CAUTION]
>
> Since these are dev instructions, we're using the default username and password. For any non-trivial use, change the credentials.

> [!TIP]
>
> To inspect the DB, you can
>
> ```sh
> psql ente_db
> ```
>
> Data is stored in `/opt/homebrew/var/postgresql@15`

### Install Local S3

If you don't have a test S3 bucket, you can run a S3 compatible API locally. This section outlines using minio. Garage is also a newer alternative.

```sh
brew install minio minio-mc
brew services run minio
```

One time bucket creation.

```sh
mc alias set local http://127.0.0.1:9000 minioadmin minioadmin
mc mb local/b2-eu-cen
mc ls local
```

> [!CAUTION]
>
> Since these are dev instructions, we're using the default username and password. For any non-trivial use, change the credentials.

### Create config

Create `museum.yaml` in `ente/server`.

```yaml
db:
    host: localhost
    port: 5432
    name: ente_db
    user: pguser
    password: pgpass

s3:
    are_local_buckets: true
    b2-eu-cen:
        key: minioadmin
        secret: minioadmin
        endpoint: localhost:9000
        region: eu-central-2
        bucket: b2-eu-cen
```

### Start museum

From `ente/server`,

```sh
go run cmd/museum/main.go
```

For live reloads, install [air](https://github.com/cosmtrek/air#installation). Then you can just call `air` after declaring the required environment variables. For example,

```sh
air
```

### Testing

For quick local iteration without Postgres-backed tests, run `go test ./...` or a narrower package like `go test ./pkg/controller/email`. Tests that require Postgres skip unless the test environment is explicitly enabled.

To run the full `server/` Go test suite, including Postgres-backed tests, use:

```sh
./scripts/test-with-postgres.sh docker
./scripts/test-with-postgres.sh host -v
```

- `docker` runs the tests against a throwaway Docker Postgres
- `host` runs them against the existing Postgres on your machine
- any other args after `<docker|host>` are forwarded to the `go test` invocation

The script creates a temporary `ente_test_*` database on the selected Postgres instance, runs the tests, and drops the database when it exits.

## Configuration

Now that you have museum running (either inside Docker or standalone), we can talk about configuring it.

By default, museum runs in the "local" configuration using values specified in `local.yaml`.

To override these values, you can create a file named `museum.yaml` in the current directory. This path is git-ignored for convenience. Note that if you run the Docker compose cluster without creating this file, Docker will create an empty directory named `museum.yaml` which you can `rmdir` if you need to provide a config file later on.

The keys and values supported by this configuration file are documented in [configurations/local.yaml](configurations/local.yaml).

> [!TIP]
>
> If your mobile app is able to connect to your self hosted instance but is not able to view or upload images, see [ente.com/help/self-hosting/administration/object-storage](https://ente.com/help/self-hosting/administration/object-storage).
