#!/bin/sh
set -eu

# This script is invoked from Xcode's "Run Script" build phase.
# It builds the cast UniFFI static lib for the current tvOS target.

REPO_ROOT=$(cd "$SRCROOT/../../../../.." && pwd)
GENERATED_DIR="$SRCROOT/Cast/Generated"
OUT_DIR="$TARGET_TEMP_DIR/cast_rust"
LIB=libcast.a

export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

if [ ! -f "$GENERATED_DIR/cast.swift" ] || [ ! -f "$GENERATED_DIR/castFFI.h" ] || [ ! -f "$GENERATED_DIR/castFFI.modulemap" ]; then
    echo "error: missing generated cast UniFFI bindings in $GENERATED_DIR" >&2
    echo "  run: (cd $REPO_ROOT/rust && cargo codegen native cast)" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"

# Rust supports tvOS targets, but rustup does not ship precompiled std for them.
# Building std from source requires nightly and rust-src.
rustup toolchain list | grep -q '^nightly-' \
    || rustup toolchain install nightly --profile minimal
rustup component list --toolchain nightly --installed | grep -qx rust-src \
    || rustup component add rust-src --toolchain nightly

case "${CONFIGURATION:-Debug}" in
    Release) profile=release; release_flag=--release ;;
    *) profile=debug; release_flag= ;;
esac

sdk=$(xcrun --sdk "$PLATFORM_NAME" --show-sdk-path)
clang=$(xcrun --sdk "$PLATFORM_NAME" --find clang)
libs=

for arch in $ARCHS; do
    case "$PLATFORM_NAME:$arch" in
        appletvos:arm64) target=aarch64-apple-tvos; min_flag=-mtvos-version-min ;;
        appletvsimulator:arm64) target=aarch64-apple-tvos-sim; min_flag=-mtvos-simulator-version-min ;;
        appletvsimulator:x86_64) target=x86_64-apple-tvos; min_flag=-mtvos-simulator-version-min ;;
        *) echo "unsupported arch: $PLATFORM_NAME/$arch" >&2; exit 1 ;;
    esac

    rustflags="-C linker=$clang -C link-arg=-isysroot -C link-arg=$sdk -C link-arg=$min_flag=$TVOS_DEPLOYMENT_TARGET"

    (
        cd "$REPO_ROOT/rust"
        CC="$clang" \
            CFLAGS="-isysroot $sdk" \
            RUSTFLAGS="$rustflags" \
            cargo +nightly build -Z build-std --locked -p ente-cast-uniffi --target "$target" $release_flag
    )

    built="$REPO_ROOT/rust/target/$target/$profile/$LIB"
    cp "$built" "$OUT_DIR/$arch.a"
    libs="$libs $OUT_DIR/$arch.a"
done

set -- $libs
if [ "$#" -eq 1 ]; then
    cp "$1" "$OUT_DIR/$LIB"
else
    lipo -create "$@" -output "$OUT_DIR/$LIB"
fi
