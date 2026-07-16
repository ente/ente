#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly app_dir="$(cd "$script_dir/.." && pwd)"
readonly dart_bin="${DART_BIN:-dart}"

cd "$app_dir"
exec "$dart_bin" run scripts/publish_self_hosted_android_release.dart "$@"
