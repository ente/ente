Fetch a website icon from one HTTP(S) URL using `ente-core::http`. Returns a static PNG, or `None` if no supported icon is found. Requires native Rust with Tokio.

```rust,no_run
let icon = ente_icons::Fetcher::new()?.fetch("https://example.com").await?;
```
