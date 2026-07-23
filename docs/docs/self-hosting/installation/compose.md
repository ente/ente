---
title: Docker Compose - Self-hosting
description: Running Ente with Docker Compose from source
---

# Docker Compose

If you wish to run Ente via Docker Compose from source, do the following:

## Requirements

Check out the [requirements](/self-hosting/installation/requirements) page to get started.

## Step 1: Clone the repository

Clone the repository. Change into the `server/config` directory of the repository, where the Compose file for running the cluster is present.

Run the following command for the same:

```sh
git clone https://github.com/ente/ente
cd ente/server/config
```

## Step 2: Populate the configuration file and environment variables

In order to run the cluster, you will have to provide environment variable values.

Copy the configuration files for modification by the following command inside `server/config` directory of the repository.

This allows you to modify configuration without having to face hassle while pulling in latest changes.

```sh
# Inside the cloned repository's directory (usually `ente`)
cd server/config
cp example.env .env
cp example.yaml museum.yaml
```

Change the values present in `.env` file along with `museum.yaml` file accordingly.

> [!TIP]
>
> Make sure to enter the correct values for the database and object storage.
>
> You should consider generating values for JWT and encryption keys for emails if you intend to use for long-term needs.
>
> You can do by running the following command inside `ente/server`, assuming you cloned the repository to `ente`:
>
> ```sh
> # Change into the ente/server
> cd ente/server
> # Generate secrets
> go run tools/gen-random-keys/main.go
> ```

## Step 3: Start the cluster

Start the cluster by running the following command:

```sh
docker compose up --build
```

This builds Museum and web applications based on the Dockerfile and starts the containers needed for Ente.

> [!TIP]
>
> Check out [post-installations steps](/self-hosting/installation/post-install/) for further usage.
