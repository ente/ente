# Production Deployments

This describes Ente's production deployment. It is specific to our infrastructure and is generally unnecessary for self-hosted instances.

## Overview

We run Museum's Docker image on Ubuntu hosts with Docker and manage it with systemd, following the [service pattern](../../../infra/services/README.md) used by the rest of our infrastructure.

- [server-release.yml](../../../.github/workflows/server-release.yml) builds and publishes the image.

- [museum.service](museum.service) runs the container directly; [museum.nginx.service](museum.nginx.service) runs it behind Nginx.

- `systemctl start|stop|status museum` manages the running image.

- [update-and-restart-museum.sh](update-and-restart-museum.sh) pulls the latest image and restarts the service.

## Installation

To bring up another Museum node, prepare the instance to run our services.

Set up [Promtail](../../../infra/services/promtail/README.md), [Prometheus and node-exporter](../../../infra/services/prometheus/README.md).

If running behind Nginx, install the [nginx](../../../infra/services/nginx/README.md) service.

Add credentials:

```sh
sudo mkdir -p /root/museum/credentials
sudo tee /root/museum/credentials/pst-service-account.json
sudo tee /root/museum/credentials/fcm-service-account.json
sudo tee /root/museum/credentials.yaml
```

Add billing data from the pricing-data repository:

```sh
scp /path/to/pricing-data/{us,in,black-friday}.json <instance>:

sudo mkdir -p /root/museum/data/billing
sudo mv *.json /root/museum/data/billing/
```

Add TLS credentials unless running behind Nginx:

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

If running behind Nginx, install Museum's Nginx configuration with suitable rate limits:

```sh
scp scripts/deploy/museum.nginx.conf <instance>:

sudo mv museum.nginx.conf /root/nginx/conf.d
sudo systemctl reload nginx
```

## Starting

SSH into the instance and run:

```sh
./update-and-restart-museum.sh
```

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
