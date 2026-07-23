# ente-test-support

Runs a local Museum backed by temporary Postgres and object storage for use by various Rust integration tests.

## Setup

Requires `go` on PATH to build and run Museum. The Postgres binary ([postgresql_embedded](https://crates.io/crates/postgresql_embedded)) is downloaded and cached on first use.

## Usage

Tests that use it are gated behind a Cargo feature so that a plain `cargo test` skips them. They can be run by enabling the `museum` feature, e.g.:

```sh
cargo test -p ente-rs --features museum
```
