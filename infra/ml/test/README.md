# ML Indexing Parity Test Suite

This directory contains the ML indexing parity framework for Android, iOS, desktop, and Python ground truth.

## Layout

- `ground_truth/`: schema, manifest, and ONNX-backed Python pipeline.
- `comparator/`: parity comparison engine and threshold checks.
- `tools/`: suite orchestration and CLI entrypoints.
- `tests/`: pytest coverage for schema/comparator behavior.
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
- `--fail-on-missing-platform`
- `--fail-on-platform-runner-error`
- `--allow-empty-comparison`
- `--output-dir <path>`
- `--verbose` (stream full runner/comparator logs to terminal)
- `--render-detection-overlays` (generate annotated detection images under `out/parity/detections/<platform>/`; includes selected platforms plus `python` ground truth)
- `--reuse-mobile-application-binary` (reuse an existing built mobile binary when available; useful for repeated local parity runs without code changes)
- `--no-parallel-mobile-runners` (force sequential android/ios runner execution)
- `--include-pairwise` (also compare non-ground-truth platform pairs such as `android -> ios`)

Outputs go to `infra/ml/test/out/parity/` by default, including:

- `comparison_report.json` (machine-readable comparison output)
- `parity_report.html` (readable HTML report with per-file metrics for both pass and fail files)

`run_ml_parity_tests.sh` compares each available platform against Python ground truth (`python -> <platform>`); non-ground-truth pairwise comparisons are excluded by default.

Optional mobile reuse env vars:

- `ML_PARITY_ANDROID_BUILD_MODE` (`profile` by default; set `debug` or `release` explicitly if needed)
- `ML_PARITY_ANDROID_EXISTING_APP_URL`, `ML_PARITY_IOS_EXISTING_APP_URL` (reuse a currently running app via VM service URL)
- `ML_PARITY_ANDROID_APPLICATION_BINARY`, `ML_PARITY_IOS_APPLICATION_BINARY` (explicit prebuilt binary path for `flutter drive --use-application-binary`)

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

Goldens are runtime artifacts and are not committed.

Use this process when corpus/threshold/model behavior changes intentionally:

1. Update corpus metadata in `infra/ml/test/ground_truth/manifest.json`; thresholds live in `ThresholdConfig` in `infra/ml/test/comparator/compare.py`.
2. Regenerate and compare with a real run:

```sh
bash infra/ml/test/run_ml_parity_tests.sh --platforms all --output-dir infra/ml/test/out/parity
```

3. Review `infra/ml/test/out/parity/parity_report.html`, `comparison_report.json`, and per-platform `results.json` files.
4. If drift is expected, adjust thresholds/known exceptions and rerun until stable.
5. Commit code/config/docs updates only; do not commit generated `out/`, `test_data/`, or cache artifacts.
