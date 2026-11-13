# Administration

Administer your own server with the account you have whitelisted as an administrator (see [Whitelist admins](../self-hosting/administration/users.md#whitelist-admins)). Log in to that server, then look up a user:

```sh
ente account login --account home-server --app photos --host https://api.example.org
ente admin user view alice@example.com --account home-server
```

```
Email    alice@example.com
ID       1580559962386438
Created  2026-01-05T10:12:00.000000Z
Plan     free
Storage  10 GB (10737418240 bytes)
Expires  2027-01-05T10:12:00.000000Z
```

A user is selected by email or numeric ID. `ente admin user list --account home-server` lists users in creation order, 100 at a time; add `--all` for every user, or `--since 2026-01-01` for users created after a date.

## Change a free subscription

```sh
ente admin user update-subscription alice@example.com --no-limit --account home-server
```

`--no-limit` sets 100 TB of storage and an expiry 100 years from now. For other values, pass `--storage 500GB`, `--expires 2027-12-31`, or both; an omitted value stays as it is. The CLI shows the old and new limits and asks:

```
Storage: 10 GB (10737418240 bytes) -> 100 TB (109951162777600 bytes)
Expires: 2027-01-05T10:12:00.000000Z -> 2126-10-22T09:00:00.000000Z
Update subscription for alice@example.com (1580559962386438) on https://api.example.org as admin@example.org (3)? [y/N]
```

Sizes accept MB, GB and TB with fractions. Dates accept `YYYY-MM-DD` or an RFC 3339 timestamp with a timezone. Paid plans are rejected.

## Reset a login factor

```sh
ente admin user disable-totp alice@example.com --account home-server
ente admin user remove-passkeys alice@example.com --account home-server
```

Each asks for confirmation and then prints `alice@example.com (1580559962386438): Authenticator-code two-factor authentication disabled.` or `...: All passkeys removed.` Neither changes the other factor.

## Delete a user

```sh
ente admin user delete alice@example.com --account home-server
```

After confirmation: `alice@example.com (1580559962386438): Account deleted; data cleanup scheduled. Subscription cancelled: false.` Deletion needs the email address, not an ID.

## Test email

```sh
ente admin email test --to alice@example.com --from noreply@example.org --from-name "Ente" --account home-server
```

Prints `Test email request accepted for alice@example.com.` This confirms the server accepted the request, not that the message was delivered.

## Run unattended

```sh
ente admin user update-subscription alice@example.com --no-limit --yes --no-input --json --account home-server
```

`--yes` approves a change; `--no-input` only disables prompts, so a change without `--yes` fails. `--json` prints results; prompts and errors still go to the terminal. `user view` returns `id`, `email`, `createdAt` and `subscription`, which is `null` or an object with `productId`, `storageBytes` and `expiresAt`. Listing users, deleting a user, disabling TOTP and removing passkeys need a login under ten minutes old; when yours is older, the CLI prints `administrator login is too old; run account login --account "home-server" --app photos and retry`. When the account is logged into several apps and Photos is not one of them, add `--app auth` or `--app locker` to pick the login to use.
