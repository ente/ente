# Metabase

Use the embedded H2 database (this db contains users, saved queries etc). The database is a mounted as a file from the local filesystem into the container.

To take backups, backup `/root/metabase.db`

## Installation

If there are any existing backups, place them in `/root/metabase.db`.

Then add the Nginx conf

```sh
sudo mv metabase.nginx.conf /root/nginx/conf.d
```

and reload the nginx service.

## Update

Take a DB backup (just for safety), then restart the service (it'll pull the latest image).

```sh
sudo systemctl stop metabase
sudo cp -R /root/metabase.db metabase.db-backup-`date '+%s'`
sudo systemctl start metabase
```
