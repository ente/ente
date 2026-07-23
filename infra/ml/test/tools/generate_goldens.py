#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from typing import Any, Mapping

from _paths import repo_root, resolve_ml_relative, resolve_repo_relative

from ground_truth.pipeline import GroundTruthPipeline
from ground_truth.schema import dump_results_document


def _git_revision(default: str = "local") -> str:
    try:
        completed = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        )
    except (subprocess.SubprocessError, FileNotFoundError):
        return default
    return completed.stdout.strip() or default


def _validate_source_hash(
    *,
    source_path: Path,
    expected_sha256: str | None,
    file_id: str,
) -> None:
    if not expected_sha256:
        return

    digest = hashlib.sha256()
    with source_path.open("rb") as source_file:
        for chunk in iter(lambda: source_file.read(1024 * 1024), b""):
            digest.update(chunk)
    actual_sha256 = digest.hexdigest()

    if actual_sha256.lower() != expected_sha256.lower():
        raise ValueError(
            f"source hash mismatch for {file_id}: expected {expected_sha256}, got {actual_sha256}"
        )


def _build_results(
    *,
    manifest_items: list[Mapping[str, Any]],
    model_cache_dir: Path,
    model_base_url: str,
    code_revision: str,
):
    pipeline = GroundTruthPipeline(
        model_cache_dir=model_cache_dir,
        model_base_url=model_base_url,
    )

    results = []
    for item in manifest_items:
        file_id = str(item["file_id"])
        source_path = resolve_ml_relative(str(item["source"]))
        if not source_path.exists():
            raise FileNotFoundError(
                f"source file does not exist for '{file_id}': {source_path}"
            )

        _validate_source_hash(
            source_path=source_path,
            expected_sha256=item.get("source_sha256"),
            file_id=file_id,
        )

        result = pipeline.analyze_image(
            file_id=file_id,
            source_path=source_path,
            code_revision=code_revision,
        )
        results.append(result)

    return tuple(results)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate ONNX-backed Python parity results from manifest entries.",
    )
    parser.add_argument(
        "--manifest",
        default="infra/ml/test/ground_truth/manifest.json",
        help="Path to manifest.json file.",
    )
    parser.add_argument(
        "--output-dir",
        default="infra/ml/test/ground_truth/goldens",
        help="Directory where generated parity files are written.",
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
    manifest_path = resolve_repo_relative(args.manifest, repo_root=root)
    output_dir = resolve_repo_relative(args.output_dir, repo_root=root)
    model_cache_dir = resolve_repo_relative(args.model_cache_dir, repo_root=root)

    manifest_payload = json.loads(manifest_path.read_text())
    items = manifest_payload.get("items", [])
    if not items:
        raise ValueError("Manifest has no items")

    code_revision = _git_revision()
    results = _build_results(
        manifest_items=items,
        model_cache_dir=model_cache_dir,
        model_base_url=args.model_base_url,
        code_revision=code_revision,
    )

    output_dir.mkdir(parents=True, exist_ok=True)
    for result in results:
        file_name = result.file_id.replace("/", "__")
        (output_dir / f"{file_name}.json").write_text(
            json.dumps(result.to_dict(), indent=2, sort_keys=True),
        )

    combined_path = output_dir / "results.json"
    combined_path.write_text(dump_results_document(results, platform="python"))

    print(f"Generated {len(results)} ONNX-backed parity result(s) at {output_dir}")
    print(f"Combined output: {combined_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
