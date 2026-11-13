# ente-test-support

Runs a local Museum backed by temporary Postgres and object storage for use by various Rust integration tests.

## Setup

Requires `go` on PATH to build and run Museum. The Postgres binary ([postgresql_embedded](https://crates.io/crates/postgresql_embedded)) is downloaded and cached on first use.

## Usage

Tests that use it are gated behind a Cargo feature so that a plain `cargo test` skips them. They can be run by enabling the `museum` feature, e.g.:

```sh
cargo test -p ente-cli --features museum
```

## Running another test command

`with-museum` keeps an isolated backend alive for a child command, providing its
URL as `NEXT_PUBLIC_ENTE_ENDPOINT` and the test email settings as
`ENTE_TEST_EMAIL_SUFFIX` and `ENTE_TEST_EMAIL_CODE`:

```sh
cargo run -p ente-test-support --bin with-museum -- <command> [args...]
```

The command inherits the working directory and standard streams. Backend resources
are cleaned up after it exits; a failed command retains Museum's diagnostic
directory. Web browser tests also use this runner.
