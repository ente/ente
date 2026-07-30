---
title: Quickstart - Self-hosting
description: Getting started with self-hosting Ente
---

# Quickstart

If you're looking to spin up Ente on your server, you are in the right place!

Our entire source code, [including the server](https://ente.com/blog/open-sourcing-our-server/) is open source. This is the same code we use on production.

For a quick preview, make sure your system meets the requirements mentioned below. After trying the preview, you can explore other ways of self-hosting Ente on your server as described in the documentation.

## Requirements

- A system with at least 1 GB of RAM and 1 CPU core
- [Docker Compose](https://docs.docker.com/compose/)

> For more details, check out the [requirements page](/self-hosting/installation/requirements).

## Set up the server

Run this command on your terminal to setup Ente.

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ente/ente/main/server/quickstart.sh)"
```

This creates a directory `my-ente` in the current working directory, prompts to start the cluster with needed containers after pulling the images required to run Ente.

> [!NOTE]
>
> Make sure to modify the default values in `compose.yaml` and `museum.yaml` if you wish to change endpoints, bucket configuration or server configuration.

## Try the web apps

Open Ente Photos web app at `http://<machine-ip>:3000` (or `http://localhost:3000` if using on same local machine). Select **Don't have an account?** to create a new user.

Follow the prompts to sign up.

Public album links are served by the separate Albums app at `http://<machine-ip>:3002` (or `http://localhost:3002` on the same machine).

<div style="display: flex; gap: 10px;">
  <img alt="Onboarding screen" src="/onboarding.png" style="width: 50%; height: auto;">
  <img alt="Sign up page" src="/sign-up.png" style="width: 50%; height: auto;">
</div>

Enter the verification code by checking the cluster logs using `sudo docker compose logs`.

![Verification Code](/otp.png)

Upload a picture via the web user interface.

Alternatively, if using Ente Auth, get started by adding an account (assuming you are running Ente Auth at `http://<machine-ip>:3003` or `http://localhost:3003`).

## Try the mobile app

You can install Ente Photos from [here](/photos/faq/installing) and Ente Auth from [here](/auth/faq/installing).

Connect to your server from [mobile apps](/self-hosting/installation/post-install/#step-6-configure-apps-to-use-your-server).

## What next?

You may wish to install using a different way for your needs. Check the "Installation" section for information regarding that.

You can import your pictures from Google Takeout or from other services to Ente Photos. For more information, check out our [migration guide](/photos/migration/) for more information.

You can import your codes from other authenticator providers to Ente Auth. Check out our [migration guide](/auth/migration/) for more information.

## Queries?

If you need support, please ask on our community [Discord](https://ente.com/discord) or start a discussion on [GitHub](https://github.com/ente/ente/discussions/).
