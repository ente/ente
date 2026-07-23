# Rust

Cargo workspace for Ente's Rust code.

## Development

```sh
cargo fmt        # Format
cargo clippy     # Lint
cargo build      # Build
cargo test       # Test

cargo run --bin ente-rs -- --help   # Run the Ente Rust CLI
```

CI runs with `RUSTFLAGS="-D warnings"` so warnings will cause checks to fail.

Other useful commands:

```sh
cargo codegen native  # Regenerate bindings used by native apps
cargo codegen frb     # Regenerate bindings used by Flutter apps

# Run integration tests against a local Museum
cargo test --features museum,ente-photos/ml-assets
```
