# Production Deployments

This document outlines how we ourselves deploy museum. Note that this is very specific to our use case, and while this might be useful as an example, this is likely overkill for simple self hosted deployments.

## Overview

We use museum's Dockerfile to build images which we then run on vanilla Ubuntu servers (+ Docker installed). For ease of administration, we wrap Docker commands to start/stop it in a systemd service.

- The production machines are vanilla Ubuntu instances, with Docker and Promtail installed.

- There is a [GitHub action](../../../.github/workflows/server-release.yml) to build museum Docker images using its Dockerfile.

- We wrap the commands to start and stop containers using these images in a systemd service.

- We call this general concept of standalone Docker images that are managed using systemd as "services". More examples and details [here](../../../infra/services/README.md).

- So museum is a "service". You can see its systemd unit definition in [museum.service](museum.service)

- On the running instance, we use `systemctl start|stop|status museum` to manage the current image.

- To update museum, use [update-and-restart-museum.sh](update-and-restart-museum.sh). It pulls the latest image before restarting the service.

- Optionally and alternatively, museum can also be run behind an Nginx. This option has a separate service definition.

## Installation

To bring up an additional museum node:

Prepare the instance to run our services.

Setup [promtail](../../../infra/services/promtail/README.md), [prometheus and node-exporter](../../../infra/services/prometheus/README.md) services.

If running behind Nginx, install the [nginx](../../../infra/services/nginx/README.md) service.

Add credentials

```sh
sudo mkdir -p /root/museum/credentials
sudo tee /root/museum/credentials/pst-service-account.json
sudo tee /root/museum/credentials/fcm-service-account.json
sudo tee /root/museum/credentials.yaml
```

Add billing data from the pricing-data repo

```sh
scp /path/to/pricing-data/{us,in,black-friday}.json <instance>:

sudo mkdir -p /root/museum/data/billing
sudo mv *.json /root/museum/data/billing/
```

Add the TLS credentials (optional if running behind Nginx)

```sh
sudo tee /root/museum/credentials/tls.cert
sudo tee /root/museum/credentials/tls.key
```

Copy the service definition and restart script to the new instance. The restart script can remain in the ente user's home directory. Move the service definition to its proper place.

```sh
# If using nginx
scp scripts/deploy/museum.nginx.service <instance>:museum.service
# otherwise
scp scripts/deploy/museum.service <instance>:

scp scripts/deploy/update-and-restart-museum.sh <instance>:

sudo mv museum.service /etc/systemd/system
sudo systemctl daemon-reload
```

If running behind Nginx, tell it about museum config (modified with suitable rate limits)

```sh
scp scripts/deploy/museum.nginx.conf <instance>:

sudo mv museum.nginx.conf /root/nginx/conf.d
sudo systemctl reload nginx
```

## Starting

SSH into the instance, and run

```sh
./update-and-restart-museum.sh
```

This'll ask for sudo credentials, pull the latest Docker image, restart the museum service and start tailing the logs (as a sanity check).

## Rollback

The update script tags the currently running image as `museum-prod:previous` before pulling. To roll back:

```sh
sudo docker tag rg.fr-par.scw.cloud/ente/museum-prod:previous rg.fr-par.scw.cloud/ente/museum-prod:latest
sudo systemctl restart museum
```

> [!NOTE]
>
> This doesn't work if there are migrations!

To reset the local `latest` back to the registry image, run `./update-and-restart-museum.sh` again, or

```sh
sudo docker pull rg.fr-par.scw.cloud/ente/museum-prod:latest
```
