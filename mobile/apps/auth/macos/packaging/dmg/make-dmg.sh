#!/bin/sh

# Package the built "Ente Auth.app" into a release DMG.
#
#     make-dmg.sh path/to/Ente\ Auth.app out.dmg
#
# The Finder appearance (window size, icon positions) comes from the
# committed DS_Store.

set -eu

app=$1
out=$2

here=$(dirname "$0")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Stage the volume contents: the app, an /Applications link to drag it
# into, the Finder layout, and the volume icon.
vol="$tmp/vol"
mkdir "$vol" "$vol/.background"
cp -R "$app" "$vol/Ente Auth.app"
ln -s /Applications "$vol/Applications"
cp "$here/DS_Store" "$vol/.DS_Store"
tiffutil -cathidpicheck "$here/background.png" "$here/background@2x.png" \
    -out "$vol/.background/background.tiff"

icon="$here/../../../assets/generation-icons/icon-macos.png"
iconset="$tmp/icon.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$icon" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" "$icon" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns "$iconset" --output "$vol/.VolumeIcon.icns"

# Package in two steps: Finder shows .VolumeIcon.icns only if the volume
# root has the custom-icon flag, which must be set on the live volume (it
# does not survive the -srcfolder copy into the image).
custom_icon_flag="0000000000000000040000000000000000000000000000000000000000000000"
hdiutil create -volname Auth -fs HFS+ -format UDRW -srcfolder "$vol" "$tmp/rw.dmg"
mkdir "$tmp/mnt"
hdiutil attach "$tmp/rw.dmg" -nobrowse -noautoopen -mountpoint "$tmp/mnt"
xattr -wx com.apple.FinderInfo "$custom_icon_flag" "$tmp/mnt"
hdiutil detach "$tmp/mnt"
hdiutil convert "$tmp/rw.dmg" -format UDZO -ov -o "$out"
