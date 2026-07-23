# Promtail

Install `promtail.service` on an instance if it is running something whose logs we want in Grafana.

## Installing

Replace `client.url` in the config file with the Loki URL that Promtail should connect to, and move the files to their expected place.

```sh
scp services/promtail/promtail.* <instance>:

nano promtail.yaml
sudo mv promtail.yaml /root/promtail.yaml
sudo mv promtail.service /etc/systemd/system/promtail.service
```

Tell systemd to pick up new service definitions, enable the unit (so that it automatically starts on boot), and start it this time around.

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now promtail
```
