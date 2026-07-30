# Space Module

This module is the top-level home for space functionality in `server`.

## Layout

- `space/api`: thin Gin handlers and route registration
- `space/controller`: space business-logic surfaces, split by concern
- `space/repo`: Postgres and storage dependencies for space concerns
- `space/models`: space request/response and module-local types

The Rust space client lives alongside the rest of the Ente Rust crates at
`../rust/space`, not inside `server/space`.

The space root key bootstrap remains on the existing `/user-entity/key` endpoint via `userentity.Space`.

## Routes

Selected private Space routes are mounted under `/spaces/:spaceID/*`.
Public Space reads also use `/spaces/:spaceID/*`; legacy `/space/*` remains only for public slug lookup and link-session bootstrap endpoints.

## Local env overrides

Use a separate Postgres DB and Garage-backed S3 buckets by setting:

```bash
export ENVIRONMENT=local

export ENTE_DB_HOST=localhost
export ENTE_DB_PORT=5432
export ENTE_DB_NAME=ente3_space
export ENTE_DB_USER=postgres
export ENTE_DB_PASSWORD=postgres
export ENTE_DB_SSLMODE=disable

export ENTE_S3_ARE_LOCAL_BUCKETS=true
export ENTE_S3_USE_PATH_STYLE_URLS=true
export ENTE_S3_HOT_STORAGE_PRIMARY=b2-eu-cen
export ENTE_S3_HOT_STORAGE_SECONDARY=wasabi-eu-central-2-v3

export ENTE_S3_B2_EU_CEN_KEY=garage-access-key
export ENTE_S3_B2_EU_CEN_SECRET=garage-secret-key
export ENTE_S3_B2_EU_CEN_ENDPOINT=http://127.0.0.1:3900
export ENTE_S3_B2_EU_CEN_REGION=garage
export ENTE_S3_B2_EU_CEN_BUCKET=ente3-space-primary

export ENTE_S3_WASABI_EU_CENTRAL_2_V3_KEY=garage-access-key
export ENTE_S3_WASABI_EU_CENTRAL_2_V3_SECRET=garage-secret-key
export ENTE_S3_WASABI_EU_CENTRAL_2_V3_ENDPOINT=http://127.0.0.1:3900
export ENTE_S3_WASABI_EU_CENTRAL_2_V3_REGION=garage
export ENTE_S3_WASABI_EU_CENTRAL_2_V3_BUCKET=ente3-space-secondary
```

If derived space assets later need a separate bucket, add the matching `ENTE_S3_*` credentials for that bucket ID too.
