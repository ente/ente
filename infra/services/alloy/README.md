# Alloy

Install `alloy.service` on an instance if it is running something whose logs we want in Grafana.

## Installing

Replace `endpoint.url` in the config file with the Loki URL that Alloy should connect to, and move the files to their expected place.

```sh
scp services/alloy/{alloy.service,config.alloy} <instance>:

nano config.alloy
sudo mv config.alloy /root/config.alloy
sudo mv alloy.service /etc/systemd/system/alloy.service
```

Tell systemd to pick up new service definitions, enable the unit (so that it automatically starts on boot), and start it this time around.

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now alloy
```
