#!/bin/sh

# Run once before starting Listmonk to initialize its database.

set -o errexit
set -o xtrace

docker pull listmonk/listmonk

docker run -it --rm --name listmonk \
    -v /root/listmonk/config.toml:/listmonk/config.toml:ro \
    listmonk/listmonk ./listmonk --install
