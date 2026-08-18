#!/bin/sh

# This script is meant to be run on the production instances.

set -o errexit

if sudo docker inspect museum >/dev/null 2>&1; then
    sudo docker tag "$(sudo docker inspect -f '{{.Image}}' museum)" rg.fr-par.scw.cloud/ente/museum-prod:previous
fi

sudo docker pull rg.fr-par.scw.cloud/ente/museum-prod

sudo systemctl restart museum
curl -fk --retry 5 --retry-connrefused --retry-delay 1 https://localhost/ping
sudo systemctl status museum --no-pager
sudo tail -n 20 /root/var/logs/museum.log
