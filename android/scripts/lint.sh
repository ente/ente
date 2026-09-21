#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

python3 checks/gradle-order/check.py .
python3 checks/gradle-order/test.py
node checks/lint-exceptions/check.mjs
node checks/lint-exceptions/test.mjs

(cd ../rust && cargo codegen native)
./gradlew --build-cache :lint
