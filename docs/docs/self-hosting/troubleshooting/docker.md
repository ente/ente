---
title: Troubleshooting Docker-related errors - Self-hosting
description: Fixing Docker-related errors when trying to self-host Ente
---

# Troubleshooting Docker-related errors

> [!TIP]
>
> **Restart after changes**
>
> Remember to restart your cluster to ensure changes that you make in the `compose.yaml` and `museum.yaml` get picked up.
>
> ```sh
> docker compose down
> docker compose up
> ```

## post_start

The Docker compose file used if relying on quickstart script or installation using Docker Compose uses the "post_start" lifecycle hook to provision the MinIO instance.

The lifecycle hook **requires Docker Compose version 2.30.0+**, and if you're using an older version of Docker Compose you will see an error like this:

```
validating compose.yaml: services.minio Additional property post_start is not allowed
```

The easiest way to resolve this is to upgrade your Docker Compose.

If you cannot update your Docker Compose version, then alternatively you can perform the same configuration by removing the "post_start" hook, and adding a new service definition:

```yaml
minio-provision:
    image: minio/mc
    depends_on:
        - minio
    volumes:
        - minio-data:/data
    networks:
        - internal
    entrypoint: |
        sh -c '
        #!/bin/sh
        while ! mc alias set h0 http://minio:3200 your_minio_user your_minio_pass
        do
          echo "waiting for minio..."
          sleep 0.5
        done
        cd /data
        mc mb -p b2-eu-cen
        mc mb -p wasabi-eu-central-2-v3
        mc mb -p scw-eu-fr-v3
        '
```

## start_interval

Similar to the `post_start` case above, if you are seeing an error like

```
services.postgres.healthcheck Additional property start_interval is not allowed
```

You will need to upgrade your Docker compose version to a newer version that supports the `start_interval` property on the health check.

## Postgres authentication failed

If you are getting Postgres password authentication failures when starting your cluster, then you might be using a stale Docker volume.

If you are getting an error of the following form (pasting a full example for easier greppability):

```
museum-1    | panic: pq: password authentication failed for user "pguser"
museum-1    |
museum-1    | goroutine 1 [running]:
museum-1    | main.setupDatabase()
museum-1    |   /etc/ente/cmd/museum/main.go:846 +0x338
museum-1    | main.main()
museum-1    |   /etc/ente/cmd/museum/main.go:124 +0x44c
museum-1 exited with code 2
```

Then the issue is that the password you're using is not the password PostgreSQL is expecting.

There are 2 possibilities:

1. If you are using Docker Compose for running Ente from source, you might not have set the same credentials in `.env` and `museum.yaml` inside `server/config` directory. Edit the values to make sure the correct credentials are being used.
2. When you have created a cluster in `my-ente` directory on running `quickstart.sh` and later deleted it, only to create another cluster with same `my-ente` directory.

    However, by deleting the directory, the Docker volumes are not deleted.

    Thus the older volumes with previous cluster's credentials are used for new cluster and the error arises.

    Deletion of the stale Docker volume can solve this. **Be careful**, this will delete all data in those volumes (any thing you uploaded etc). Do this if you are sure this is the exact problem.

    ```shell
    docker volume ls
    ```

    to list them, and then delete the ones that begin with `my-ente` using `docker volume rm`. You can delete all stale volumes by using `docker system prune` with the `--volumes` flag, but be _really_ careful, that'll delete all volumes (Ente or otherwise) on your machine that are not currently in use by a running Docker container.

    An alternative way is to delete the volumes along with removal of cluster's containers using `docker compose` inside `my-ente` directory.

    ```sh
    docker compose down --volumes
    ```

    If you're unsure about removing volumes, another alternative is to rename your `my-ente` folder. Docker uses the folder name to determine the volume name prefix, so giving it a different name will cause Docker to create a volume afresh for it.

## MinIO provisioning error

If you encounter similar logs while starting your Docker Compose cluster

```
my-ente-minio-1 ->  | Waiting for minio...
my-ente-minio-1 ->  | Waiting for minio...
my-ente-minio-1 ->  | Waiting for minio...
```

This could be due to usage of deprecated MinIO `mc config` command. Changing `mc config host h0 add` to `mc alias set h0` resolves this.

Thus the updated `post_start` will look as follows for `minio` service:

```yaml
    minio:
        ...
        post_start:
        - command: |
            sh -c '
            #!/bin/sh
            while ! mc alias set h0 http://minio:3200 your_minio_user your_minio_pass 2>/dev/null
            ...
            '
```
