---
title: User Management - Self-hosting
description: Guide to configuring Ente CLI for Self Hosted Instance
---

# User Management

You may wish to self-host Ente for your family or close circle. In such cases, you may wish to enable administrative access for few users, disable new registrations, manage one-time tokens (OTTs), etc.

This document covers the details on how you can administer users on your server.

## Whitelist admins

The administrator users have to be explicitly whitelisted in `museum.yaml`. You can achieve this the following steps:

> [!NOTE]
>
> To make getting started easier, the first registered user is automatically treated as an admin until you whitelist one explicitly. If your instance is publicly reachable, register your own account first so the admin account is yours.

1.  Connect to `ente_db` (the database used for storing data related to Ente).

    ```shell
    # Change the DB name and DB user name if you use different
    # values.
    # If using Docker
    docker exec -it <postgres-ente-container-name> sh
    psql -U pguser -d ente_db

    # Or when using psql directly
    psql -U pguser -d ente_db
    ```

2.  Get the user ID of the first user by running the following SQL query:

    ```sql
    SELECT * from users;
    ```

3.  Edit `internal.admins` or `internal.admin` (if you wish to whitelist only single user) in `museum.yaml` to add the user ID you wish to whitelist.
    - For multiple admins:

    ```yaml
    internal:
        admins:
            - <user_id>
    ```

    - For single admin:

    ```yaml
    internal:
        admin: <user_id>
    ```

4.  Restart Museum by restarting the cluster

> [!TIP]
>
> Restart your Compose clusters whenever you make changes.
>
> If you have edited the Compose file or configuration file (`museum.yaml`), make sure to recreate the cluster's containers.
>
> You can do this by the following command:
>
> ```sh
> docker compose down && docker compose up -d
> ```

## Increase storage and account validity

You can use Ente CLI for increasing storage quota and account validity for users on your instance. Check this guide for more [information](/self-hosting/administration/cli#step-4-increase-storage-and-account-validity)

## Handle user verification codes

Ente currently relies on verification codes for completion of registration.

When SMTP is not configured, these verification codes are accessible in server logs. Look for log entries with the following pattern:

```
Skipping sending email to user@example.com: Verification code: 123456
```

If using Docker Compose, you can access logs by running `sudo docker compose logs` in the cluster folder where the Compose file resides.

However, you may wish to streamline this workflow. You can follow one of the 2 methods if you wish to have many users in the system.

### Use hardcoded OTTs

You can configure to use hardcoded OTTs only for specific emails, or based on suffix.

A sample configuration for the same is provided below, which is to be used in `museum.yaml`:

```yaml
internal:
    hardcoded-ott:
        emails:
            - "example@example.org,123456"
        local-domain-suffix: "@example.org"
        local-domain-value: 012345
```

This sets OTT to 123456 for the email address example@example.com and 012345 for emails having @example.com as suffix.

### Send email with verification code

You can configure SMTP for sending verification code e-mails to users, if you do not wish to hardcode OTTs and have larger audience.

For more information on configuring email, check out the [email configuration](/self-hosting/installation/config#email) section.

## Disable registrations

For security purposes, you may choose to disable registrations on your instance. You can disable new registrations by using the following configuration in `museum.yaml`.

```yaml
internal:
    disable-registration: true
```
