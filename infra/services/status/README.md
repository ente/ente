# Status

Our status page ([status.ente.com](https://status.ente.com)) is a self-hosted [Uptime Kuma](https://github.com/louislam/uptime-kuma).

## Installing

Install [nginx](../nginx/README.md).

Create a directory where Uptime Kuma will keep its state. This is the directory we can optionally backup if we wish to preserve history and settings when moving instances in the future.

```sh
sudo mkdir -p /root/uptime-kuma
```

Add the service definition and nginx configuration.

```sh
scp services/status/uptime-kuma.* <instance>:

sudo mv uptime-kuma.service /etc/systemd/system/
sudo mv uptime-kuma.nginx.conf /root/nginx/conf.d
```

Tell systemd to pick up new service definitions, enable the unit (so that it automatically starts on boot), and start it this time around.

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now uptime-kuma
```

Tell nginx to pick up the new configuration.

```sh
sudo systemctl reload nginx
```

## Administration

Login into the [dashboard](https://status.ente.com/dashboard) for administration.
