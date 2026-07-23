# Ente CLI

The Ente CLI is a Command Line Utility for exporting data from [Ente](https://ente.com). It also does a few more things, for example, you can use it to decrypt the export from Ente Auth.

## Install

The easiest way is to download a pre-built binary from the [GitHub releases](https://github.com/ente/ente/releases?q=tag%3Acli-v0).

You can also build these binaries yourself

```sh
./release.sh
```

Or you can build from source

```sh
 go build -o "bin/ente" main.go
```

The generated binaries are standalone, static binaries with no dependencies. You can run them directly, or put them somewhere in your PATH.

There is also an option to use [Docker](#docker).

## Usage

Run the help command to see all available commands.

```sh
ente --help
```

### Accounts

If you wish, you can add multiple accounts (your own and that of your family members) and export all data using this tool.

#### Add an account

```sh
ente account add
```

> [!NOTE]
>
> `ente account add` does not create new accounts, it just adds pre-existing accounts to the list of accounts that the CLI knows about so that you can use them for other actions.

#### List accounts

```sh
ente account list
```

#### Change export directory

```sh
ente account update --app auth/photos --email email@domain.com --dir ~/photos
```

### Export

#### Start export

```sh
ente export
```

### CLI Docs

You can view more cli documents at [docs](docs/generated/ente.md). To update the docs, run the following command:

```sh
go run main.go docs
```

## Docker

If you fancy Docker, you can also run the CLI within a container.

### Configure

Modify the `docker-compose.yml` and add volume. `cli-data` volume is mandatory, you can add more volumes for your export directory.

Build and run the container in detached mode

```sh
docker-compose up -d --build
```

Note that [BuildKit](https://docs.docker.com/go/buildkit/) is needed to build this image. If you face this issue, a quick fix is to add `DOCKER_BUILDKIT=1` in front of the build command.

`exec` into the container

```sh
docker-compose exec ente-cli /bin/sh -c "./ente-cli version"
docker-compose exec ente-cli /bin/sh -c "./ente-cli account add"
```
