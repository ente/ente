# Nginx

This is a base Nginx service that terminates TLS, and can be used as a reverse proxy for arbitrary services by adding new entries in `/root/nginx/conf.d` and `sudo systemctl reload nginx`.

## Installation

Copy the service definition

```sh
scp services/nginx/nginx.service <instance>:

sudo mv nginx.service /etc/systemd/system/nginx.service
```

Create a directory to house service specific configuration

```sh
sudo mkdir -p /root/nginx/conf.d
```

Add the SSL certificate provided by Cloudflare

```sh
sudo tee /root/nginx/cert.pem
sudo tee /root/nginx/key.pem
```

Tell systemd to pick up new service definition, enable it (so that it automatically starts on boot going forward), and start it.

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now nginx
```

## Adding a service

When adding new services that sit behind Nginx,

1. Add its nginx conf file to `/root/nginx/conf.d`

2. Restart nginx (`sudo systemctl reload nginx`)

## Configuration files

All the files we put into `/root/nginx/conf.d` get included in an `http` block. We can see this in the default configuration of nginx:

```
http {
    ...
    include /etc/nginx/conf.d/*.conf;
}
```

> To view the default configuration, run the following command against the [official Docker image for Nginx](https://hub.docker.com/_/nginx), which is also what we use:
>
>     docker run --rm --entrypoint=cat nginx /etc/nginx/nginx.conf > /tmp/nginx.conf

This is a [handy tool](https://nginx-playground.wizardzines.com) to check the syntax of the configuration files. Alternatively, you can run `docker exec nginx nginx -t` on the instance to ask nginx to check the configuration.

## Updating configuration

Nginx configuration files can be changed without needing to restart anything.

1. Update the configuration file at `/root/nginx/conf.d/museum.conf`
2. Verify that there are no errors in the configuration by using `sudo docker exec nginx nginx -t`.
3. Ask nginx to reload the configuration `sudo systemctl reload nginx`.
