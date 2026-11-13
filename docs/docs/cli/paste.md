# Paste

Share text through a link that works once:

```sh
ente paste create "Meeting room code: 4821"
```

```
https://paste.ente.com/aB3dE9fG#k7Qw...
```

Send the whole link, including the part after `#`; that part is the decryption key and never reaches the server. The first person to open the link reads the text, and the server deletes it. Unread pastes expire after 24 hours. No account is needed.

## Add a password

```sh
ente paste create --input notes.txt --password
```

The CLI asks for a paste password and its confirmation. The reader needs both the link and the password.

## Open a paste once

```sh
ente paste consume "https://paste.ente.com/aB3dE9fG#k7Qw..."
```

Prints the text without a trailing newline and asks for the password when the paste has one. The server copy is deleted as soon as it is fetched, even if the key or password is wrong, so a prompted retry only works while the command is still running. On a terminal, control characters other than tabs and newlines are escaped; add `--raw` to print them as they are. With a token and the key as separate values, run `ente paste consume aB3dE9fG --key k7Qw...`.

## Use from a script

```sh
ente paste create --input notes.txt --password --json
cat notes.txt | ente paste create
ente paste consume "$URL" --json
```

`create` returns `{"url": "..."}` and `consume` returns `{"text": "..."}`. Piped stdin is read when no text or `--input` is given. `--password` still decides whether a paste is protected; `ENTE_CLI_PASSWORD` only supplies the password instead of a prompt. When opening a protected paste, a wrong value fails immediately and the paste is gone.

## Use your own server

```sh
ente paste create "hello" --host https://api.example.org --paste-origin https://paste.example.org
ente paste consume "https://paste.example.org/aB3dE9fG#k7Qw..." --host https://api.example.org
```

`--host` is the API server; `--paste-origin` is the website written into the link.

## Limits

- 4,000 characters; some emoji count as more than one. Text cannot be blank.
- One read, then gone; 24 hours at most.
