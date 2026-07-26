#!/usr/bin/env bash
#
# Build the current working tree of Ente Auth and put it on the iPhone.
#
#   ./deploy-ente-auth.sh              debug build (default), install + launch
#   ./deploy-ente-auth.sh --release    release build: no DEBUG banner, real speed
#   ./deploy-ente-auth.sh --no-launch  install only, don't launch
#   DEVICE=<udid> ./deploy-ente-auth.sh
#
# Whatever is checked out in the repo is what gets built — switch branches or
# pull first if you want something else.
#
# Signing comes from the settings committed in the repo: team BCU8ZR2922,
# bundle io.ente.auth.bftest, entitlements emptied so a free Apple account can
# sign it. That means no push notifications and no passkey autofill, and the
# app stops launching about 7 days after install. Rerun this to renew it.

set -euo pipefail

APP_DIR="/Users/benhome/Desktop/Projects/ente/mobile/apps/auth"
FLUTTER="${FLUTTER:-$HOME/flutter/bin/flutter}"
DEVICE="${DEVICE:-00008150-001649221ABB401C}"   # Ben's iPhone
MODE=debug
LAUNCH=1

usage() { sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//'; }

for arg in "$@"; do
  case "$arg" in
    --release)   MODE=release ;;
    --debug)     MODE=debug ;;
    --no-launch) LAUNCH=0 ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

[ -x "$FLUTTER" ] || { echo "flutter not found at $FLUTTER (override with \$FLUTTER)" >&2; exit 1; }
[ -d "$APP_DIR" ] || { echo "app not found at $APP_DIR" >&2; exit 1; }
cd "$APP_DIR"

# A free Apple account cannot sign Ente's own bundle ID, so catch that before
# spending three minutes on a build that can only fail at the signing step.
if grep -q "PRODUCT_BUNDLE_IDENTIFIER = io.ente.auth;" ios/Runner.xcodeproj/project.pbxproj; then
  echo "ios/Runner.xcodeproj still uses Ente's own bundle ID io.ente.auth." >&2
  echo "A free account can't sign that. Set PRODUCT_BUNDLE_IDENTIFIER to" >&2
  echo "io.ente.auth.bftest and DEVELOPMENT_TEAM to BCU8ZR2922, and empty out" >&2
  echo "ios/Runner/Runner.entitlements, then run this again." >&2
  exit 1
fi

echo "==> Building Ente Auth ($MODE) — $(git rev-parse --abbrev-ref HEAD) @ $(git rev-parse --short HEAD)"
"$FLUTTER" build ios "--$MODE"

APP="$APP_DIR/build/ios/iphoneos/Runner.app"
[ -d "$APP" ] || { echo "build finished but produced no app at $APP" >&2; exit 1; }
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")

echo "==> Installing $BUNDLE_ID on $DEVICE"
if ! xcrun devicectl device install app --device "$DEVICE" "$APP"; then
  echo >&2
  echo "Install failed. Devices this Mac can see:" >&2
  xcrun devicectl list devices >&2 || true
  echo >&2
  echo "If the phone isn't listed, plug it in (or put it on the same Wi-Fi)," >&2
  echo "unlock it, and trust this Mac. Pass DEVICE=<udid> to target another one." >&2
  exit 1
fi

if [ "$LAUNCH" -eq 0 ]; then
  echo "==> Installed. Not launching (--no-launch)."
  exit 0
fi

echo "==> Launching"
for attempt in $(seq 1 6); do
  if out=$(xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" 2>&1); then
    echo "==> Ente Auth is running on the phone."
    exit 0
  fi
  # The phone refuses to launch anything while locked, which is the usual
  # reason to land here — wait it out rather than failing the whole run.
  if grep -q "could not be, unlocked" <<<"$out"; then
    echo "    Phone is locked — unlock it (attempt $attempt/6, retrying in 10s)"
    sleep 10
    continue
  fi
  # iOS won't run a free-signed app until the certificate behind it is trusted
  # by hand, and a fresh certificate resets that. Nothing this script can do.
  if grep -q "has not been explicitly trusted by the user" <<<"$out"; then
    echo >&2
    echo "The app is installed, but iOS won't run it until you trust the" >&2
    echo "developer certificate. On the phone:" >&2
    echo >&2
    echo "  Settings > General > VPN & Device Management" >&2
    echo "    > Apple Development: <your Apple ID> > Trust" >&2
    echo >&2
    echo "Then tap Ente Auth, or rerun this script. You only need to do this" >&2
    echo "when the certificate changes, not on every install." >&2
    exit 1
  fi
  echo "$out" >&2
  echo >&2
  echo "Launch failed, but the app is installed — tap Ente Auth on the phone." >&2
  exit 1
done

echo "Phone stayed locked. The app is installed — unlock it and tap Ente Auth." >&2
exit 1
