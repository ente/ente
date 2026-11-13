#!/bin/bash

set -o xtrace
set -o errexit

PROJECT=copycat-db

docker rmi "ente/$PROJECT" || true
docker build --tag "ente/$PROJECT" .

docker run \
    --interactive --tty --rm \
    --env-file copycat-db.env \
    --name "$PROJECT" \
    "ente/$PROJECT" \
    "$@"
