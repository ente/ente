# Infra ML Workspace

`infra/ml` is split into two focused areas:

- `playground/`: exploratory ML notebooks, model prep experiments, and sample assets.
- `test/`: ML indexing parity framework (Python ground truth, desktop/mobile runners, comparator, and CI entrypoints).

Parity Python project configuration stays at this root:

- `pyproject.toml`
- `uv.lock`
- `.python-version`
- `.gitignore`

Playground notebooks use their own Python project:

- `infra/ml/playground/pyproject.toml`
- `infra/ml/playground/uv.lock`

ONNX Runtime 1.27 no longer publishes Apple x86_64 binaries. On macOS, the
parity and playground Python environments therefore require Apple Silicon.

Use the directory-specific READMEs for day-to-day work:

- `infra/ml/playground/README.md`
- `infra/ml/test/README.md`
