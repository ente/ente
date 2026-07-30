---
title: Passkeys
description: Using passkeys as a second factor for your Ente account
---

# Passkeys

Passkeys are a new authentication mechanism that uses strong cryptography built into devices, like Windows Hello or Apple's Touch ID. **You can use passkeys as a second factor to secure your Ente account.**

> [!TIP]
>
> Passkeys are the colloquial term for a WebAuthn (Web Authentication) credentials.
>
> - More details about why and how are in the Passkeys announcement [blog post](https://ente.com/blog/introducing-passkeys-on-ente/).
> - And to know more technical details about how our passkey verification works, you can see this [technical note in our source code](https://github.com/ente/ente/blob/main/web/docs/webauthn-passkeys.md).

## Passkeys and TOTP

Ente already supports TOTP codes (in fact, we built an [entire app](https://ente.com/auth/) to store them...). Passkeys serve as an alternative 2FA (second factor) mechanism.

If you add a passkey to your Ente account, it will be used instead of any existing 2FA codes that you have configured (if any).

## Enabling and disabling passkeys

Passkeys get enabled if you add one (or more) passkeys to your account. Conversely, passkeys get disabled if you remove all your existing passkeys.

To add and remove passkeys, use the _Passkey_ option in the settings menu. This will open the Ente Accounts web app (_accounts.ente.com_), where you can manage your passkeys.

> [!NOTE]
>
> Ente Accounts has moved from _accounts.ente.io_ to _accounts.ente.com_. Older passkeys created on the old domain continue to work, and Ente will automatically open the right domain for your account. New passkeys are created on _accounts.ente.com_.

## Login with passkeys

If passkeys are enabled, then the Ente Accounts web app will automatically open when you log into your Ente account on a new device. Here you can follow the instructions given by the browser to verify your passkey.

> These instructions different for each browser and device, but generally they will ask you to use the same mechanism that you used when you created the passkey to verify it (scanning a QR code, using your fingerprint, pressing the key on your Yubikey or other security key hardware etc).

## Recovery

If you are unable to login with your passkey (e.g. if you have misplaced the hardware key that you used to store your passkey), then you can **recover your account by using your Ente recovery key**.

During login, press cancel on the browser dialog to verify your passkey, and then select the "Recover two-factor" option in the error message that gets shown. This will take you to a place where you can enter your Ente recovery key and login into your account. Now you can go to the _Passkey_ page to delete the lost passkey and/or add a new one.

If you have lost access to both your passkey and recovery key, please reach out to [support@ente.com](mailto:support@ente.com) for help.

## Related FAQs

- [Can I use passkeys instead of passwords?](/photos/faq/account-creation#use-passkeys)
- [What happens if I lose my passkey?](/photos/faq/account-creation#lost-passkey)
