#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

../../packages/install_source/scripts/prepare_fdroid_source.sh
