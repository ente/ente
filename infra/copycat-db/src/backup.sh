#!/bin/bash

set -o errexit
set -o pipefail
set -o xtrace

NOWS="$(date +%s)"

if test -z "$SCW_RDB_INSTANCE_ID"
then
    echo "copycat-db: SCW_RDB_INSTANCE_ID must be set"
    exit 1
fi

if test "$BACKUP_MODE" = "scw-export" || test "$BACKUP_MODE" = "snapshot-scw-export"
then
    BACKUP_FILE="db-$NOWS.custom"

    # Scaleway backup names cannot contain dots
    BACKUP_NAME="db-$NOWS-custom"
elif test "$BACKUP_MODE" = "snapshot-pgdump"
then
    if test "${#PGUSER}" -eq 0 || test "${#PGPASSWORD}" -eq 0
    then
        echo "copycat-db: PGUSER and PGPASSWORD must be set for snapshot-pgdump"
        exit 1
    fi

    if test -z "$SCW_PRIVATE_NETWORK_ID"
    then
        echo "copycat-db: SCW_PRIVATE_NETWORK_ID must be set for snapshot-pgdump"
        exit 1
    fi

    BACKUP_FILE="db-$NOWS.dumpdir.tar.zst"
else
    echo "copycat-db: BACKUP_MODE must be one of scw-export, snapshot-scw-export, snapshot-pgdump"
    exit 1
fi

EXPIRYS="$(( 30 * 24 * 60 * 60 + $NOWS ))"

EXPIRY="$(date -Iseconds --utc --date "@$EXPIRYS")"

BACKUP_INSTANCE_ID=$SCW_RDB_INSTANCE_ID
DELETE_INSTANCE_ID=

if test "$BACKUP_MODE" = "snapshot-scw-export" || test "$BACKUP_MODE" = "snapshot-pgdump"
then
    LATEST_SNAPSHOT_ID=$(
        scw rdb snapshot list instance-id="$SCW_RDB_INSTANCE_ID" order-by=created_at_desc -o json \
            | jq -r 'map(select((.status // "" | ascii_downcase) == "ready"))[0].id'
    )

    if test -z "$LATEST_SNAPSHOT_ID" || test "$LATEST_SNAPSHOT_ID" = "null"
    then
        echo "copycat-db: no ready snapshot found for instance: $SCW_RDB_INSTANCE_ID"
        exit 1
    fi

    BACKUP_INSTANCE_ID=$(
        scw rdb snapshot restore "$LATEST_SNAPSHOT_ID" \
            instance-name=copycat-db-temp \
            is-ha-cluster=false \
            -o json \
            | jq -r '.id'
    )

    if test -z "$BACKUP_INSTANCE_ID" || test "$BACKUP_INSTANCE_ID" = "null"
    then
        echo "copycat-db: failed to restore snapshot: $LATEST_SNAPSHOT_ID"
        exit 1
    fi

    scw rdb instance wait "$BACKUP_INSTANCE_ID" timeout=12h

    PUBLIC_ENDPOINT_ID="$(
        scw rdb endpoint list "$BACKUP_INSTANCE_ID" -o json \
            | jq -er '
                map(select(.load_balancer != null))
                | if length == 1 then .[0].id
                  else error("copycat-db: expected exactly one public endpoint on temp instance")
                  end
            '
    )"

    scw rdb endpoint delete "$PUBLIC_ENDPOINT_ID" instance-id="$BACKUP_INSTANCE_ID"
    scw rdb instance wait "$BACKUP_INSTANCE_ID" timeout=12h

    DELETE_INSTANCE_ID=$BACKUP_INSTANCE_ID
fi

if test "$BACKUP_MODE" = "scw-export" || test "$BACKUP_MODE" = "snapshot-scw-export"
then
    # Wait longer than Scaleway's default 20 minutes for the backup to be ready to export.
    BACKUP_ID=$(scw rdb backup create instance-id="$BACKUP_INSTANCE_ID" \
        name=$BACKUP_NAME expires-at=$EXPIRY \
        database-name=ente_db -o json | jq -r '.id')
    scw rdb backup wait $BACKUP_ID timeout=18h
    scw rdb backup download output=$BACKUP_FILE \
        $(scw rdb backup export $BACKUP_ID --wait -o json | jq -r '.id')
else
    scw rdb endpoint create "$BACKUP_INSTANCE_ID" \
        load-balancer=false \
        private-network.private-network-id="$SCW_PRIVATE_NETWORK_ID"
    scw rdb instance wait "$BACKUP_INSTANCE_ID" timeout=12h

    PRIVATE_ENDPOINT_IP="$(
        scw rdb endpoint list "$BACKUP_INSTANCE_ID" -o json \
            | jq -er '
                map(select(.private_network != null))
                | if length == 1 then .[0].ip
                  else error("copycat-db: expected exactly one private endpoint on temp instance")
                  end
            '
    )"

    PRIVATE_ENDPOINT_PORT="$(
        scw rdb endpoint list "$BACKUP_INSTANCE_ID" -o json \
            | jq -er '
                map(select(.private_network != null))
                | if length == 1 then .[0].port
                  else error("copycat-db: expected exactly one private endpoint on temp instance")
                  end
            '
    )"

    if ! PGHOST="$PRIVATE_ENDPOINT_IP" PGPORT="$PRIVATE_ENDPOINT_PORT" PGSSLMODE=require \
        timeout 5m bash -c '
            until pg_isready -d ente_db -t 3
            do
                echo "copycat-db: waiting for private endpoint (${SECONDS}s elapsed)"
                sleep 5
            done
            echo "copycat-db: private endpoint ready after ${SECONDS}s"
        '
    then
        echo "copycat-db: private endpoint readiness check failed"
        exit 1
    fi

    PGHOST="$PRIVATE_ENDPOINT_IP" PGPORT="$PRIVATE_ENDPOINT_PORT" PGSSLMODE=require \
        pg_dump -Fd -j 8 --compress=0 --file "db-$NOWS.dumpdir" ente_db
fi

if test -n "$DELETE_INSTANCE_ID"
then
    if test "$DELETE_INSTANCE_ID" = "$SCW_RDB_INSTANCE_ID"
    then
        echo "copycat-db: refusing to delete production instance"
        exit 1
    fi

    DELETE_INSTANCE_NAME=$(scw rdb instance get "$DELETE_INSTANCE_ID" -o json | jq -r '.name')

    if test "$DELETE_INSTANCE_NAME" != "copycat-db-temp"
    then
        echo "copycat-db: refusing to delete unexpected instance: $DELETE_INSTANCE_ID ($DELETE_INSTANCE_NAME)"
        exit 1
    fi

    scw rdb instance delete "$DELETE_INSTANCE_ID"
fi

if test "$BACKUP_MODE" = "snapshot-pgdump"
then
    tar -cf - "db-$NOWS.dumpdir" | zstd -T0 -q > "$BACKUP_FILE"
    rm -rf "db-$NOWS.dumpdir"
fi

rclone copy --log-level INFO $BACKUP_FILE $RCLONE_DESTINATION

rclone delete --log-level INFO --min-age 30d $RCLONE_DESTINATION

set +o xtrace
echo "copycat-db: backup complete: $BACKUP_FILE"
