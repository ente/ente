#!/usr/bin/env bash

set -euo pipefail

readonly repo_root="$(git rev-parse --show-toplevel)"
readonly mobile_dir="$repo_root/mobile"
readonly photos_dir="$mobile_dir/apps/photos"
readonly flutter_bin="${FLUTTER_BIN:-flutter}"
readonly pod_bin="${POD_BIN:-pod}"
readonly expected_pod_version="1.17.0"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Self-hosted iOS validation requires macOS." >&2
  exit 1
fi

actual_pod_version="$($pod_bin --version)"
if [[ "$actual_pod_version" != "$expected_pod_version" ]]; then
  echo "Expected CocoaPods $expected_pod_version, found $actual_pod_version." >&2
  exit 1
fi

cd "$mobile_dir"
"$flutter_bin" pub get --enforce-lockfile

cd "$photos_dir"
"$flutter_bin" test --no-pub \
  test/scripts/build_self_hosted_ios_adhoc_test.dart \
  test/scripts/prepare_self_hosted_ios_release_test.dart \
  test/scripts/publish_self_hosted_ios_release_test.dart \
  test/scripts/self_hosted_ios_identity_test.dart

cd "$photos_dir/ios"
"$pod_bin" install --deployment

cd "$repo_root"
git diff --exit-code
git diff --check
echo "Self-hosted mobile macOS validation passed."
