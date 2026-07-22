#!/usr/bin/env bash

set -euo pipefail

readonly repo_root="$(git rev-parse --show-toplevel)"
readonly mobile_dir="$repo_root/mobile"
readonly photos_dir="$mobile_dir/apps/photos"
readonly rust_dir="$repo_root/rust"
readonly flutter_bin="${FLUTTER_BIN:-flutter}"
readonly dart_bin="${DART_BIN:-dart}"
readonly cargo_bin="${CARGO_BIN:-cargo}"
readonly public_endpoint="https://photos.example.com"

readonly -a endpoint_tests=(
  test/core/network/endpoint_policy_test.dart
  test/core/network/endpoint_switcher_test.dart
  test/ui/settings/developer_settings_lock_test.dart
  test/ui/settings/server_settings_page_test.dart
)
readonly -a linux_release_tests=(
  test/scripts/prepare_self_hosted_android_release_test.dart
  test/scripts/publish_self_hosted_android_release_test.dart
)

cd "$mobile_dir"
"$flutter_bin" pub get --enforce-lockfile

cd "$rust_dir"
"$cargo_bin" codegen frb
git -C "$repo_root" diff --exit-code

cd "$photos_dir"
"$flutter_bin" test --no-pub \
  "${endpoint_tests[@]}" \
  "${linux_release_tests[@]}"

"$flutter_bin" test --no-pub \
  --dart-define=configurableEndpoint=true \
  --dart-define="endpoint=$public_endpoint" \
  "${endpoint_tests[@]}"

"$flutter_bin" test --no-pub \
  --dart-define=lockedEndpoint=true \
  --dart-define="endpoint=$public_endpoint" \
  "${endpoint_tests[@]}"

cd "$repo_root"
git ls-files -z -- "*.dart" |
  xargs -0 -n 200 "$dart_bin" format \
    --output=none \
    --set-exit-if-changed
git diff --exit-code

cd "$mobile_dir"
"$flutter_bin" analyze --no-pub

cd "$repo_root"
git diff --check
echo "Self-hosted mobile Linux validation passed."
