---
title: Manual setup (without Docker) - Self-hosting
description: Installing and setting up Ente without Docker
---

# Manual setup (without Docker)

If you wish to run Ente from source without using Docker, follow the steps described below:

## Requirements

1. **Go:** Install Go on your system. This is needed for building Museum (Ente's server)

    ```shell
    sudo apt update && sudo apt upgrade
    sudo apt install golang-go
    ```

    Alternatively, you can also download the latest binaries from the [official website](https://go.dev/dl/).

2. **PostgreSQL and `libsodium`:** Install PostgreSQL (database) and `libsodium` (high level API for encryption) via package manager.

    ```shell
    sudo apt install postgresql
    sudo apt install libsodium23 libsodium-dev
    ```

    Start the database using `systemd` automatically when the system starts.

    ```shell
    sudo systemctl enable postgresql
    sudo systemctl start postgresql
    ```

    Ensure the database is running using

    ```shell
    sudo systemctl status postgresql
    ```

3. **`pkg-config`:** Install `pkg-config` for dependency handling.

    ```shell
    sudo apt install pkg-config
    ```

4. **npm and Node.js:** Needed for building the web application.

    Install npm and Node using your package manager.

    ```shell
    sudo apt install npm nodejs
    ```

5. **Git:** Needed for cloning the repository and pulling in latest changes

6. **Caddy:** Used for setting reverse proxy and file servers

7. **Object Storage:** Ensure you have an object storage configured for usage, needed for storing files. You can choose to run MinIO or Garage locally without Docker, however, an external bucket will be reliable and suited for long-term storage.

## Step 1: Clone the repository

Start by cloning Ente's repository from GitHub to your local machine.

```sh
git clone https://github.com/ente/ente
```

## Step 2: Configure PostgreSQL database

1. Enter terminal-based front-end to PostgreSQL:

    ```shell
    psql
    ```

    > [!TIP]
    >
    > You may need to use `su <username>` before executing `psql`, where `<username>` is the user that starts PostgreSQL service.

2. Create a user in PostgreSQL for ente:

    ```sql
    CREATE USER <username> WITH ENCRYPTED PASSWORD '<password>';
    ```

3. Create a database:

    ```sql
    CREATE DATABASE <database name>;
    ```

4. Grant all privileges to the user on that database:

    ```sql
    GRANT ALL PRIVILEGES ON DATABASE <database name> TO <username>;
    ```

5. Make the user owner of the database:

    ```sql
    ALTER DATABASE <database name> OWNER TO <username>;
    ```

Values you used for `database name` and `username` correspond to the values you have to set for `db.user` and `db.name` in `museum.yaml`.

## Step 3: Configure Museum (Ente's server)

1. Install all the needed dependencies for the server.

    ```shell
    # Change into server directory, where the source code for Museum is
    # present inside the repo
    cd ente/server

    # Install the needed dependencies
    go mod tidy
    ```

2. Build the server. The server binary should be available as `./main` relative to `server` directory

    ```shell
    go build cmd/museum/main.go
    ```

3. Create `museum.yaml` file inside `server` for configuring the needed variables. You can copy the templated configuration file for editing with ease.

    ```shell
    cp config/example.yaml ./museum.yaml
    ```

    > [!TIP]
    >
    > Make sure to enter the correct values for the database and object storage.
    >
    > You should consider generating values for JWT and encryption keys for emails if you intend to use for long-term needs.
    >
    > You can do by running the following command inside `ente/server`, assuming you cloned the repository to `ente`:
    >
    > ```shell
    > # Generate secrets
    > go run tools/gen-random-keys/main.go
    > ```

4. Run the server

    ```shell
    ./main
    ```

Museum should be accessible at `http://localhost:8080`

## Step 4: Configure Web Application

1. Install the dependencies for web application.

    ```shell
    # Change into web directory, this is where all the applications
    # will be managed and built
    cd ../web

    # Install dependencies
    npm ci
    ```

2. Configure the environment variables in your corresponding shell's configuration file (`.bashrc`, `.zshrc`)

    ```shell
    # Replace this with actual endpoint for Museum
    export NEXT_PUBLIC_ENTE_ENDPOINT=http://localhost:8080
    ```

3. Build the needed applications (Photos, Albums, Accounts, Auth, Cast, Public Locker, Embed, Memories) as per your needs:

    ```shell
    # These commands are executed inside web directory
    # Build photos. Build output to be served is present at apps/photos/out
    npm run build

    # Build albums. Build output to be served is present at apps/albums/out
    npm run build:albums

    # Build accounts. Build output to be served is present at apps/accounts/out
    npm run build:accounts

    # Build auth. Build output to be served is present at apps/auth/out
    npm run build:auth

    # Build cast. Build output to be served is present at apps/cast/out
    npm run build:cast

    # Build public locker. Build output to be served is present at apps/share/out
    npm run build:share

    # Build embed. Build output to be served is present at apps/embed/out
    npm run build:embed

    # Build memories. Build output to be served is present at apps/memories/out
    npm run build:memories
    ```

4. Copy the output files to `/var/www/ente/apps` for easier management.

    ```shell
    mkdir -p /var/www/ente/apps

    # Photos
    sudo cp -r apps/photos/out /var/www/ente/apps/photos
    # Albums
    sudo cp -r apps/albums/out /var/www/ente/apps/albums
    # Accounts
    sudo cp -r apps/accounts/out /var/www/ente/apps/accounts
    # Auth
    sudo cp -r apps/auth/out /var/www/ente/apps/auth
    # Cast
    sudo cp -r apps/cast/out /var/www/ente/apps/cast
    # Public Locker
    sudo cp -r apps/share/out /var/www/ente/apps/share
    # Embed
    sudo cp -r apps/embed/out /var/www/ente/apps/embed
    # Memories
    sudo cp -r apps/memories/out /var/www/ente/apps/memories
    ```

5. Set up file server using Caddy by editing `Caddyfile`, present at `/etc/caddy/Caddyfile`.

    ```groovy
    # Replace the ports with domain names if you have subdomains configured and need HTTPS
    :3000 {
        root * /var/www/ente/apps/photos
        file_server
        try_files {path} {path}.html /index.html
    }

    :3001 {
        root * /var/www/ente/apps/accounts
        file_server
        try_files {path} {path}.html /index.html
    }

    :3002 {
        root * /var/www/ente/apps/albums
        file_server
        try_files {path} {path}.html /index.html
    }

    :3003 {
        root * /var/www/ente/apps/auth
        file_server
        try_files {path} {path}.html /index.html
    }

    :3004 {
        root * /var/www/ente/apps/cast
        file_server
        try_files {path} {path}.html /index.html
    }

    :3005 {
        root * /var/www/ente/apps/share
        file_server
        try_files {path} {path}.html /index.html
    }

    :3006 {
        root * /var/www/ente/apps/embed
        file_server
        try_files {path} {path}.html /index.html
    }

    :3010 {
        root * /var/www/ente/apps/memories
        file_server
        try_files {path} {path}.html /index.html
    }
    ```

    > [!TIP]
    >
    > **Important for Share App**
    >
    > The share web app (Public Locker) specifically requires all routes to be served through `/index.html` as it uses client-side routing with a single entry point. The `try_files` directive with `/index.html` as the fallback is essential for proper functionality. Without this configuration, direct links to shared albums and routes will result in 404 errors.

    The Ente Photos web app should be accessible at http://localhost:3000, and the Ente Albums app at http://localhost:3002. Check out the [default ports](/self-hosting/installation/env-var#ports) for more information.

> [!TIP]
>
> Check out [post-installations steps](/self-hosting/installation/post-install/) for further usage.
