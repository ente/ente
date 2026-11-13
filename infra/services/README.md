# Services

"Services" are Docker images we run on our instances and manage using systemd.

Generally our services (including museum itself) follow the same pattern:

- They're run on vanilla Ubuntu instances. The only expectation they have is for Docker to be installed.

- They log to fixed, known locations such as `/root/var/logs/foo.log` so Alloy can ingest them when needed.

- Each service should consist of a Docker image (or a Docker compose file), and a systemd unit file.

- To start / stop / schedule the service, we use systemd.

- Each time the service runs it should pull the latest Docker image, so there is no separate installation/upgrade step needed. We can just restart the service, and it'll use the latest code.

- Any credentials and/or configuration should be read by mounting the appropriate file from `/root/service-name` into the running Docker container.

- There are exceptions to this general pattern (See [sentry](sentry)).

## Systemd cheatsheet

```sh
sudo systemctl status my-service
sudo systemctl start my-service
sudo systemctl stop my-service
sudo systemctl restart my-service
sudo journalctl --unit my-service
```

## Adding a service

Create a systemd unit file (See the various `*.service` files in this repository for examples).

If we want the service to start on boot, add an `[Install]` section to its service file (_note_: starting on boot requires one more step later):

```
[Install]
WantedBy=multi-user.target
```

Copy the service file to the instance where we want to run the service. Services might also have some additional configuration or env files, also copy those to the instance.

```sh
scp services/example.service example.env <instance>:
```

SSH into the instance.

```sh
ssh <instance>
```

Move the service to `/etc/systemd/system`, and put configuration files containing credentials under `/root`.

```sh
sudo mv example.service /etc/systemd/system
sudo mv example.env /root
```

Tell systemd to load the unit, enable it on boot, and start it:

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now example
```

To view stdout/err, use:

```sh
sudo journalctl --follow --unit example
```

## Logging

Simple services can log to standard output and error. Docker captures these logs, and Alloy sends them to Grafana.

Services that need a specific job name or more control over retention can log to their own files.

- Such files should be in `/var/logs` within the container, and this should be mounted to `/root/var/logs` on the instance (using the `-v` flag in the service file which launches the Docker container or the Docker compose cluster).

- Add each log file to `alloy/config.alloy` on that instance so Alloy can send it to Grafana.
