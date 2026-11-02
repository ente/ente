# Rust

## Testing

- All code must be tested end to end.
- Unit tests are fine and encouraged for broader coverage, but correctness of a unit in isolation is not enough. `crates/test-support/` allows testing code in `crates/` against a local Ente setup (Museum, object storage, and database). Where UX is involved, exposing the feature through the CLI and driving it in a CLI test is also an option.
- If a committed test would need an inordinate amount of scaffolding, manually test the behavior before opening the PR. Clearly communicate what was tested and any remaining gaps to the developer and in the PR.

## Shared code

- Over time, we want all clients to use the same solid and tested Rust core. When moving functionality into Rust, also expose it through the CLI. CLI exposure can follow in a separate PR. Eventually, anything a customer can do in any of our apps, they and their agents should be able to do through the CLI. This includes lab projects like Ensu and Space, and toys like Paste.
- Design idiomatic Rust APIs first, then adapt them to each client language. The shape of a JavaScript or Dart caller should not dictate the shared Rust API.
- Keep `ente-core` small, with shared primitives and protocol mechanisms. Product behavior belongs in the product crates. A new crate should represent a meaningful boundary, not just provide a home for a helper. Call out changes to core to the developer.
- `Session` is the shared authenticated context. Pass `&Session` to domain functions. Do not accumulate product methods on it or add another context type or service factory around it.
- The consuming platform owns its databases and schemas. Keep platform persistence choices out of shared product APIs.
- Keep shared types about the domain. Build consumer-specific projections, such as export metadata and diagnostic reports, in the consumer, reusing the shared interpretation.
- Shared crates return data and errors describing what happened. The consuming app supplies user-facing wording and recovery instructions.
- Use `ente_core::crypto` for cryptographic primitives. Fix missing or incorrect behavior there instead of adding another implementation in a consumer.

## Bindings

- `bindings/` should not have any logic beyond translating representations and errors. Rule of thumb: if it is not a dumb conduit, something is wrong. Business rules, request orchestration, and fallback decisions belong in the domain crate.
- For WASM, use scalars and bytes directly, Serde and Tsify for plain records, and handles for stateful objects. Keep handle cleanup in the client wrapper so callers do not have to manage the binding.
- Respect the actual wire and storage encodings. Do not add base64 round trips just to cross a binding. Use the same principles across client languages, with an idiomatic implementation in each.
- Shared binding libraries hold the reusable conversions. App binding crates select what their app needs. Choose feature boundaries around useful capabilities instead of adding a flag for every function.

## Size and dependencies

- Track the size of the generated WASM when surfacing Rust code for web. Call out non-trivial or unexpected increases to the developer; they may require restructuring the code. This applies to API additions and newly enabled features too, even when no new dependency is added.
- Prefer pure Rust and existing primitives where they fit. Consider the cost to every client that consumes the crate, and measure the shipped artifact. Keep native dependencies such as SQLCipher and OpenSSL confined to the consumers that need them, accounting for Cargo feature unification.

## CLI

- When adding functionality to the CLI, document it in the CLI help and in the documentation website (`docs/docs/cli/` at the repository root, published at https://ente.com/help/cli/). Follow their existing tone and conventions.
- Released storage formats and CLI interfaces are commitments to users. This includes the vault, account and export databases, keyring entries, export layout and metadata, JSON output, and environment variables. Discuss changes that require migration or break existing workflows with the developer before implementing them.
- The export folder belongs to the user. Keep operational bookkeeping in the CLI database. Ente-specific metadata belongs in `export.json` and the `ente` sections of the metadata files; do not add extra bookkeeping files to the export.
