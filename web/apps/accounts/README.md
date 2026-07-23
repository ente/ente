# Ente Accounts

Code that runs on `accounts.ente.com`.

Primarily, this serves a common domain where our clients can create and authenticate using shared passkeys tied to the user's Ente account.

It also includes other cross app account-level like family invitation acceptance.

> [!NOTE]
>
> Passkeys can be shared by multiple subdomains, so we didn't strictly need a separate web origin for sharing passkeys between our (photos and auth) web clients, but we do need a web origin to handle the passkey flow for the desktop and mobile clients.

`accounts.ente.io` remains the legacy origin for users who already have Passkeys scoped to the old `ente.io` relying-party ID.

For more details about the Passkey flows, [docs/webauthn-passkeys.md](../../docs/webauthn-passkeys.md).

## Development

To set this up to work with a locally running museum, modify your local `museum.yaml` to set the relaying party's ID to "localhost" (without any port number).

```yaml
webauthn:
    rpid: "localhost"
    rporigins:
        - "http://localhost:3001"
```

Note that browsers already treat `localhost` as a secure domain, so Passkey APIs will work even if our local dev server is using `http`.
