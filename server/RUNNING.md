# Running Museum

The Docker Compose setup runs Museum, Postgres, and MinIO in an isolated cluster. This is the easiest way to get started.

You can also run the static Go binary directly on your machine.

This document covers both approaches and Museum's configuration.

- [Run using pre-built Docker images](docs/quickstart.md)
- [Run using Docker, building image from source](#build-and-run-using-docker)
- [Use individual pre-built images](#pre-built-images)
- [Run without Docker](#running-without-docker)
- [Configuration](#configuration)

## Run using pre-built Docker images

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ente/ente/main/server/quickstart.sh)"
```

For more details, see [docs/quickstart.md](docs/quickstart.md).

## Build and run using Docker

From `ente/server`, start the cluster:

```sh
docker compose up --build
```

Once the cluster has started, call Museum:

```sh
curl http://localhost:8080/ping
```

Or connect from the [web app](../web):

```sh
NEXT_PUBLIC_ENTE_ENDPOINT=http://localhost:8080 npm run dev
```

Or connect from the [mobile app](../mobile):

```sh
flutter run --dart-define=endpoint=http://localhost:8080
```

Connect to Postgres:

```sh
docker compose exec postgres env PGPASSWORD=pgpass psql -U pguser -d ente_db
```

Use the MinIO S3 API:

```sh
AWS_ACCESS_KEY_ID=changeme AWS_SECRET_ACCESS_KEY=changeme1234 \
    aws s3 --endpoint-url http://localhost:3200 ls s3://b2-eu-cen
```

Or open the MinIO dashboard at http://localhost:3201.

> [!NOTE]
>
> To avoid exposing unnecessary services, this port is not exposed by default. You'll need to uncomment the corresponding port in your `compose.yaml` first.

> [!WARNING]
>
> The sample credentials are user `changeme` and password `changeme1234`. Change them before any non-local use.

> [!NOTE]
>
> For production, we recommend using external S3-compatible storage instead of the bundled MinIO service.

### Cleanup

Persistent data is stored in Docker volumes and survives container restarts. Inspect the volumes with `docker volume ls`.

To remove stopped containers, use `docker compose rm`. To also remove volumes, use `docker compose down -v`.

### Multiple clusters

You can spin up independent clusters, each with its own volumes, by using the `-p` Docker Compose flag to specify different project names for each one.

### Pruning images

Each source build creates a new image and leaves the old one dangling. Remove dangling images with `docker image prune --force`, or use `docker system prune` for a broader cleanup.

## Pre-built images

### Server

If you have provisioned Postgres and object storage separately, pull the server image from `ghcr.io/ente/server`.

```sh
docker pull ghcr.io/ente/server
```

### Web

The image at `ghcr.io/ente/web` contains all the web apps.

```sh
docker pull ghcr.io/ente/web
```

For details about configuring the web image, see [web/docs/docker.md](../web/docs/docker.md).

## Running without Docker

The following development setup runs Museum directly on macOS. Adapt the package installation commands for other operating systems.

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
> This installs the same Postgres major version used in production. Newer versions should also work.

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

Create the database and user once:

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
### Install Local S3

If you don't have a test S3 bucket, you can run a S3 compatible API locally. This section outlines using minio. Garage is also a newer alternative.

```sh
brew install minio minio-mc
brew services run minio
```

Create the bucket once:

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

By default, Museum uses the values in `configurations/local.yaml`.

To override these values, you can create a file named `museum.yaml` in the current directory. This path is git-ignored for convenience. Note that if you run the Docker compose cluster without creating this file, Docker will create an empty directory named `museum.yaml` which you can `rmdir` if you need to provide a config file later on.

The keys and values supported by this configuration file are documented in [configurations/local.yaml](configurations/local.yaml).

> [!TIP]
>
> If your mobile app can connect to your self-hosted instance but cannot view or upload images, see [ente.com/help/self-hosting/administration/object-storage](https://ente.com/help/self-hosting/administration/object-storage).
