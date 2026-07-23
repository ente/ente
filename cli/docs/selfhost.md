## Self Hosting

If you are self-hosting the server, you can still configure CLI to export data & perform basic admin actions.

To do this, first configure the CLI to point to your server. Define a config.yaml and put it either in the same directory as CLI binary or path defined in env variable `ENTE_CLI_CONFIG_DIR`

```yaml
endpoint:
  api: "http://localhost:8080"
```

You should be able to [add an account](https://github.com/ente/ente/blob/main/cli/docs/generated/ente_account_add.md), and subsequently increase the [storage and account validity](https://github.com/ente/ente/blob/main/cli/docs/generated/ente_admin_update-subscription.md) using the CLI.

For the admin actions, you first need to whitelist admin users. You can create `server/museum.yaml`, and whitelist add the admin userID `internal.admins`. See [local.yaml](https://github.com/ente/ente/blob/main/server/configurations/local.yaml#L211C1-L232C1) in the server source code for details about how to define this.

You can use [account list](https://github.com/ente/ente/blob/main/cli/docs/generated/ente_account_list.md) command to find the user id of any account.

```yaml
# ....

internal:
  admins:
    # - 1580559962386440

# ....
```
