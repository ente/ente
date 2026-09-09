#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

node .github/checks/documentation-comments/check.mjs
node .github/checks/documentation-comments/test.mjs
ruby .github/checks/workflow-paths/check.rb
ruby .github/checks/workflow-paths/test.rb
ruby .github/checks/wasm-ci-paths/check.rb
ruby .github/checks/wasm-ci-paths/test.rb
