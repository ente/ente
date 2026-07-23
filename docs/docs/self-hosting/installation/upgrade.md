---
title: Upgrade - Self-hosting
description: Upgrading self-hosted Ente
---

# Upgrade your server

Upgrading Ente depends on the method of installation you have chosen.

> [!IMPORTANT]
>
> If your compose file references `ghcr.io/ente-io/`, replace it with `ghcr.io/ente/`, then run `docker compose pull && docker compose up -d`.

## Quickstart

> [!TIP]
>
> You can free up some disk space by deleting older images that were used by obsolete containers.
>
> ```sh
> docker image prune
> ```

Pull in the latest images in the directory where the Compose file resides. Restart the cluster to recreate containers with newer images.

Run the following command inside `my-ente` directory (default name used in quickstart):

```sh
docker compose pull && docker compose up -d
```

## Docker Compose

You can pull in the latest source code from Git and build a new cluster based on the updated source code.

1. Pull the latest changes from `main`.

    ```shell
    # Assuming you have cloned repository to ente
    cd ente
    # Pull changes
    git pull
    ```

2. Recreate the cluster.
    ```shell
    cd server/config
    # Stop and remove containers if they are running
    docker compose down
    # Build with latest code
    docker compose up --build
    ```

## Manual Setup

You can pull in the latest source code from Git and build a new cluster based on the updated source code.

1. Pull the latest changes from `main`.

    ```shell
    # Assuming you have cloned repository to ente
    cd ente

    # Pull changes and only keep changes from remote.
    # This is needed to keep package-lock.json up-to-date.
    # This resets all changes made in the local repository.
    # Make sure to stash changes if you have made any.
    git fetch origin
    git reset --hard main
    ```

2. Follow the steps described in [manual setup](/self-hosting/installation/manual#step-3-configure-web-application) for Museum and web applications.
