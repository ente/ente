---
title: Post-installation steps - Self-hosting
description: Steps to be followed post-installation for smooth experience
---

# Post-installation steps

A list of steps that should be done after installing Ente are described below:

## Step 1: Creating first user

The first user to be created will be treated as an admin user by default.

Once Ente is up and running, the Ente Photos web app will be accessible on `http://localhost:3000`.

Select **Don't have an account?** to create a new user. Follow the prompts to sign up.

<div style="display: flex; gap: 10px;">
  <img alt="Onboarding screen" src="/onboarding.png" style="width: 50%; height: auto;">
  <img alt="Sign up page" src="/sign-up.png" style="width: 50%; height: auto;">
</div>

Enter the verification code to complete registration.

This code can be found in the server logs, which should be shown in your terminal where you started the Docker Compose cluster.

If not, access the server logs inside the folder where Compose file resides.

```sh
sudo docker compose logs
```

If running Museum without Docker, the code should be visible in the terminal (stdout).

![otp](/otp.png)

## Step 2: Whitelist admins

1.  Connect to `ente_db` (the database used for storing data related to Ente).

    ```shell
    # Change the DB name and DB user name if you use different
    # values.
    # If using Docker
    docker exec -it <postgres-ente-container-name> sh
    psql -U pguser -d ente_db

    # Or when using psql directly
    psql -U pguser -d ente_db
    ```

2.  Get the user ID of the first user by running the following PSQL command:

    ```sql
    SELECT * from users;
    ```

3.  Edit `internal.admins` or `internal.admin` (if you wish to whitelist only single user) in `museum.yaml` to add the user ID you wish to whitelist.
    - For multiple admins:

    ```yaml
    internal:
        admins:
            - <user_id>
    ```

    - For single admin:

    ```yaml
    internal:
        admin: <user_id>
    ```

4.  Restart Museum by restarting the cluster

> [!TIP]
>
> Restart your Compose clusters whenever you make changes.
>
> If you have edited the Compose file or configuration file (`museum.yaml`), make sure to recreate the cluster's containers.
>
> You can do this by the following command:
>
> ```sh
> docker compose down && docker compose up -d
> ```

## Step 3: Configure application endpoints

You may wish to access some of the applications such as Albums, Share, Paste, Cast, Accounts via your instance's endpoints through the application instead of our production instances.

Configure every web app you deploy in the `apps` section of `museum.yaml`.

```yaml
# Replace yourdomain.tld with actual domain
apps:
    photos: https://photos.ente.yourdomain.tld
    public-albums: https://albums.ente.yourdomain.tld
    auth: https://auth.ente.yourdomain.tld
    locker: https://locker.ente.yourdomain.tld
    public-locker: https://share.ente.yourdomain.tld
    public-paste: https://paste.ente.yourdomain.tld
    public-memories: https://memories.ente.yourdomain.tld
    cast: https://cast.ente.yourdomain.tld
    embed-albums: https://embed.ente.yourdomain.tld
    accounts: https://accounts.ente.yourdomain.tld
    legacy: https://legacy.ente.yourdomain.tld
```

When you set these keys, Museum rejects browser requests from origins that are not in the list. List every web app that you deploy. A web app that is not in the list will get 403 errors in the browser.

If you are using quickstart, note that only Photos and Albums are exposed by default in `compose.yaml`. Uncomment the port mappings of the other apps there, or deploy them separately, before pointing their `apps.*` keys to those URLs.

## Step 4: Make it publicly accessible

You may wish to access Ente on public Internet. You can do so by configuring a reverse proxy with software such as Caddy, NGINX, Traefik.

Check out our [documentation](/self-hosting/administration/reverse-proxy) for more information.

If you do not wish to make it accessible via Internet, we recommend you to use [Tailscale](/self-hosting/guides/tailscale) for convenience. Alternately, you can use your IP address for accessing the application in your local network, though this poses challenges with respect to object storage (details below).

### Understanding IP address challenges with object storage

When accessing Ente using an IP address instead of a domain name, you may encounter two distinct issues with file uploads and downloads.

**Issue 1: S3 endpoint reachability.** Museum embeds the bucket `endpoint` value into the pre-signed URLs it hands to clients. The quickstart ships with `endpoint: localhost:3200`, which only resolves to MinIO from within the server. Uploads from the mobile app or another machine then silently fail (museum logs `OBJECT_SIZE_FETCH_FAILED: dial tcp …: i/o timeout`). Set `endpoint` in `museum.yaml` to an address reachable from both museum and the clients - typically the server's LAN IP or a hostname. Learn more in [Configuring Object Storage](/self-hosting/administration/object-storage#using-the-mobile-app-or-another-device).

**Issue 2: CORS (Cross-Origin Resource Sharing).** Your browser treats requests between different ports on the same IP as cross-origin requests. For example:

- Ente web app runs on `http://192.168.1.100:3000`
- MinIO object storage runs on `http://192.168.1.100:3200`

The browser blocks these requests unless CORS is properly configured.

**Solutions:**

1. **Use a domain name** (recommended): Set up a reverse proxy with a domain or use Tailscale to avoid CORS issues entirely.

2. **Configure CORS for your IP**: Update the MinIO CORS configuration to include your IP address in `AllowedOrigins`. You'll need to update this if your IP changes.

3. **Use wildcard CORS** (less secure): Configure `AllowedOrigins` to `["*"]` in your object storage CORS settings.

Learn more about [configuring CORS for object storage](/self-hosting/administration/object-storage#cors-cross-origin-resource-sharing).

> [!NOTE]
>
> This challenge is unrelated to the local storage path configuration (MinIO volumes in compose.yaml). It's specifically about browser security when accessing object storage over the network.

## Step 5: Download mobile and desktop app

You can install Ente Photos by following the [installation section](/photos/faq/installing).

You can also install Ente Auth (if you are planning to use Auth) by following the [installation section](/auth/faq/installing).

## Step 6: Configure apps to use your server

You can modify Ente mobile apps and CLI to connect to your server.

### Mobile

Tap the onboarding screen 7 times to modify developer settings. Enter your Ente server's endpoint.

<div style="display: flex; gap: 10px;">
<img src="/developer-settings.png" alt="Developer Settings" height="50%" width="50%" />
<img src="/developer-settings-endpoint.png" alt="Developer Settings - Server Endpoint" height="50%" width="50%" />
</div>

### Desktop

Tap 7 times on the onboarding screen to configure the server endpoint to be used.

<div align="center">

![Setting a custom server on the onboarding screen on desktop or self-hosted web
apps](web-dev-settings.png){width=400px}

</div>

## Step 7: Configure Ente CLI

You can download Ente CLI from [here](https://github.com/ente/ente/releases?q=tag%3Acli).

Check our [documentation](/self-hosting/administration/cli) on how to use Ente CLI for managing self-hosted instances.

> [!NOTE]
>
> **For upgrading**
>
> Check out our [upgrading documentation](/self-hosting/installation/upgrade) for various installation methods.
