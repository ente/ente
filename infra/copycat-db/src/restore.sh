#!/bin/bash

set -o errexit
set -o pipefail
set -o xtrace

if test -z "$1"; then
    # Backup names contain epochs, so lexical sort finds the latest.
    BACKUP_FILE=$(
        rclone lsf --files-only $RCLONE_DESTINATION \
            | awk '/^db-.*(\.custom|\.dumpdir\.tar\.zst)$/' \
            | sort \
            | tail -1
    )
else
    BACKUP_FILE="$1"
fi

if test -z "$BACKUP_FILE"; then
    echo "copycat-db: no backup found"
    exit 1
fi

rclone copy --log-level INFO "${RCLONE_DESTINATION}${BACKUP_FILE}" .

if test "${BACKUP_FILE%.custom}" = "$BACKUP_FILE"; then
    ARCHIVE_FILE=$BACKUP_FILE
    zstd -dc "$BACKUP_FILE" | tar -xf -
    BACKUP_FILE="${BACKUP_FILE%.tar.zst}"
    rm "$ARCHIVE_FILE"
fi

# `rdb` is only the initial connection; the dump creates `ente_db`.
# Restore ownership as the current user without requiring production roles.
createdb rdb || true
pg_restore -d rdb --create --no-privileges --no-owner --exit-on-error "$BACKUP_FILE"

# Prune transient state and tokens.
psql -d ente_db -c 'delete from tokens'
psql -d ente_db -c 'delete from push_tokens'
psql -d ente_db -c 'delete from queue'
psql -d ente_db -c 'delete from temp_objects'

set +o xtrace
echo "copycat-db: restore complete: $BACKUP_FILE"
