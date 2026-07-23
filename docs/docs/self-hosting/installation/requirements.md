---
title: Requirements - Self-hosting
description: Requirements for self-hosting Ente
---

# Requirements

Ensure your system meets these requirements and has the needed software installed for a smooth experience.

## Hardware

The server is capable of running on minimal resource requirements as a lightweight Go binary, since most of the intensive computational tasks are done on the client. It performs well on small cloud instances, old laptops, and even [low-end embedded devices](https://github.com/ente/ente/discussions/594).

- **Storage:** An Unix-compatible filesystem such as ZFS, EXT4, BTRFS, etc. if using PostgreSQL container as it requires a filesystem that supports user/group permissions.
- **RAM:** A minimum of 1 GB of RAM is required for running the cluster (if using quickstart script).
- **CPU:** A minimum of 1 CPU core is required.

## Software

- **Operating System:** Any Linux or \*nix operating system, Ubuntu or Debian is recommended to have a good Docker experience. Non-Linux operating systems tend to provide poor experience with Docker and difficulty with troubleshooting and assistance.

- **Docker:** Required for running Ente's server, web application and dependent services (database and object storage). Ente also requires **Docker Compose plugin** to be installed.

> [!NOTE]
>
> Ente requires **Docker Compose version 2.30 or higher**.
>
> Furthermore, Ente uses the command `docker compose`, `docker-compose` is no longer supported.
