---
title: Configuration - Self-hosting
description: "Information about all the configuration variables needed to run Ente with museum.yaml"
---

# Configuration

Museum is designed to be configured either via environment variables or via YAML. We recommend using YAML for maintaining your configuration as it can be backed up easily, helping in restoration.

## Configuration File

Museum's configuration file (`museum.yaml`) is responsible for making database configuration, bucket configuration, internal configuration, etc. accessible for other internal services.

By default, Museum runs in local environment, thus `local.yaml` configuration is loaded.

If `ENVIRONMENT` environment variable is set (say, to `production`), Museum will attempt to load `configurations/production.yaml`.

> [!NOTE]
>
> Ente uses the `production` configuration for its own deployments, and it may change between releases.

If `credentials-file` is defined and found, it overrides the defaults.

Use `museum.yaml` file for declaring configuration over `local.yaml`.

All configuration values can be overridden via environment variables using the `ENTE_` prefix and replacing dots (`.`) or hyphens (`-`) with underscores (`_`).

Museum reads configuration from `museum.yaml`. Any environment variables prefixed with `ENTE_` takes precedence.

For example,

```yaml
s3:
    b2-eu-cen:
        endpoint:
```

in `museum.yaml` is read as `s3.b2-eu-cen.endpoint` by Museum.

`ENTE_S3_B2_EU_CEN_ENDPOINT` declared as environment variable is same as the above and `ENTE_S3_B2_EU_CEN_ENDPOINT` overrides `s3.b2-eu-cen.endpoint`.

### General Settings

| Variable           | Description                                               | Default            |
| ------------------ | --------------------------------------------------------- | ------------------ |
| `credentials-file` | Path to optional credentials override file                | `credentials.yaml` |
| `credentials-dir`  | Directory to look for credentials (TLS, service accounts) | `credentials/`     |
| `log-file`         | Log output path. Required in production.                  | `""`               |

### HTTP

| Variable       | Description                       | Default |
| -------------- | --------------------------------- | ------- |
| `http.use-tls` | Enables TLS and binds to port 443 | `false` |

### App Endpoints

The `apps` section tells Museum where each Ente web app is hosted. Configure the public URL of every web app you deploy; these URLs form Museum's list of trusted browser origins.

If you set any of `apps.photos`, `apps.auth`, `apps.locker` or `apps.extra-origins`, Museum rejects browser requests from origins that are not in this list. If you set none of these keys, Museum only logs the unknown origins. This is a fallback so that older setups do not break; a future version of Museum will reject unknown origins by default. To choose the behavior explicitly, set `apps.cors-report-only` to `true` or `false`.

| Variable               | Description                                             | Default                     |
| ---------------------- | ------------------------------------------------------- | --------------------------- |
| `apps.photos`          | Photos web app base endpoint                            | `https://photos.ente.com`   |
| `apps.public-albums`   | Albums app base endpoint for public sharing             | `https://albums.ente.com`   |
| `apps.embed-albums`    | Embed app base endpoint                                 | `https://embed.ente.com`    |
| `apps.auth`            | Auth web app base endpoint                              | `https://auth.ente.com`     |
| `apps.locker`          | Locker web app base endpoint                            | `https://locker.ente.com`   |
| `apps.public-locker`   | Public Locker (share) app base endpoint                 | `https://share.ente.com`    |
| `apps.public-paste`    | Ente Paste app base endpoint                            | `https://paste.ente.com`    |
| `apps.public-memories` | Memories app base endpoint for public memory shares     | `https://memories.ente.com` |
| `apps.accounts`        | Accounts app base endpoint (used for passkey-based 2FA) | `https://accounts.ente.com` |
| `apps.accounts-legacy` | Legacy Accounts endpoint for passkey migration          | `https://accounts.ente.io`  |
| `apps.payments`        | Payments web app base endpoint                          | `https://payments.ente.com` |
| `apps.cast`            | Cast app base endpoint                                  | `https://cast.ente.com`     |
| `apps.family`          | Family web app base endpoint                            | `https://family.ente.io`    |
| `apps.space`           | Space web app base endpoint                             | `https://ente.space`        |
| `apps.legacy`          | Legacy recovery web app base endpoint                   | `https://legacy.ente.com`   |
| `apps.extra-origins`   | Additional trusted browser origins                      | Ente's other production origins |

### Database

The `db` section is used for configuring database connectivity. Ensure you provide correct credentials for proper connectivity within Museum.

| Variable      | Description                | Default     |
| ------------- | -------------------------- | ----------- |
| `db.host`     | DB hostname                | `localhost` |
| `db.port`     | DB port                    | `5432`      |
| `db.name`     | Database name              | `ente_db`   |
| `db.sslmode`  | SSL mode for DB connection | `disable`   |
| `db.user`     | Database username          |             |
| `db.password` | Database password          |             |
| `db.extra`    | Additional DSN parameters  |             |

### Object Storage

The `s3` section within `museum.yaml` is by default configured to use local MinIO buckets when using `quickstart.sh` or Docker Compose.

If you wish to use an external S3 provider with SSL, you can edit the configuration with your provider's credentials, and set `s3.are_local_buckets` to `false`. Additionally, you can configure this for specific buckets in the corresponding bucket sections in the Compose file.

If you are using default MinIO, it is accessible at port `3200`. Web Console can be accessed by enabling port `3201` in the Compose file.

For more information on object storage configuration, check our [documentation](/self-hosting/administration/object-storage).

If you face any issues related to uploads then check out [CORS](/self-hosting/administration/object-storage#cors-cross-origin-resource-sharing) and [troubleshooting](/self-hosting/troubleshooting/uploads) sections.

| Variable                               | Description                                  | Default |
| -------------------------------------- | -------------------------------------------- | ------- |
| `s3.b2-eu-cen`                         | Primary hot storage bucket configuration     |         |
| `s3.wasabi-eu-central-2-v3.compliance` | Whether to disable compliance lock on delete | `true`  |
| `s3.scw-eu-fr-v3`                      | Cold storage bucket configuration            |         |
| `s3.wasabi-eu-central-2-v3`            | Secondary hot storage configuration          |         |
| `s3.are_local_buckets`                 |                                              | `true`  |
| `s3.use_path_style_urls`               | Enable path-style URLs for MinIO             | `false` |

### Encryption Keys

These values are used for encryption of user e-mails. Default values are provided by Museum.

They are generated by random in quickstart script, so no intervention is necessary if using quickstart.

However, if you are using Ente for long-term needs and you have not installed Ente via quickstart, consider generating values for these along with [JWT](#jwt) by following the steps described below:

```sh
# If you have not cloned already
git clone https://github.com/ente/ente

# Generate the values
cd ente/server
go run tools/gen-random-keys/main.go
```

| Variable         | Description                    | Default     |
| ---------------- | ------------------------------ | ----------- |
| `key.encryption` | Key for encrypting user emails | Pre-defined |
| `key.hash`       | Hash key                       | Pre-defined |

### JWT

| Variable     | Description             | Default    |
| ------------ | ----------------------- | ---------- |
| `jwt.secret` | Secret for signing JWTs | Predefined |

### Email

You may wish to send emails for verification codes instead of [hardcoding them](/self-hosting/administration/users#use-hardcoded-otts). In such cases, you can configure SMTP.

Set the host and port accordingly with your credentials in `museum.yaml`

You may skip the username and password if using a local relay server.

```yaml
smtp:
    host:
    port:
    # Optional username and password if using local relay server
    username:
    password:
    # Email address used for sending emails (this mail's credentials have to be provided)
    email:
    # Optional name for sender
    sender-name:
    # Optional encryption
    encryption:
```

| Variable           | Description                  | Default |
| ------------------ | ---------------------------- | ------- |
| `smtp.host`        | SMTP server host             |         |
| `smtp.port`        | SMTP server port             |         |
| `smtp.username`    | SMTP auth username           |         |
| `smtp.password`    | SMTP auth password           |         |
| `smtp.email`       | Sender email address         |         |
| `smtp.sender-name` | Custom name for email sender |         |
| `smtp.encryption`  | Encryption method (tls, ssl) |         |

> [!NOTE]
>
> The legacy `transmail.key` is no longer supported, and should be converted to use [SMTP credentials](https://help.zoho.com/portal/en/kb/zeptomail/faqs/sending-emails/articles/how-to-configure-smtp) instead.

### WebAuthn Passkey Support

| Variable             | Description                  | Default                     |
| -------------------- | ---------------------------- | --------------------------- |
| `webauthn.rpid`      | Relying Party ID             | `localhost`                 |
| `webauthn.rporigins` | Allowed origins for WebAuthn | `["http://localhost:3001"]` |

### Internal

| Variable                                     | Description                                                                                                                                                             | Default |
| -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| `internal.silent`                            | Suppress external effects (e.g. email alerts)                                                                                                                           | `false` |
| `internal.trusted-client-ip-header`          | Request header trusted by gin’s `TrustedPlatform` when the server runs behind a proxy (leave empty to use gin’s default order: X-Forwarded-For, X-Real-IP, remote addr) |         |
| `internal.health-check-url`                  | External healthcheck URL                                                                                                                                                |         |
| `internal.hardcoded-ott`                     | Predefined OTPs for testing                                                                                                                                             |         |
| `internal.hardcoded-ott.emails`              | E-mail addresses with hardcoded OTTs                                                                                                                                    | `[]`    |
| `internal.hardcoded-ott.local-domain-suffix` | Suffix for which hardcoded OTT is to be used                                                                                                                            |         |
| `internal.hardcoded-ott.local-domain-value`  | Hardcoded OTT value for the above suffix                                                                                                                                |         |
| `internal.admins`                            | List of admin user IDs                                                                                                                                                  | `[]`    |
| `internal.admin`                             | Single admin user ID                                                                                                                                                    |         |
| `internal.disable-registration`              | Disable user registration                                                                                                                                               | `false` |

### Replication

By default, replication of objects (photos, thumbnails, videos) is disabled and only one bucket is used.

To enable replication, set `replication.enabled` to `true`. For this to work, 3 buckets have to be configured in total.

| Variable                   | Description                          | Default           |
| -------------------------- | ------------------------------------ | ----------------- |
| `replication.enabled`      | Enable replication across buckets    | `false`           |
| `replication.worker-url`   | Cloudflare Worker for replication    |                   |
| `replication.worker-count` | Number of goroutines for replication | `6`               |
| `replication.tmp-storage`  | Temp directory for replication       | `tmp/replication` |

### Background Jobs

This configuration is for enabling background cron jobs for tasks such as sending mails, removing unused objects (clean up) and worker configuration for the same.

| Variable                                      | Description                             | Default |
| --------------------------------------------- | --------------------------------------- | ------- |
| `jobs.cron.skip`                              | Skip all cron jobs                      | `false` |
| `jobs.remove-unreported-objects.worker-count` | Workers for removing unreported objects | `1`     |
| `jobs.clear-orphan-objects.enabled`           | Enable orphan cleanup                   | `false` |
| `jobs.clear-orphan-objects.prefix`            | Prefix filter for orphaned objects      |         |
