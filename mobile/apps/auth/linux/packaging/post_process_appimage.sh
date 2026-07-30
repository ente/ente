#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <path-to-appimage>" >&2
    exit 2
fi

appimage="$1"
if [[ ! -f "$appimage" ]]; then
    echo "AppImage not found: $appimage" >&2
    exit 1
fi

if ! command -v appimagetool >/dev/null 2>&1; then
    echo "appimagetool is required to rebuild the AppImage" >&2
    exit 1
fi

appimage_dir="$(cd "$(dirname "$appimage")" && pwd)"
appimage_name="$(basename "$appimage")"
appimage_path="$appimage_dir/$appimage_name"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

cp "$appimage_path" "$workdir/input.AppImage"
chmod +x "$workdir/input.AppImage"

(
    cd "$workdir"
    ./input.AppImage --appimage-extract >/dev/null
)

appdir="$workdir/squashfs-root"

if [[ -d "$appdir/usr/lib" ]]; then
    runtime_libs="$(
        find "$appdir/usr/lib" \( -type f -o -type l \) \( \
            -name 'libstdc++.so*' -o \
            -name 'libgcc_s.so*' \
        \) -print
    )"
    if [[ -n "$runtime_libs" ]]; then
        echo "Removing bundled C++ runtime libraries from the AppImage:"
        echo "$runtime_libs"
        printf '%s\n' "$runtime_libs" | while IFS= read -r runtime_lib; do
            rm -f "$runtime_lib"
        done
    fi

    blocked_libs="$(
        find "$appdir/usr/lib" \( -type f -o -type l \) \( \
            -name 'libGL.so*' -o \
            -name 'libEGL.so*' -o \
            -name 'libGLES*.so*' -o \
            -name 'libGLX.so*' -o \
            -name 'libOpenGL.so*' -o \
            -name 'libdrm.so*' -o \
            -name 'libgbm.so*' -o \
            -name 'libglapi.so*' -o \
            -name 'libwayland-client.so*' -o \
            -name 'libwayland-egl.so*' \
        \) -print
    )"
    if [[ -n "$blocked_libs" ]]; then
        echo "Refusing to ship graphics stack libraries in the AppImage:" >&2
        echo "$blocked_libs" >&2
        exit 1
    fi
fi

cat >"$appdir/AppRun" <<'APPRUN'
#!/usr/bin/env bash
set -e

APPDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export APPDIR
cd "$APPDIR"

HOST_LIBRARY_PATH="/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu:/lib64:/usr/lib64:/lib:/usr/lib"
BUNDLED_LIBRARY_PATH="$APPDIR/usr/lib"

if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then
    export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$HOST_LIBRARY_PATH:$BUNDLED_LIBRARY_PATH"
else
    export LD_LIBRARY_PATH="$HOST_LIBRARY_PATH:$BUNDLED_LIBRARY_PATH"
fi

exec "$APPDIR/enteauth" "$@"
APPRUN
chmod +x "$appdir/AppRun"

output="$workdir/${appimage_name%.AppImage}.processed.AppImage"
ARCH=x86_64 appimagetool "$appdir" "$output" >/dev/null
mv "$output" "$appimage_path"
chmod +x "$appimage_path"

echo "Post-processed AppImage: $appimage_path"
