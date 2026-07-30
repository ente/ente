#!/usr/bin/env bash

# This script is invoked from Xcode's "Run Script" build phase.
# It builds the Rust static library used by Ensu's generated UniFFI bindings.

set -euo pipefail

: "${SRCROOT:?}" "${TARGET_TEMP_DIR:?}" "${PLATFORM_NAME:?}" "${ARCHS:?}"

REPO_ROOT=$(cd "$SRCROOT/../../../../.." && pwd)
GENERATED_DIR="$SRCROOT/Ensu/Generated"
OUT_DIR="$TARGET_TEMP_DIR/ensu_rust"
TARGET_DIR="$REPO_ROOT/rust/target"
mkdir -p "$GENERATED_DIR" "$OUT_DIR"

# Xcode's build-phase PATH omits Homebrew and rustup's install dir.
export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

for tool in cargo rustup cmake; do
    command -v "$tool" >/dev/null || { echo "error: $tool not on PATH" >&2; exit 1; }
done

if [[ ! -f "$GENERATED_DIR/ensu.swift" \
   || ! -f "$GENERATED_DIR/ensuFFI.h" \
   || ! -f "$GENERATED_DIR/ensuFFI.modulemap" ]]; then
    echo "error: missing generated Ensu UniFFI bindings in $GENERATED_DIR" >&2
    echo "  run: (cd $REPO_ROOT/rust && cargo codegen native)" >&2
    exit 1
fi

# Host build scripts compile against macOS; each target uses its own SDK below.
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
TARGET_SDKROOT=$(xcrun --sdk "$PLATFORM_NAME" --show-sdk-path)
TARGET_CLANG=$(xcrun --sdk "$PLATFORM_NAME" --find clang)
export SDKROOT
[[ -n "${IPHONEOS_DEPLOYMENT_TARGET:-}" ]] && \
    export CMAKE_OSX_DEPLOYMENT_TARGET="$IPHONEOS_DEPLOYMENT_TARGET"

case "${CONFIGURATION:-Debug}" in
    Release) profile=release; cargo_flags=(--locked --release) ;;
    *)       profile=debug;   cargo_flags=(--locked) ;;
esac

rust_target_for() {
    case "$1:$2" in
        iphoneos:arm64)         echo aarch64-apple-ios ;;
        iphonesimulator:arm64)  echo aarch64-apple-ios-sim ;;
        *) return 1 ;;
    esac
}

build_crate() {
    local name=$1 crate_dir=$2 lib=$3
    local arch_libs=()

    echo "==> $name ($profile, $PLATFORM_NAME: $ARCHS)"

    for arch in $ARCHS; do
        local target
        target=$(rust_target_for "$PLATFORM_NAME" "$arch") || {
            echo "    skip: unsupported $PLATFORM_NAME/$arch" >&2
            continue
        }

        rustup target list --installed | grep -qx "$target" \
            || rustup target add "$target"

        local suffix
        suffix=$(echo "$target" | tr '[:lower:]-' '[:upper:]_')
        export "CARGO_TARGET_${suffix}_LINKER=$TARGET_CLANG"
        export "CFLAGS_${suffix}=-isysroot $TARGET_SDKROOT"
        export "CXXFLAGS_${suffix}=-isysroot $TARGET_SDKROOT"

        local rustflags="${RUSTFLAGS:-} -C link-arg=-isysroot -C link-arg=$TARGET_SDKROOT"
        if [[ -n "${IPHONEOS_DEPLOYMENT_TARGET:-}" ]]; then
            local min_flag
            case $PLATFORM_NAME in
                iphoneos)        min_flag=-miphoneos-version-min ;;
                iphonesimulator) min_flag=-mios-simulator-version-min ;;
            esac
            rustflags+=" -C link-arg=$min_flag=$IPHONEOS_DEPLOYMENT_TARGET"
        fi

        (cd "$crate_dir" && RUSTFLAGS="$rustflags" CARGO_TARGET_DIR="$TARGET_DIR" cargo rustc "${cargo_flags[@]}" --target "$target" --lib --crate-type staticlib)

        local built="$TARGET_DIR/$target/$profile/$lib"
        [[ -f "$built" ]] || { echo "error: expected $built" >&2; exit 1; }

        local arch_lib="$OUT_DIR/${lib%.a}_${arch}.a"
        cp "$built" "$arch_lib"
        arch_libs+=("$arch_lib")
    done

    local out="$OUT_DIR/$lib"
    rm -f "$out"
    case ${#arch_libs[@]} in
        0) echo "error: no supported archs for $name" >&2; exit 1 ;;
        1) cp "${arch_libs[0]}" "$out" ;;
        *) lipo -create "${arch_libs[@]}" -output "$out" ;;
    esac
    echo "    -> $out"
}

build_crate ensu "$REPO_ROOT/rust/bindings/uniffi/ensu" libensu.a
