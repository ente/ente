#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from typing import Any, Mapping

from _paths import repo_root, resolve_repo_relative

from ground_truth.pipeline import GroundTruthPipeline
from ground_truth.schema import dump_results_document


DEFAULT_ASSET_LOCK = "infra/ml/test/ml_indexing/assets.json"

# Keep the golden byte-stable across regenerations: embedding the generating
# commit would change the file's SHA-256 even when results are identical.
GOLDEN_CODE_REVISION = "ml-indexing-golden"


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source_file:
        for chunk in iter(lambda: source_file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _validate_sha256(path: Path, expected_sha256: str, *, label: str) -> None:
    actual_sha256 = _sha256(path)
    if actual_sha256.lower() != expected_sha256.lower():
        raise ValueError(
            f"{label} hash mismatch at {path}: expected {expected_sha256}, got {actual_sha256}"
        )


def _default_assets_repo_dir(root: Path) -> Path:
    env_path = os.environ.get("ENTE_ML_ASSETS_REPO_DIR")
    if env_path:
        return Path(env_path)
    return root.parent / "test-fixtures" / "ml" / "indexing" / "v1"


def _file_id(path_value: str) -> str:
    file_name = Path(path_value).name
    if not file_name:
        raise ValueError(f"Could not derive file_id from manifest path: {path_value}")
    return file_name


def _build_results(
    *,
    assets_repo_dir: Path,
    manifest: Mapping[str, Any],
    model_cache_dir: Path,
    model_base_url: str,
    code_revision: str,
):
    pipeline = GroundTruthPipeline(
        model_cache_dir=model_cache_dir,
        model_base_url=model_base_url,
    )

    results = []
    for item in manifest.get("files", []):
        path_value = str(item["path"])
        source_path = assets_repo_dir / path_value
        file_id = _file_id(path_value)
        if not source_path.exists():
            raise FileNotFoundError(
                f"source file does not exist for '{file_id}': {source_path}"
            )

        expected_sha256 = item.get("sha256")
        if expected_sha256:
            _validate_sha256(
                source_path,
                str(expected_sha256),
                label=f"source fixture {file_id}",
            )

        results.append(
            pipeline.analyze_image(
                file_id=file_id,
                source_path=source_path,
                code_revision=code_revision,
            )
        )

    if not results:
        raise ValueError("Manifest has no files")
    return tuple(results)


def _dump_deterministic_results(results) -> str:
    payload = json.loads(dump_results_document(results, platform="python"))
    for result in payload["results"]:
        result["runner_metadata"].pop("timing_ms", None)
    return json.dumps(payload, indent=2, sort_keys=True)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate the Python golden JSON used by the Rust ML indexing Cargo test.",
    )
    parser.add_argument(
        "--asset-lock",
        default=DEFAULT_ASSET_LOCK,
        help="Path to infra/ml/test/ml_indexing/assets.json.",
    )
    parser.add_argument(
        "--assets-repo-dir",
        default=None,
        help=(
            "Path to the external fixture dataset root "
            "(for example test-fixtures/ml/indexing/v1). Defaults to "
            "ENTE_ML_ASSETS_REPO_DIR or ../test-fixtures/ml/indexing/v1."
        ),
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Output JSON path. Defaults to the python_golden.path from the asset lock.",
    )
    parser.add_argument(
        "--model-cache-dir",
        default="infra/ml/test/.cache/onnx_models",
        help="Directory where ONNX models are cached locally.",
    )
    parser.add_argument(
        "--model-base-url",
        default="https://models.ente.io/",
        help="Base URL for downloading ONNX model files.",
    )
    args = parser.parse_args()

    root = repo_root()
    asset_lock_path = resolve_repo_relative(args.asset_lock, repo_root=root)
    asset_lock = json.loads(asset_lock_path.read_text())

    assets_repo_dir = (
        Path(args.assets_repo_dir)
        if args.assets_repo_dir
        else _default_assets_repo_dir(root)
    )
    manifest_path = assets_repo_dir / asset_lock["manifest"]["path"]
    manifest = json.loads(manifest_path.read_text())
    _validate_sha256(
        manifest_path,
        str(asset_lock["manifest"]["sha256"]),
        label="fixture manifest",
    )

    output_path = (
        Path(args.output)
        if args.output
        else assets_repo_dir / asset_lock["python_golden"]["path"]
    )
    model_cache_dir = resolve_repo_relative(args.model_cache_dir, repo_root=root)

    results = _build_results(
        assets_repo_dir=assets_repo_dir,
        manifest=manifest,
        model_cache_dir=model_cache_dir,
        model_base_url=args.model_base_url,
        code_revision=GOLDEN_CODE_REVISION,
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(_dump_deterministic_results(results))
    sha256 = _sha256(output_path)
    expected_sha256 = str(asset_lock["python_golden"]["sha256"]).lower()
    print(f"Generated {len(results)} Python ML indexing result(s): {output_path}")
    print(f"SHA-256: {sha256}")
    if sha256 != expected_sha256:
        print(
            "NOTE: generated SHA-256 differs from the asset lock. "
            "Update infra/ml/test/ml_indexing/assets.json if this drift is intentional."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
