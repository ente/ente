# Caddy

Caddy is used to terminate TLS and manage certificates for custom domains.

## Installation

```sh
sudo mkdir -p /root/caddy/conf
sudo mv Caddyfile /root/caddy/conf
sudo chown root:root /root/caddy/conf/Caddyfile
```

The rest works like our other systemd services.

If the Caddyfile changes, the running instance can be updated without restarts by using `sudo systemctl reload caddy`.

## Backups

The entire `/root/caddy` directory can be backed up and contains everything needed to restore the same setup.
