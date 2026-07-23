# ML Indexing Parity Test Suite

This directory contains the ML indexing parity framework for Android, iOS, desktop, and Python ground truth.

## Layout

- `ground_truth/`: schema, manifest, and ONNX-backed Python pipeline.
- `comparator/`: parity comparison engine and threshold checks.
- `tools/`: suite orchestration and CLI entrypoints.
- `ml_indexing/`: asset lock for the Cargo-based Rust ML indexing test.
- Runtime-only artifacts (gitignored): `test_data/`, `out/`, `.cache/`.

## Prerequisites

- Python + `uv`
- Node/npm (desktop parity)
- Flutter SDK (Android/iOS parity)
- Android emulator/device and iOS simulator/device when running mobile parity

## Local Run (One Command)

```sh
bash infra/ml/test/run_ml_parity_tests.sh
```

Common flags:

- `--platforms all|desktop|android|ios`
- `--output-dir <path>`
- `--verbose` (stream full runner/comparator logs to terminal)
- `--render-detection-overlays` (generate annotated detection images under `out/parity/detections/<platform>/`; includes selected platforms plus `python` ground truth)
- `--reuse-mobile-application-binary` (reuse an existing built mobile binary when available; useful for repeated local parity runs without code changes)
- `--no-parallel-mobile-runners` (force sequential android/ios runner execution)

Outputs go to `infra/ml/test/out/parity/` by default, including:

- `comparison_report.json` (machine-readable comparison output)
- `parity_report.html` (readable HTML report with per-file metrics for both pass and fail files)

`run_ml_parity_tests.sh` compares each available platform against Python ground truth (`python -> <platform>`).

Optional mobile reuse env vars:

- `ML_PARITY_ANDROID_BUILD_MODE` (`profile` by default; set `debug` or `release` explicitly if needed)
- `ML_PARITY_ANDROID_EXISTING_APP_URL`, `ML_PARITY_IOS_EXISTING_APP_URL` (reuse a currently running app via VM service URL)
- `ML_PARITY_ANDROID_APPLICATION_BINARY`, `ML_PARITY_IOS_APPLICATION_BINARY` (explicit prebuilt binary path for `flutter drive --use-application-binary`)

## Rust ML Indexing Cargo Test

The Rust-only ML indexing test lives at `rust/crates/photos/tests/ml_indexing.rs`.
It is gated by the `ente-photos/ml-assets` Cargo feature so ordinary local
`cargo test --workspace` runs do not download ML assets or execute indexing.

From `rust/`:

```sh
cargo test -p ente-photos --test ml_indexing --features ml-assets -- --nocapture
```

By default the test downloads the external fixture manifest, fixture images,
Python golden JSON, ONNX Runtime dynamic library, and ONNX models into
`rust/.cache/`, with SHA-256 verification for every asset.

Optional env vars:

- `ENTE_ML_INDEXING_PRINT_STATS=1`: print a per-metric comparison summary (count, max observed value, threshold) even when the test passes; on failure the summary is always appended to the failure message.

`infra/ml/test/ml_indexing/assets.json` locks the external manifest, Python
golden, model URLs, expected unsupported decode files, and thresholds. The
current RAW/CR2 fixture is expected to fail Rust decode; the test verifies that
failure path and skips golden comparison for that file until RAW support lands.

## Detection Overlay Visualizer

Render face detection overlays (box + score + landmarks) for each platform output:

```sh
uv run --project infra/ml \
  python infra/ml/test/tools/render_face_detection_overlays.py \
  --parity-dir infra/ml/test/out/parity \
  --platform ios \
  --platform android
```

By default this writes annotated images to:

- `infra/ml/test/out/parity/detections/<platform>/*.png`

Useful optional filters:

- `--file-id <fixture_name>` (repeatable)
- `--output-dir <custom_dir>`

## Ground-Truth Decode Visualizer

Render the exact Python ground-truth decode output (including EXIF orientation handling) for every manifest fixture, then review the generated gallery.

```sh
uv run --project infra/ml \
  python infra/ml/test/tools/visualize_ground_truth_decodes.py \
  --manifest infra/ml/test/ground_truth/manifest.json \
  --output-dir infra/ml/test/out/parity/python_decode_preview \
  --open
```

This script calls `ground_truth._runtime.decode_image_rgb` directly, so it tracks decode/orientation behavior changes in the Python reference pipeline.

Outputs:

- `infra/ml/test/out/parity/python_decode_preview/index.html`
- `infra/ml/test/out/parity/python_decode_preview/decoded/*.png`

## Golden Update / Maintenance

Goldens under this monorepo's `out/`, `test_data/`, and cache directories are
runtime artifacts and are not committed. The Rust ML indexing golden JSON is
different: it belongs in the external `test-fixtures` repo next to the image
corpus, because it describes that corpus.

Use this process when corpus/threshold/model behavior changes intentionally:

1. Update corpus metadata in the external fixture repo. Rust ML indexing thresholds live in `infra/ml/test/ml_indexing/assets.json`; shell-suite thresholds live in `ThresholdConfig` in `infra/ml/test/comparator/compare.py`.
2. Regenerate and compare with a real run:

```sh
bash infra/ml/test/run_ml_parity_tests.sh --platforms all --output-dir infra/ml/test/out/parity
```

3. Regenerate the Rust ML indexing golden in the external fixture repo:

```sh
uv run --project infra/ml \
  python infra/ml/test/tools/generate_ml_indexing_golden.py \
  --assets-repo-dir /path/to/test-fixtures/ml/indexing/v1
```

4. Review `infra/ml/test/out/parity/parity_report.html`, `comparison_report.json`, per-platform `results.json` files, and the generated external `goldens/python/results.json`.
5. If drift is expected, update thresholds/known exceptions and the Python golden SHA in `infra/ml/test/ml_indexing/assets.json`, then rerun until stable.
6. Commit code/config/docs updates in this repo; commit the corpus manifest and Python golden JSON in the external fixture repo. Do not commit generated `out/`, `test_data/`, or cache artifacts in this repo.
