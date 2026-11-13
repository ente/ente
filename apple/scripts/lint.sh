#!/bin/bash
set -eo pipefail

cd "$(dirname "$0")/.."

node checks/lint-exceptions/check.mjs
node checks/lint-exceptions/test.mjs

swift format lint --recursive --strict .
swift package plugin --allow-writing-to-package-directory swiftlint lint --strict
