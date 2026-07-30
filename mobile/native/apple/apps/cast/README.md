# Ente Cast for tvOS

Source code for the Ente Cast tvOS app.

## Building from source

1. Install [Xcode](https://developer.apple.com/xcode/) and [Rust](https://www.rust-lang.org/tools/install). In Xcode install the tvOS platform.

2. Generate the Swift bindings:

   ```sh
   cd rust
   cargo codegen native cast
   ```

3. Open `Cast.xcodeproj` in Xcode and run the `Cast` scheme.

> [!NOTE]
>
> The first build will install the Rust `nightly` toolchain and `rust-src`. They are needed for building Rust for tvOS targets.
>
> Re-run `cargo codegen native cast` whenever the UniFFI-exported surface of the cast crate (`rust/bindings/uniffi/cast`) changes.
