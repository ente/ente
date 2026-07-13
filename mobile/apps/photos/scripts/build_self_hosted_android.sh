#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly app_dir="$(cd "$script_dir/.." && pwd)"
readonly flutter_bin="${FLUTTER_BIN:-flutter}"
readonly dart_bin="${DART_BIN:-dart}"
readonly self_hosted_flavor="selfhosted"

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
    --flavor | --flavor=*)
      echo "The locked build wrapper owns the Android flavor; remove '$argument'." >&2
      exit 64
      ;;
  esac
done

echo "Building locked Ente Photos for $canonical_endpoint"

"$flutter_bin" build apk \
  "$@" \
  --flavor "$self_hosted_flavor" \
  --dart-define=lockedEndpoint=true \
  --dart-define="endpoint=$canonical_endpoint"
