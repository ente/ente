#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

node .github/checks/format-js/check.mjs
node --test .github/checks/format-js/test.mjs
node .github/checks/documentation-comments/check.mjs
node .github/checks/documentation-comments/test.mjs
ruby .github/checks/workflow-paths/check.rb
ruby .github/checks/workflow-paths/test.rb
ruby .github/checks/workflow-security/test.rb
node --test .github/checks/pr-approval/test.mjs
node .github/checks/rust-ci-paths/check.mjs
node --test .github/checks/rust-ci-paths/test.mjs
node --test .github/scripts/ci/test.mjs
