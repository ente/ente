#!/bin/sh
#
# Ente self-host quickstart helper script.
#
# Usage: sh -c "$(curl -fsSL https://raw.githubusercontent.com/ente/ente/main/server/quickstart.sh)"
# Docs: https://github.com/ente/ente/blob/main/server/docs/quickstart.md

set -e

dcv=""
if command -v docker >/dev/null
then
    dcv=`docker compose version --short 2>/dev/null || echo`
fi

if test -z "$dcv"
then
    printf "ERROR: Please install Docker Compose before running this script.\n"
    exit 1
fi

dcv_maj=`echo "$dcv" | cut -d . -f 1`
dcv_min=`echo "$dcv" | cut -d . -f 2`

if test \( "$dcv_maj" -lt 2 \) -o \( "$dcv_maj" -eq 2 -a "$dcv_min" -lt 30 \)
then
    printf "ERROR: Docker Compose version ($dcv) should be at least 2.30+ for running this script.\n"
    exit 1
fi

if ! command -v base64 >/dev/null
then
    printf "ERROR: base64 command not found. It is needed to autogenerate credentials.\n"
    exit 1
fi

if test -d my-ente
then
    printf "ERROR: The 'my-ente' directory already exists. To start your instance again:\n\n"
    printf "    \033[1mcd my-ente && docker compose up\033[0m\n\n"
    exit 1
fi

printf "\n - \033[1mH E L L O\033[0m - \033[1;32mE N T E\033[0m -\n\n"

gen_user_suffix () { head -c 6 /dev/urandom | base64 | tr -d '\n'; }

gen_password () { head -c 21 /dev/urandom | base64 | tr -d '\n'; }

# crypto_secretbox_KEYBYTES = 32
gen_key () { head -c 32 /dev/urandom | base64 | tr -d '\n'; }

# crypto_generichash_BYTES_MAX = 64
gen_hash () { head -c 64 /dev/urandom | base64 | tr -d '\n'; }

# Like gen_key but sodium_base64_VARIANT_URLSAFE which converts + to -, / to _
gen_jwt_secret () { head -c 32 /dev/urandom | base64 | tr -d '\n' | tr '+/' '-_'; }

pg_pass=`gen_password`
minio_user=minio-user-$(gen_user_suffix)
minio_pass=`gen_password`
museum_key=`gen_key`
museum_hash=`gen_hash`
museum_jwt_secret=`gen_jwt_secret`

mkdir my-ente && cd my-ente
printf " \033[1;32mE\033[0m   Created directory \033[1mmy-ente\033[0m\n"
sleep 1

cat <<EOF >compose.yaml
services:
  museum:
    image: ghcr.io/ente/server
    ports:
      - 8080:8080 # API
    depends_on:
      postgres:
        condition: service_healthy
    volumes:
      - ./museum.yaml:/museum.yaml:ro
      - ./data:/data:ro
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8080/ping"]
      interval: 60s
      timeout: 5s
      retries: 3
      start_period: 120s

  # Resolve "localhost:3200" in the museum container to the minio container.
  socat:
    image: alpine/socat
    network_mode: service:museum
    depends_on: [museum]
    command: "TCP-LISTEN:3200,fork,reuseaddr TCP:minio:3200"

  web:
    image: ghcr.io/ente/web
    # Uncomment what you need to tweak.
    ports:
      - 3000:3000 # Photos web app
      # - 3001:3001 # Accounts
      - 3002:3002 # Public albums
      # - 3003:3003 # Auth
      # - 3004:3004 # Cast
      # - 3005:3005 # Share
      # - 3006:3006 # Embed
      # - 3008:3008 # Paste
      # - 3009:3009 # Locker
      # - 3010:3010 # Memories
    # Modify these values to your custom subdomains, if using any
    environment:
      ENTE_API_ORIGIN: http://localhost:8080

  postgres:
    image: postgres:15
    environment:
      POSTGRES_USER: pguser
      POSTGRES_PASSWORD: $pg_pass
      POSTGRES_DB: ente_db
    healthcheck:
      test: pg_isready -q -d ente_db -U pguser
      start_period: 40s
      start_interval: 1s
    volumes:
      - postgres-data:/var/lib/postgresql/data

  minio:
    image: minio/minio
    ports:
      - 3200:3200 # MinIO API
      # Uncomment to enable MinIO Web UI      
      # - 3201:3201
    environment:
      MINIO_ROOT_USER: $minio_user
      MINIO_ROOT_PASSWORD: $minio_pass
    command: server /data --address ":3200" --console-address ":3201"
    volumes:
      - minio-data:/data
    post_start:
      - command: |
          sh -c '
          #!/bin/sh

          while ! mc alias set h0 http://minio:3200 $minio_user $minio_pass 2>/dev/null
          do
            echo "Waiting for minio..."
            sleep 0.5
          done

          cd /data

          mc mb -p b2-eu-cen
          mc mb -p wasabi-eu-central-2-v3
          mc mb -p scw-eu-fr-v3
          '

volumes:
  postgres-data:
  minio-data:
EOF

printf " \033[1;32mN\033[0m   Created \033[1mcompose.yaml\033[0m\n"
sleep 1

cat <<EOF >museum.yaml
db:
      host: postgres
      port: 5432
      name: ente_db
      user: pguser
      password: $pg_pass

s3:
      # Top-level configuration for buckets, you can override by specifying these configuration in the desired bucket.
      # Set this to false if using external object storage bucket or bucket with SSL
      are_local_buckets: true
      # Set this to false if using subdomain-style URL. This is set to true for ensuring compatibility with MinIO when SSL is enabled.
      use_path_style_urls: true
      b2-eu-cen:
         # Uncomment the below configuration to override the top-level configuration 
         # are_local_buckets: true
         # use_path_style_urls: true
         key: $minio_user
         secret: $minio_pass
         endpoint: localhost:3200
         region: eu-central-2
         bucket: b2-eu-cen
      wasabi-eu-central-2-v3:
         # are_local_buckets: true
         # use_path_style_urls: true
         key: $minio_user
         secret: $minio_pass
         endpoint: localhost:3200
         region: eu-central-2
         bucket: wasabi-eu-central-2-v3
         compliance: false
      scw-eu-fr-v3:
         # are_local_buckets: true
         # use_path_style_urls: true
         key: $minio_user
         secret: $minio_pass
         endpoint: localhost:3200
         region: eu-central-2
         bucket: scw-eu-fr-v3

# Specify the base endpoints for various web apps you're running.
apps:
    photos: http://localhost:3000
    public-albums: http://localhost:3002
    embed-albums: http://localhost:3006
    auth: http://localhost:3003
    locker: http://localhost:3009
    public-locker: http://localhost:3005
    public-paste: http://localhost:3008
    cast: http://localhost:3004
    accounts: http://localhost:3001
    public-memories: http://localhost:3010

key:
      encryption: $museum_key
      hash: $museum_hash

jwt:
      secret: $museum_jwt_secret
EOF

printf " \033[1;32mT\033[0m   Created \033[1mmuseum.yaml\033[0m\n"
sleep 1

printf " \033[1;32mE\033[0m   Do you want to start Ente? (y/n) [n]: "
read -r choice

if [[ "$choice" =~ ^[Yy]$ ]]; then
    printf "\nStarting docker compose\n"
    printf "\nAfter the cluster has started, open web app at \033[1mhttp://localhost:3000\033[0m\n"
    printf "(Verification code will be in the logs here)\n\n"
    docker compose up
else
    printf "\nTo start the cluster:\n"
    printf " \033[1;32m$\033[0m   cd my-ente\n"
    printf " \033[1;32m$\033[0m   docker compose up\n"
    printf "\nAfter the cluster has started, open web app at \033[1mhttp://localhost:3000\033[0m\n"
    printf "(Verification code will be in the logs here)\n\n"
fi
