---
title: Self-hosting Ente on Windows
description: A community guide with a Windows specific workflow for running the self-hosted version on Ente
---

# Self-hosting Ente on Windows

While this setup was tested on Windows, the concepts are not OS-specific and will apply to any containerized deployment, including Linux and MacOS. If you are struggling with self-hosting, I recommend you read this guide.

The key differences are:

- Docker Desktop/Engine installation
- File path formatting for container volume mounts
- Startup service automation

## Prerequisites

You will need Docker Desktop or Docker Engine. Follow the installation instructions for your system:

- [Docker Desktop for Windows](https://docs.docker.com/desktop/setup/install/windows-install/)
- [MacOS](https://docs.docker.com/desktop/setup/install/mac-install/) (or install [docker-desktop Homebrew cask](https://formulae.brew.sh/cask/docker-desktop))
- [Linux](https://docs.docker.com/desktop/setup/install/linux/)

## Architecture

To troubleshoot, you'll need an understanding of the components at play. Start by memorizing the diagram here (there will be a quiz): https://github.com/ente/ente/tree/main/server/README.md

We have four primary components:

1. museum
    - Ente service API
    - Exposes port `8080`, which you will use for connecting your desktop and mobile ente app
2. postgres
    - Database for users and indexing your photos
    - Does not expose any ports
    - Museum calls it directly via the `postgres` host, which will be resolved by the container DNS
3. minio
    - Object store for photos
    - Minio exposes ports `9000` (API port) and `9001` (web UI)
    - The UI is optional, but useful for verifying the contents of your bucket during initial setup
4. web-ui
    - Web app can be accessed without using the ente app
    - Additionally provides support for shared albums and casting
    - Optional

When you upload files, museum gives your client (app or browser) the credentials to upload directly to object store. This is a good design because it means your object store can live in s3, while your museum is hosted on your local machine, and your local machine will not be a bottleneck for large file uploads. The caveat is that the minio endpoint is only specified once (in `museum.yaml`), but used by both the museum **and** your client for uploads. This means that if you specify `localhost:9000`, it must be reachable by both the museum and your browser. However, museum is running in a container, so `localhost` is local to the container, not your Windows machine. We will tell museum to translate `localhost` to the Windows host using the following directive:

```
extra_hosts:
  - localhost:host-gateway
```

## Secrets

**DO NOT** store secrets in plaintext. Let Docker handle them for you. Docker secrets are only available to swarm services, so we will be deploying using `docker stack` instead of `docker compose`.

You will need 6 secrets stored in your favorite password manager (any will do, I use Apple Passwords):

1. `pg_password`: random password
2. `minio_user`: random password
3. `minio_password`: random password
4. `encryption_key`: 32-char, base64
5. `hash_key`: 64-char, base64
6. `jwt_secret`: 32-char, base64, URL-safe

I generated the passwords using my password manager and the base64 values using bash:

- `openssl rand -base64 32`
- `openssl rand -base64 64`
- `openssl rand -base64 32 | tr '+/' '-_'`

If you don't have access to a unix shell, you can find an equivalent powershell command.

For each key, store it as a docker secret:

```
"Kx7v..." | docker secret create encryption_key -
```

## Configuration

Postgres and minio require dedicated folders on your Windows machine that will be mounted inside their respective containers. These folders can live anywhere in your file system. My tree looks like this:

```
D:\
  ente\
    minio\
    postgres\
    museum.yaml
    docker-compose.yaml
```

The `minio` and `postgres` folders start out empty. Copy the following configuration files to get started:

### museum.yaml

```
internal:
  admin: 1580559962386438  # This first user ID seems to be deterministic (but it may change in the future)
  # Uncomment after registering the admin account to disable additional users:
  # disable-registration: true

db:
  host: postgres
  port: 5432
  name: ente_db
  user: ente_db_user

s3:
  are_local_buckets: true
  b2-eu-cen:
    endpoint: localhost:9000
    # endpoint: http://192.168.1.42:9000    # Local IP of your machine, allows local network access
    # endpoint: https://minio.mydomain.com  # Custom domain
    region: us-east-1
    bucket: b2-eu-cen

apps:
  public-albums: http://localhost:3002
  # public-albums: http://192.168.1.42:3002
  # public-albums: https://albums.mydomain.com
  public-memories: http://localhost:3010
  # public-memories: http://192.168.1.42:3010
  # public-memories: https://memories.mydomain.com
  cast: http://localhost:3004
  # cast: http://192.168.1.42:3004
  # cast: https://cast.mydomain.com
```

### docker-compose.yaml

```
secrets:
  pg_password:
    external: true
  minio_user:
    external: true
  minio_password:
    external: true
  encryption_key:
    external: true
  hash_key:
    external: true
  jwt_secret:
    external: true

services:
  museum:
    image: ghcr.io/ente/server
    ports:
      - 8080:8080
    extra_hosts:
      - localhost:host-gateway  # Required if minio endpoint in `museum.yaml` is set to `localhost`
    volumes:
      - ./museum.yaml:/museum.yaml:ro
    secrets:
      - pg_password
      - minio_user
      - minio_password
      - encryption_key
      - hash_key
      - jwt_secret
    entrypoint: >
      sh -c '
        export ENTE_DB_PASSWORD=$$(cat /run/secrets/pg_password);
        export ENTE_S3_B2_EU_CEN_KEY=$$(cat /run/secrets/minio_user | xargs);  # Trim newline
        export ENTE_S3_B2_EU_CEN_SECRET=$$(cat /run/secrets/minio_password | xargs);  # Trim newline
        export ENTE_KEY_ENCRYPTION=$$(cat /run/secrets/encryption_key);
        export ENTE_KEY_HASH=$$(cat /run/secrets/hash_key);
        export ENTE_JWT_SECRET=$$(cat /run/secrets/jwt_secret);
        exec /museum
      '
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8080/ping"]
      start_period: 120s  # First time bootstrapping will take longer, so tell the container environment to ignore the first 120s of failed health checks.

  web:
    image: ghcr.io/ente/web
    ports:
      - 3000:3000  # Photos
      - 3002:3002  # Albums
      - 3004:3004  # Cast
      - 3005:3005  # Share
      - 3006:3006  # Embed
      - 3008:3008  # Paste
      - 3009:3009  # Locker
      - 3010:3010  # Memories
    environment:
      ENTE_API_ORIGIN: http://localhost:8080
      # ENTE_API_ORIGIN: http://192.168.1.42:8080
      # ENTE_API_ORIGIN: https://api.mydomain.com
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000"]

  postgres:
    image: postgres:15
    volumes:
      - ./postgres:/var/lib/postgresql/data
    secrets:
      - pg_password
    environment:
      POSTGRES_DB: ente_db
      POSTGRES_USER: ente_db_user
    entrypoint: >
      sh -c '
        export POSTGRES_PASSWORD=$$(cat /run/secrets/pg_password);
        docker-entrypoint.sh postgres
      '
    healthcheck:
      test: ["CMD", "pg_isready"]
      start_period: 30s  # Extended startup for first-time bootstrapping. Startup time will also increase as the database grows.

  minio:
    image: minio/minio:latest
    ports:
      - 9000:9000
      - 9001:9001
    volumes:
      - ./minio:/data
    secrets:
      - minio_user
      - minio_password
    entrypoint: >
      sh -c '
        export MINIO_ROOT_USER=$$(cat /run/secrets/minio_user);
        export MINIO_ROOT_PASSWORD=$$(cat /run/secrets/minio_password);
        exec minio server /data --console-address :9001
      '
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
```

Modify the volume mappings for museum, postgres, and minio to target the corresponding locations on your Windows machine, using either relative or absolute path:

- `./relative/windows/path:/container/path/do/not/modify`
- `D:/absolute/windows/path:/container/path/do/not/modify`

## Deployment

From the directory containing `docker-compose.yaml` run:

```
docker stack deploy -d -c docker-compose.yaml ente
```

Use docker CLI or Docker Desktop UI to monitor container health and logs during startup. Containers may be recreated on startup while waiting for dependencies. This lack of dependency management is a limitation of docker swarm. Eventually, all containers should start up.

### Post-installation

Follow https://ente.com/help/self-hosting/installation/post-install and enjoy the following tips:

- You can use the desktop app to register a new account. Click the login screen lock image 7 times and override the endpoint to `http://localhost:8080`.
- Your user email can be anything. No actual emails will be sent. The one-time code can be found in the museum container logs.
- I recommend using Docker Desktop UI to view logs and run container commands.
- On shutdown (`docker stack rm ente`), docker will wait for postgres to terminate before deleting the default network. The startup command (`docker stack deploy -d -c docker-compose.yaml ente`) will fail until all resources are deleted.
- Minio **will not** auto-create the bucket. I feel like museum should be doing this, but at the time of testing, this was not handled automatically. Additionally, if you don't allowlist CORS, your uploads will not complete. Run the following commands to fix both issues:
    1. In Docker Desktop, open the `ente_minio` container Exec tab, or run the following powershell command:
        ```
        docker exec -it $(docker ps -q -f name=ente_minio) sh
        ```
    2. Log in, create the default bucket, and allowlist CORS:
        ```
        printf '%s\n%s\n' "$(cat /run/secrets/minio_user)" "$(cat /run/secrets/minio_password)" | mc alias set admin http://localhost:9000
        mc mb -p admin/b2-eu-cen
        mc admin config set admin api cors\_allow\_origin="\*"
        ```
    3. Restart your minio container and you should be ready to upload!
- In case you missed it, use the ente CLI to increase your storage limits: https://ente.com/help/self-hosting/administration/cli#step-4-increase-storage-and-account-validity

## Next steps

1. Start ente automatically with Windows Task Scheduler. Create a basic task to run on login using `powershell.exe` with the following flags:

    ```
    -WindowStyle Hidden -ExecutionPolicy Bypass -File "D:\ente\ente_deploy.ps1"
    ```

    Then add `ente_deploy.ps1` to your `ente` directory:

    ```
    param(
      [string]$LogFile = "$PSScriptRoot\ente-deploy.log"
    )

    function Log($msg) {
        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg" | Add-Content $LogFile
    }

    do {
        $ok = try { docker node ls 2>$null } catch { $null }
        if ($ok) { break }
        Start-Sleep -Seconds 5
    } while ($true)

    Set-Location $PSScriptRoot
    $output = docker stack deploy -d -c docker-compose.yaml ente 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        Log $output
        exit $exitCode
    }

    exit 0
    ```

    - For non-Windows setups, find the recommended service manager for your OS (e.g. `systemd`), and configure it to use the following startup command: `cd /path/to/ente && docker stack deploy -c docker-compose.yaml ente`

2. To expose ente on your local network or custom domain, update `ENTE_API_ORIGIN` in `docker-compose.yaml` and the relevant app endpoints in `museum.yaml`.
    - For custom domains, I use a Cloudflare tunnel. Cloudflare client comes with a reverse proxy.
    - If you don't want to use a custom domain, but still want your ente service exposed publicly, Tailscale is a good choice. However, their "funnel" only routes to a single port, so you will need to set up your own reverse proxy. Caddy and Nginx are both great options which can be deployed as part of your existing `docker-compose.yaml`.
    - If you just want to connect through a VPN, Tailscale is the ideal choice, no reverse proxy necessary.
3. Migrating your photos from a different service can be messy. Google Takeout did not get imported into ente correctly, so half my photos had the wrong creation time. I ended up using a custom powershell script to get the JSON metadata associated with each file into the correct format. Your import may work fine.
4. You're self-hosting, so you have to worry about replication! Be sure to periodically back up either your postgres+minio databases or photos export to local disk. See https://ente.com/help/self-hosting/administration/backup for recommendations.
    - For example, my setup uses ente's continuous export and sync to an external drive, which is then uploaded daily to B2 using Kopia.

## Troubleshooting tips

1. Most errors will be network misconfigurations. Use your browser (or desktop app) developer tools console to see where a request is being sent. For example, if you're connecting from a different device or through a custom domain, and you see `localhost:8080` domain being hit in the networking logs, you know you forgot to update the web UI's `ENTE_API_ORIGIN` value. If your uploads aren't starting, your `s3.b2-eu-cen.endpoint` may be misconfigured. If your uploads are getting stuck at 97%, look for symptoms of a `403` and follow the CORS allowlist instructions.
2. Secrets are finicky when reading from files. You have to worry about trimming newlines and carriage returns. The configuration I shared should handle this, but if you see key authentication errors, you're in for a treat.
3. If you have lots of disk I/O (like a large copy) happening in the background, Windows will prioritize the Windows process over containers. This means containers will be slow to start up and may be terminated on startup. Wait for the copy to finish or increase the container `healthcheck.start_period`.
