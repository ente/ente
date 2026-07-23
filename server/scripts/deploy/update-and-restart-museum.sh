#!/bin/sh

# This script is meant to be run on the production instances.
#
# It will tag the old image, pull the latest Docker image, restart museum and
# start tailing the logs as a sanity check.

set -o errexit

if sudo docker inspect museum >/dev/null 2>&1; then
    sudo docker tag "$(sudo docker inspect -f '{{.Image}}' museum)" rg.fr-par.scw.cloud/ente/museum-prod:previous
fi

sudo docker pull rg.fr-par.scw.cloud/ente/museum-prod

sudo systemctl restart museum
sudo systemctl status museum | more
sudo tail -F /root/var/logs/museum.log
