---
title: Ente CLI for Self-hosted Instance - Self-hosting
description: Guide to configuring Ente CLI for Self Hosted Instance
---

# Ente CLI for self-hosted instance

If you are self-hosting, you can configure Ente CLI to export data & perform basic administrative actions.

> [!TIP]
>
> **Installing Ente CLI**
>
> For instructions on installing the Ente CLI, see the [README available on Github](https://github.com/ente/ente/tree/main/cli/README.md).

## Step 1: Configure endpoint

To do this, first configure the CLI to use your server's endpoint.

Define `config.yaml` and place it in `~/.ente/` or directory specified by `ENTE_CLI_CONFIG_DIR` or directory where Ente CLI is present.

```yaml
# Set the API endpoint to your domain where Museum is being served.
endpoint:
    api: http://localhost:8080
```

## Step 2: Whitelist admins

You can whitelist administrator users by following this [guide](/self-hosting/administration/users#whitelist-admins).

## Step 3: Add an account

> [!NOTE]
>
> You can not create new accounts using Ente CLI.
>
> You can only log in to your existing accounts.
>
> To create a new account, use Ente Photos (or Ente Auth) web application, desktop or mobile.

You can add your existing account using Ente CLI.

```sh
ente account add
```

This should prompt you for authentication details and export directory. Your account should be added after successful authentication.

It can be used for exporting data (for plain-text backup), managing Ente Auth and performing administrative actions.

## Step 4: Increase storage and account validity

You can use `ente admin update-subscription` to increase storage quota and account validity (duration).

For infinite storage and validity, use the following command:

```sh
ente admin update-subscription -a <admin-user-mail> -u <user-email-to-update> --no-limit

# Set a limit
ente admin update-subscription -a <admin-user-mail> -u <user-email-to-update> --no-limit False
```

> [!NOTE]
>
> The users must be registered on the server with same e-mail address.
>
> If the commands are failing, ensure:
>
> 1. `<admin-user-mail>` is whitelisted as administrator user in `museum.yaml`. For more information, check this [guide](/self-hosting/administration/users#whitelist-admins).
> 2. `<user-email-to-update>` is a registered user with completed verification.

For more information, check out the documentation for setting [storage and account validity](https://github.com/ente/ente/blob/main/cli/docs/generated/ente_admin_update-subscription.md) using the CLI.

## References

1. [Ente CLI Documentation](https://github.com/ente/ente/blob/main/cli/docs/generated)
