# Rust

Cargo workspace for Ente's Rust code.

## Development

```sh
cargo fmt        # Format
cargo clippy     # Lint
cargo build      # Build
cargo test --workspace --exclude ente-cli  # Test libraries with SQLite
cargo test -p ente-cli                     # Test CLI with SQLCipher

cargo run -p ente-cli -- --help   # Run the Ente Rust CLI
```

CI runs with `RUSTFLAGS="-D warnings"` so warnings will cause checks to fail.

Other useful commands:

```sh
cargo codegen native  # Regenerate bindings used by native apps
cargo codegen frb     # Regenerate bindings used by Flutter apps
cargo codegen napi    # Regenerate bindings used by Desktop (Electron) apps

# Run integration tests against a local Museum
cargo test --workspace --exclude ente-cli --features museum,ente-ml/ml-assets
cargo test -p ente-cli --features museum
```
