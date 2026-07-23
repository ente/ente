# Grafana

Grafana data is stored in a persistent Docker volume named `grafana-storage`. To create a backup of this, use

```sh
docker run --rm \
  --mount source=grafana-storage,target=/g \
  -v $(pwd):/backup \
  busybox \
  tar -cvzf /backup/grafana-storage.backup.tar.gz /g
```

## Installation

Restore the volume:

```sh
docker run --rm \
  --mount source=grafana-storage,target=/g \
  -v $(pwd):/backup \
  busybox \
  tar -xvzf /backup/grafana-storage.backup.tar.gz -C /
```

Add the Grafana nginx config

```sh
sudo mv grafana.nginx.conf /root/nginx/conf.d
```

and reload the nginx service before starting Grafana for the first time.

```sh
sudo systemctl reload nginx
sudo systemctl start grafana
```
