#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

ruby -w -c scripts/lib/upstream_sync.rb
ruby -w -c scripts/upstream_sync.rb
ruby -w -c scripts/test/upstream_sync_test.rb
ruby -w -c scripts/test/upstream_sync_integration_test.rb
ruby -w -c scripts/test/upstream_sync_workflow_test.rb
ruby -w -c .github/scripts/check_workflow_security.rb
ruby -w -c .github/scripts/check_workflow_security_test.rb

ruby scripts/test/upstream_sync_test.rb
ruby scripts/test/upstream_sync_integration_test.rb
ruby scripts/test/upstream_sync_workflow_test.rb
node --test .github/scripts/upstream-sync-issue.test.cjs
ruby .github/scripts/check_workflow_security.rb
ruby .github/scripts/check_workflow_security_test.rb

git diff --check

echo "Upstream synchronization tests passed."
