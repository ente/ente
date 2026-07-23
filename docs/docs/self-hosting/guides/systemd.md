---
title: Running Ente using systemd - Self-hosting
description: Running Ente services (Museum and web application) via systemd
---

# Running Ente using `systemd`

On Linux distributions using `systemd` as initialization system, Ente can be configured to run as a background service, upon system startup by service files.

## Museum as a background service

Please check the below links if you want to run Museum as a service, both of them are battle tested.

1. [How to run museum as a systemd service](https://gist.github.com/mngshm/a0edb097c91d1dc45aeed755af310323)
2. [Museum.service](https://github.com/ente/ente/blob/23e678889189157ecc389c258267685934b83631/server/scripts/deploy/museum.service#L4)

Once you are done with setting and running Museum, all you are left to do is run the web app and set up reverse proxy. Check out the documentation for [more information](/self-hosting/installation/manual#step-3-configure-web-application).

> **Credits:** [mngshm](https://github.com/mngshm)
