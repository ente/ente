# Ente Accounts

Code that runs on `accounts.ente.com`, providing a common origin where Ente clients associate passkeys tied to the user's account. It also handles other cross-app account flows like accepting family invitations.

> [!NOTE]
>
> Web subdomains can share passkeys through a common relying-party ID, but desktop and mobile clients still need a web origin to complete the passkey flow.

`accounts.ente.io` remains the legacy origin for users who already have Passkeys scoped to the old `ente.io` relying-party ID.

## Development

The repository's local Museum configuration already supports the Accounts app on `http://localhost:3001`. When using another configuration, set the relying-party ID to `localhost` and allow the app's origin:

```yaml
webauthn:
    rpid: "localhost"
    rporigins:
        - "http://localhost:3001"
```

Browsers treat `localhost` as a secure context, so WebAuthn works with the local HTTP server.
