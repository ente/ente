# Listmonk

We use [Listmonk](https://listmonk.app/) to manage our mailing lists.

- Museum lets Listmonk know about new users and account deletion (this allows Listmonk to create corresponding accounts).

- Subsequently, Listmonk handles user subscription / unsubscription etc (Listmonk stores its data in an external Postgres).

## Installing

Install [nginx](../nginx/README.md).

Add Listmonk's configuration.

```sh
sudo mkdir -p /root/listmonk
sudo tee /root/listmonk/config.toml
```

Add the service definition and nginx configuration.

```sh
scp services/listmonk/listmonk.* <instance>:

sudo mv listmonk.service /etc/systemd/system/
sudo mv listmonk.nginx.conf /root/nginx/conf.d
```

> The very first time we ran Listmonk, at this point we also needed to get it to install the tables it needs in the Postgres DB. For this, we used the `initialize-db.sh` script.
>
> ```sh
> scp services/listmonk/initialize-db.sh <instance>:
>
> sudo sh initialize-db.sh
> rm initialize-db.sh
> ```

Tell systemd to pick up new service definitions, enable the unit (so that it automatically starts on boot), and start it this time around.

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now listmonk
```

Tell nginx to pick up the new configuration.

```sh
sudo systemctl reload nginx
```
