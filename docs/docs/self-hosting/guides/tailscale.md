---
title: Self-hosting with Tailscale - Self-hosting
description: Guides for self-hosting Ente Photos and/or Ente Auth with Tailscale
---

# Guide

This guide aims to achieve self-hosting Ente photos or Ente-Auth with tailscale (TSDPROXY) without exposing any port OR if someone is behind CGNAT and cannot open any port on the internet but want to run their own selfhosted service for themselves, friends and family only.

Before getting start keep the following NOTE in mind.

> [!NOTE]
>
> If someone is behind double or triple CGNAT; must install tailscale system wide by running `curl -fsSL https://tailscale.com/install.sh | sh` in your linux terminal and `sudo tailscale up` otherwise dns resolver will fail and uploading will not work. This is not necessary for those who are not behing CGNAT. This guide also work on docker rootless and normal.

> [!IMPORTANT]
>
> For Docker rootless, the user must have local permissions for all directories required by the Ente-photos self-hosted server. This can be achieved by running `sudo chown -R 1000:1000 /home/ubuntu/docker/ente`. In the Linux terminal, you can check the UID with `id -u` or simply `id`. The first user typically has UID 1000. To allow listening and pinging on any port without root privileges, create a file called `/etc/sysctl.d/99-rootless.conf` with the following content:
>
> ```
> net.ipv4.ip_unprivileged_port_start=0
> net.ipv4.ping_group_range = 0 2147483647
> ```
>
> then run `sudo sysctl --system`. Create `~/.config/systemd/user/docker.service.d/override.conf` with the following content:
>
> ```
> [Service]
> Environment="DOCKERD_ROOTLESS_ROOTLESSKIT_NET=slirp4netns"
> Environment="DOCKERD_ROOTLESS_ROOTLESSKIT_PORT_DRIVER=slirp4netns"
> ```
>
> and Restart the docker daemon `systemctl --user restart docker` Instead of `--volume /var/run/docker.sock:/var/run/docker.sock` in TSDPROXY compose.yaml, use `--volume $XDG_RUNTIME_DIR/docker.sock:/var/run/docker.sock`

## GETTING START WITH SETUP

First of all create a directory `sudo mkdir -p /home/ubuntu/docker/tsdproxy/config` then `cd docker/tsdproxy` and create compose.yaml file by running `sudo nano compose.yaml`. Populate it with the following:

```
services:
  tsdproxy:
    image: almeidapaulopt/tsdproxy
    container_name: tsdproxy
    restart: unless-stopped
    environment:
      TZ: Asia/Singapur # change me
    volumes:
      - $XDG_RUNTIME_DIR/docker.sock:/var/run/docker.sock # for docker rootless otherwise /var/run/docker.sock:/var/run/docker.sock
      - tsdproxy_data:/data
      - /home/lee/docker/tsdproxy/config:/config
    networks:
      - proxy
    labels: # giving the labels here will create tsdproxy instance in tailscale admin counsle and GUI can be accessable through tailscale if device is connected
      - tsdproxy.enable=true
      - tsdproxy.name=tsdproxy
      - tsdproxy.ephemeral=false # this is optional but useful

volumes:
  tsdproxy_data:
    name: tsdproxy_data

networks:
  proxy:
    name: proxy
```

Now login into your tailscale account admin counsel > settings > keys > Generate authkey. Give any description and select resuable, because the key will get purged if not selected after rebooting the machine. It is advisable to create **Tags** in **ACLs settings** `tag: tsdproxy` `tag: ente` `tag: minio` as well. This will create a tag nodes with no key expirory. One is safe to reboot restart docker or machine.

> Copy the generated authkey as it is shown only once. Make tsdproxy.yaml file in `cd docker/tsdproxy/config` by running `sudo nano tsdproxy.yaml` and populate it with the following content:

```
defaultproxyprovider: default
docker:
    local:
        host: unix:///var/run/docker.sock
        defaultproxyprovider: default
files: {}
tailscale:
  providers:
    default:
      authkey: ""
      authkeyfile: "/config/authkey"
      controlurl: https://controlplane.tailscale.com
  datadir: /data/
http:
  hostname: 0.0.0.0
  port: 8080
log:
  level: info
  json: false
proxyaccesslog: true
```

In the same directory run `sudo nano authkey` and paste the authkey just copied earlier from tailscale admin counsel.

> Here Tailscale (TSDPROXY) setup is complete in all respect. Just run `docker compose up -d`. Check your tailscale admin counsel and you will see tsdproxy node up and running. Make sure that **HTTPS** is enabled in tailscale DNS settings. You can visit the TSDPROXY web GUI by https://tsdproxy.xyz.ts.net. (xyz is change value for everyone)

## ente Part

First make the following necessary files/directories:

```
sudo mkdir -p /home/ubuntu/docker/ente/custom-logs
sudo mkdir -p /home/ubuntu/docker/ente/data
sudo mkdir -p /home/ubuntu/docker/ente/minio-data
sudo mkdir -p /home/ubuntu/docker/ente/postgres-data
sudo mkdir -p /home/ubuntu/docker/ente/scripts/compose
```

Then give user permission for each of the above directory. `sudo chown -R 1000:1000 /home/ubuntu/docker/ente/custom-logs` etc etc. Make sure not to skip `/home/ubuntu/docker/tsdproxy/config`

`cd docker/ente/script/compose` and run `sudo nano credentials.yaml` then populate it with the following:

```
db:
    host: postgres
    port: 5432
    name: ente_db
    user: pguser # change me
    password: pgpass #change me

s3:
    are_local_buckets: true
    b2-eu-cen:
        key: test # change me
        secret: testtest # change me
        endpoint: https://minio.xyz.ts.net
        region: eu-central-2
        bucket: b2-eu-cen
    wasabi-eu-central-2-v3:
        key: test # change me
        secret: testtest # change me
        endpoint: localhost:3200
        region: eu-central-2
        bucket: wasabi-eu-central-2-v3
        compliance: false
    scw-eu-fr-v3:
        key: test # change me
        secret: testtest # change me
        endpoint: localhost:3200
        region: eu-central-2
        bucket: scw-eu-fr-v3
```

In the same directory run `sudo nano minio-provision.sh` and populate it with the following contant:

```
#!/bin/sh

# Script used to prepare the minio instance that runs as part of the development
# Docker compose cluster.

while ! mc alias set h0 http://minio:3200 test testtest #(change me)
do
   echo "waiting for minio..."
   sleep 0.5
done

cd /data

mc mb -p b2-eu-cen
mc mb -p wasabi-eu-central-2-v3
mc mb -p scw-eu-fr-v3
```

Now `cd docker/ente` and run `sudo nano docker-compose.yaml` and populate it with the following:

```
services:
  museum:
    image: ghcr.io/ente/server
    ports:
      - 9080:8080 # 9080 because tsdproxy is running on 8080:8080
      # - 2112:2112 # Prometheus metrics
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      # Pass-in the config to connect to the DB and MinIO
      ENTE_CREDENTIALS_FILE: /credentials.yaml
     # ENTE_CLI_SECRETS_PATH: /cli-data/secret.txt
     # ENTE_CLI_CONFIG_PATH: /cli-data/
    volumes:
      - /home/ubuntu/docker/ente/custom-logs:/var/logs
      - /home/ubuntu/docker/ente/museum.yaml:/museum.yaml:ro
      - /home/ubuntu/docker/ente/scripts/compose/credentials.yaml:/credentials.yaml:ro
     #- /home/ubuntu/docker/ente/cli-data:/cli-data
     #- /home/ubuntu/docker/ente/exports/ente-photos:/exports
      - /home/ubuntu/docker/ente/data:/data:ro
    networks:
      - ente
      - proxy
    labels:
      tsdproxy.enable: "true"
      tsdproxy.name: "ente"

#  # Resolve "localhost:3200" in the museum container to the minio container.
  socat:
    image: alpine/socat
    network_mode: service:museum
    depends_on:
      - museum
    command: "TCP-LISTEN:3200,fork,reuseaddr TCP:minio:3200"

  postgres:
    image: postgres:15
    ports:
      - 5432:5432
    environment:
      POSTGRES_USER: pguser # change me
      POSTGRES_PASSWORD: pgpass # change me
      POSTGRES_DB: ente_db
    # Wait for postgres to be accept connections before starting museum.
    healthcheck:
      test:
        [
          "CMD",
          "pg_isready",
          "-q",
          "-d",
          "ente_db",
          "-U",
          "pguser" # change it accouding to the POSTGRES_USER: pguser
        ]
      start_period: 40s
      start_interval: 1s
    volumes:
      - /home/ubuntu/docker/ente/postgres-data:/var/lib/postgresql/data
    networks:
      - ente

  minio:
    image: minio/minio
    # Use different ports than the minio defaults to avoid conflicting
    # with the ports used by Prometheus.
    ports:
      - 3200:3200 # API
      - 3201:3201 # Console
    environment:
      MINIO_ROOT_USER: test # change me
      MINIO_ROOT_PASSWORD: testtest # change me
      MINIO_SERVER_URL: https://minio.xyz.ts.net
    command: server /data --address ":3200" --console-address ":3201"
    volumes:
      - /home/ubuntu/docker/ente/minio-data:/data
    networks:
      - ente
      - proxy
    labels:
      tsdproxy.enable: "true"
      tsdproxy.name: "minio"

  minio-provision:
    image: minio/mc
    depends_on:
      - minio
    volumes:
      - /home/ubuntu/docker/ente/scripts/compose/minio-provision.sh:/provision.sh:ro
      - /home/ubuntu/docker/ente/minio-data:/data
    networks:
      - ente
    entrypoint: sh /provision.sh


networks:
  ente:
    name: ente

  proxy:
    external: true
```

> Thats it. Run `docker compose up -d`. Wait until every container becomes healthy. Open a web browser. Make sure tailscale is installed on the machine. Visit https://ente.xyz.ts.net/ping. It will pong. All good if you see it. First time it will take minute or two to get SSL cert. Downnload Desktop or mobile app. Tap 7 time on the screen, which will prompt developer mode. Add https://ente.xyz.ts.net. Add new user. When asked for OTP, go to your linux terminal and run `docker logs ente-museum-1`. Search for userauth. Feed the six digit and Done.

> For getting 100TB (limitless) storage, install ente-cli for windows. Extract it and add folder. Name it **export**. Add config.yaml file along and populate it with the following:

```
endpoint:
  api: "https://ente.xyz.ts.net"
  accounts: "http://localhost:3001"

log: false
```

Right-Click in the directory where you have extracted ente-cli. Select `open in terminal`. Run

```
.\ente.exe account bob # change bob to yours
```

Hit Enter twice. For export directory, just write export, as you already created the **export** folder earlier. **Write email. The one which is already used before when creating ente account in ente desktop app.** Type the same password used before for the account. Run

```
.\ente.ext account list
```

This will list all account details. Copy Acount ID.

> Navigate to museum.yaml file. `cd docker/ente`. Run `sudo nano museum.yaml` and add the account ID under Admins. Delete any previous entries. Restart ente-museum-1 container from linux terminal. Run `docker restart ente-museum-1`. All well, now you will have 100TB storage. Repeat if for any other accounts you want to give unlimited storage access.

> **Credits:** [A4alli](https://github.com/A4alli)
