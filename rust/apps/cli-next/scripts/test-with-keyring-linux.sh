#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
if [[ $(uname -s) != Linux ]]; then
    echo "The native Linux keyring test requires Linux." >&2
    exit 1
fi

test_name=native_keyring_survives_separate_processes
executable=$(cargo test --locked -p ente-cli-next --test cli --no-run \
    --message-format=json-render-diagnostics "$@" | python3 -c '
import json, sys
artifacts = [json.loads(line) for line in sys.stdin]
executable, = [a["executable"] for a in artifacts
              if a.get("reason") == "compiler-artifact" and a["target"]["name"] == "cli"
              and a.get("executable")]
print(executable)
')
listing=$("$executable" --ignored --exact "$test_name" --list)
if ! grep -Fxq "$test_name: test" <<< "$listing"; then
    echo "Native keyring test not found; nothing was run." >&2
    exit 1
fi

keyring_home=$(mktemp -d)
trap 'rm -rf "$keyring_home"' EXIT
env -i PATH="$PATH" HOME="$keyring_home" XDG_DATA_HOME="$keyring_home/data" \
    XDG_RUNTIME_DIR="$keyring_home" dbus-run-session -- bash -euc '
        printf %s native-test | gnome-keyring-daemon --foreground --unlock --components=secrets &
        daemon=$!
        trap '\''kill "$daemon" 2>/dev/null || true; wait "$daemon" 2>/dev/null || true'\'' EXIT
        gdbus wait --session --timeout 30 org.freedesktop.secrets
        "$@"
    ' -- "$executable" --ignored --exact "$test_name"
