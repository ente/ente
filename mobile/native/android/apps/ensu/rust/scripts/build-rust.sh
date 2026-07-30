#!/usr/bin/env bash

# This script is invoked from Gradle's `buildRustJni` task.
# It builds the JNI library used by Ensu's generated UniFFI bindings.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/../../../../../../.." && pwd)
TARGET_DIR="$REPO_ROOT/rust/target"
TOOLCHAIN=""
OUT_DIR=""

ABIS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --toolchain) TOOLCHAIN=$2; shift 2 ;;
        --out-dir)   OUT_DIR=$2; shift 2 ;;
        *)           ABIS+=("$1"); shift ;;
    esac
done
[[ -n $TOOLCHAIN && -n $OUT_DIR && ${#ABIS[@]} -gt 0 ]] || {
    echo "usage: $(basename "$0") --toolchain DIR --out-dir DIR <abi> [<abi>...]" >&2
    exit 1
}

# Gradle's build-task PATH omits Homebrew and rustup's bin dir.
export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

for tool in cargo rustup cmake; do
    command -v "$tool" >/dev/null || { echo "error: $tool not on PATH" >&2; exit 1; }
done

build_abi() {
    local abi=$1 target clang_triple libcxx_dir
    case $abi in
        arm64-v8a)
            target=aarch64-linux-android
            clang_triple=aarch64-linux-android24
            libcxx_dir=aarch64-linux-android
            ;;
        armeabi-v7a)
            target=armv7-linux-androideabi
            clang_triple=armv7a-linux-androideabi24
            libcxx_dir=arm-linux-androideabi
            ;;
        x86_64)
            target=x86_64-linux-android
            clang_triple=x86_64-linux-android24
            libcxx_dir=x86_64-linux-android
            ;;
        *) echo "error: unsupported ABI $abi" >&2; exit 1 ;;
    esac

    local linker=$TOOLCHAIN/bin/$clang_triple-clang
    [[ -x $linker ]] || { echo "error: NDK clang not found at $linker (API 24 toolchain missing?)" >&2; exit 1; }

    rustup target list --installed | grep -qx "$target" || rustup target add "$target"

    local lower upper
    lower=${target//-/_}
    upper=$(echo "$lower" | tr a-z A-Z)
    export "CARGO_TARGET_${upper}_LINKER=$linker"
    export "CC_${lower}=$linker"
    export "CXX_${lower}=$TOOLCHAIN/bin/$clang_triple-clang++"
    export "AR_${lower}=$TOOLCHAIN/bin/llvm-ar"
    export "RANLIB_${lower}=$TOOLCHAIN/bin/llvm-ranlib"

    local out=$OUT_DIR/$abi
    mkdir -p "$out"
    echo "==> $abi"
    (cd "$REPO_ROOT/rust/bindings/uniffi/ensu" && CARGO_TARGET_DIR="$TARGET_DIR" cargo build --release --target "$target")
    cp "$TARGET_DIR/$target/release/libensu.so" "$out/"
    cp "$TOOLCHAIN/sysroot/usr/lib/$libcxx_dir/libc++_shared.so" "$out/"
}

for abi in "${ABIS[@]}"; do build_abi "$abi"; done
