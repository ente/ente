---
title: Migrating from other providers
description: Guide for importing your existing 2FA tokens into Ente Auth from other providers
---

# Migrating from other providers

---

Ente Auth natively supports imports from many 2FA providers. In addition to the providers specifically listed in the documentation, the supported providers are:

- 2FAS Authenticator
- Aegis Authenticator
- andOTP (including encrypted backups, except MOTP)
- Bitwarden
- Google Authenticator
- LastPass
- Proton
- Raivo OTP

Details as to how codes may be imported from these providers may be found within the app.

> [!NOTE]
>
> Please note that this list may be out of sync, please see the app for the latest set of supported providers.

Ente Auth also supports imports from Auth's own encrypted exports and plain text files. Plain text files must be in the following format:

`otpauth://totp/provider.com:you@email.com?secret=YOUR_SECRET`

The codes can be separated by a comma or a new line.

So if your provider is not specifically listed, you might be still able to import from them by first converting the data from your old provider into these plaintext files and then importing those into Ente.
