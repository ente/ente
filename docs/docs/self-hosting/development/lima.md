---
title: Using Lima for development
description: Running Museum (server + DB) and web apps in a Lima VM for local development
---

# Using Lima for development

This guide shows a practical Lima workflow for local development on macOS.

It runs:

- Museum + Postgres via Docker Compose
- Ente Paste web app on port `3008`

## 1. Start Lima

```sh
limactl start template://docker
```

Then verify shell access:

```sh
limactl shell docker /bin/bash -lc 'id && uname -a'
```

## 2. Clone repo inside the VM

Using a VM-local clone avoids host-mount permission differences.

```sh
limactl shell docker /bin/bash -lc '
  cd ~ &&
  git clone https://github.com/ente/ente.git &&
  cd ente
'
```

## 3. Start Museum + Postgres

```sh
limactl shell docker /bin/bash -lc '
  cd ~/ente/server &&
  touch museum.yaml &&
  mkdir -p data &&
  cat > museum.yaml <<EOF
apps:
  public-paste: http://localhost:3008
EOF
  sudo docker compose up -d --build
'
```

Check health:

```sh
limactl shell docker /bin/bash -lc 'curl -fsS http://localhost:8080/ping'
```

## 4. Run Ente Paste web app

Run this in a separate terminal:

```sh
limactl shell docker /bin/bash -lc '
  sudo docker run --rm --name paste-dev \
    -p 3008:3008 \
    -v "$HOME/ente/web:/workspace" \
    -w /workspace \
    -e NEXT_PUBLIC_ENTE_ENDPOINT=http://localhost:8080 \
    node:24-bookworm \
    bash -lc "
      npm ci &&
      npm exec --workspace paste -- next dev --webpack -p 3008
    "
'
```

## 5. Open in browser

- Paste app: `http://localhost:3008`
- Museum API: `http://localhost:8080/ping`

If localhost ports are not reachable from your host, create an SSH tunnel:

```sh
ssh -F ~/.lima/docker/ssh.config \
  -N \
  -L 8080:127.0.0.1:8080 \
  -L 3008:127.0.0.1:3008 \
  lima-docker
```

## 6. Stop services

```sh
limactl shell docker /bin/bash -lc '
  cd ~/ente/server &&
  sudo docker compose down &&
  sudo docker rm -f paste-dev >/dev/null 2>&1 || true
'
```
