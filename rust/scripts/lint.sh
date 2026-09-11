#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
export RUSTFLAGS="-D warnings"

python3 checks/cargo-versions/check.py ..
python3 checks/cargo-versions/test.py
python3 checks/cargo-workspace-dependencies/check.py ..
python3 checks/cargo-workspace-dependencies/test.py
node checks/dependency-boundaries/check.mjs ..
node checks/dependency-boundaries/test.mjs
node checks/lint-exceptions/check.mjs ..
node checks/lint-exceptions/test.mjs
cargo fmt --check
cargo clippy --locked --all-targets --features museum,ente-ml/ml-assets
cargo audit
