#!/bin/sh

# This script is meant to be run on the production instances.

set -o errexit

if docker inspect museum >/dev/null 2>&1; then
    docker tag "$(docker inspect -f '{{.Image}}' museum)" rg.fr-par.scw.cloud/ente/museum-prod:previous
fi

docker pull rg.fr-par.scw.cloud/ente/museum-prod

systemctl restart museum
curl -fk --retry 5 --retry-all-errors --retry-delay 1 https://localhost/ping
systemctl status museum --no-pager
tail -n 20 /root/var/logs/museum.log
