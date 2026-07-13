#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly app_dir="$(cd "$script_dir/.." && pwd)"
readonly flutter_bin="${FLUTTER_BIN:-flutter}"
readonly dart_bin="${DART_BIN:-dart}"
readonly xcodebuild_bin="${XCODEBUILD_BIN:-xcodebuild}"

if [[ -z "${ENTE_SELF_HOSTED_ENDPOINT:-}" ]]; then
  echo "ENTE_SELF_HOSTED_ENDPOINT is required." >&2
  exit 64
fi

cd "$app_dir"
canonical_endpoint="$(
  "$dart_bin" run --verbosity=error \
    scripts/validate_self_hosted_endpoint.dart \
    "$ENTE_SELF_HOSTED_ENDPOINT"
)"
readonly canonical_endpoint

if [[ "${1:-}" == "--validate-only" ]]; then
  if [[ "$#" -ne 1 ]]; then
    echo "--validate-only does not accept additional arguments." >&2
    exit 64
  fi
  echo "Validated locked endpoint: $canonical_endpoint"
  exit 0
fi

for argument in "$@"; do
  case "$argument" in
    -D | -D* | --dart-define | --dart-define=* | --dart-define-from-file | --dart-define-from-file=*)
      echo "The locked build wrapper owns all Dart defines; remove '$argument'." >&2
      exit 64
      ;;
    --config-only | --no-config-only)
      echo "The locked build wrapper owns Xcode configuration; remove '$argument'." >&2
      exit 64
      ;;
  esac
done

echo "Building locked Ente Photos for $canonical_endpoint"

is_simulator=false
configuration="Release"
for argument in "$@"; do
  case "$argument" in
    --simulator)
      is_simulator=true
      configuration="Debug"
      ;;
    --debug)
      configuration="Debug"
      ;;
    --profile)
      configuration="Profile"
      ;;
    --release)
      configuration="Release"
      ;;
  esac
done

if [[ "$is_simulator" == true ]]; then
  "$flutter_bin" build ios \
    "$@" \
    --config-only \
    --dart-define=lockedEndpoint=true \
    --dart-define="endpoint=$canonical_endpoint"

  "$xcodebuild_bin" \
    -workspace ios/Runner.xcworkspace \
    -scheme Runner \
    -configuration "$configuration" \
    -sdk iphonesimulator \
    -destination "generic/platform=iOS Simulator" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO \
    -quiet \
    build

  echo "Built build/ios/${configuration}-iphonesimulator/Runner.app"
  exit 0
fi

exec "$flutter_bin" build ios \
  "$@" \
  --dart-define=lockedEndpoint=true \
  --dart-define="endpoint=$canonical_endpoint"
