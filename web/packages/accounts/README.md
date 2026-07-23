## ente-accounts

A package for sharing the pages involved in the signup/login flow.

Currently this is used by the photos and auth apps.

> [!NOTE]
>
> This is distinct from the accounts _app_, which currently acts as a broker for passkeys.

### Packaging

This (internal) package exports a React TypeScript library. We rely on the importing project to transpile and bundle it.
