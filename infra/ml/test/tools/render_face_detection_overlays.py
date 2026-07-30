#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
from typing import Any, Mapping

from PIL import Image, ImageDraw, ImageFont

from _paths import ML_DIR, repo_root, resolve_repo_relative

from ground_truth._runtime import decode_image_rgb


_PALETTE = (
    (230, 25, 75),
    (60, 180, 75),
    (0, 130, 200),
    (245, 130, 48),
    (145, 30, 180),
    (70, 240, 240),
    (240, 50, 230),
    (210, 245, 60),
    (250, 190, 190),
    (0, 128, 128),
    (170, 110, 40),
    (128, 0, 0),
)


def _resolve_source_path(source_value: str, *, repo_root: Path) -> Path:
    source_path = Path(source_value)
    if source_path.is_absolute():
        return source_path

    ml_relative = ML_DIR / source_path
    if ml_relative.exists():
        return ml_relative

    return repo_root / source_path


def _safe_output_name(file_id: str) -> str:
    sanitized = re.sub(r"[^0-9A-Za-z._-]", "_", file_id)
    if sanitized:
        return sanitized
    return "file"


def _load_manifest_sources(
    *,
    manifest_path: Path,
    repo_root: Path,
) -> dict[str, Path]:
    payload = json.loads(manifest_path.read_text())
    items = payload.get("items", [])
    if not isinstance(items, list):
        raise ValueError("manifest `items` must be a list")

    sources_by_id: dict[str, Path] = {}
    for item in items:
        if not isinstance(item, Mapping):
            continue
        file_id = item.get("file_id")
        source = item.get("source")
        if not isinstance(file_id, str) or not isinstance(source, str):
            continue
        sources_by_id[file_id] = _resolve_source_path(source, repo_root=repo_root)
    return sources_by_id


def _draw_label(
    *,
    image: Image.Image,
    draw: ImageDraw.ImageDraw,
    text: str,
    position: tuple[float, float],
    color: tuple[int, int, int],
    font: ImageFont.ImageFont,
) -> None:
    x, y = position
    left, top, right, bottom = draw.textbbox((x, y), text, font=font)
    padding = 2
    draw.rectangle(
        (
            left - padding,
            top - padding,
            right + padding,
            bottom + padding,
        ),
        fill=(0, 0, 0, 180),
    )
    draw.text((x, y), text, fill=(*color, 255), font=font)


def _render_detections(
    *,
    image_rgb: Any,
    file_id: str,
    platform: str,
    faces: list[Mapping[str, Any]],
    min_score: float,
) -> Image.Image:
    image = Image.fromarray(image_rgb, mode="RGB").convert("RGBA")
    draw = ImageDraw.Draw(image, mode="RGBA")
    width, height = image.size
    line_width = max(1, round(min(width, height) * 0.003))
    point_radius = max(2, round(min(width, height) * 0.004))
    font = ImageFont.load_default()

    header = (
        f"{platform}  |  {file_id}  |  faces(score >= {min_score:.2f})={len(faces)}"
    )
    _draw_label(
        image=image,
        draw=draw,
        text=header,
        position=(8, 8),
        color=(255, 255, 255),
        font=font,
    )

    for index, face in enumerate(faces):
        color = _PALETTE[index % len(_PALETTE)]
        box_values = face.get("box")
        if not isinstance(box_values, list) or len(box_values) != 4:
            continue

        x_norm, y_norm, w_norm, h_norm = (
            float(box_values[0]),
            float(box_values[1]),
            float(box_values[2]),
            float(box_values[3]),
        )
        x1 = x_norm * width
        y1 = y_norm * height
        x2 = (x_norm + w_norm) * width
        y2 = (y_norm + h_norm) * height

        draw.rectangle((x1, y1, x2, y2), outline=(*color, 255), width=line_width)

        score_value = face.get("score")
        if isinstance(score_value, (int, float)):
            label = f"#{index} score={float(score_value):.3f}"
        else:
            label = f"#{index}"
        label_x = max(0.0, min(x1 + 3.0, width - 1.0))
        label_y = max(0.0, y1 - 16.0)
        _draw_label(
            image=image,
            draw=draw,
            text=label,
            position=(label_x, label_y),
            color=color,
            font=font,
        )

        landmarks = face.get("landmarks")
        if not isinstance(landmarks, list):
            continue
        for point in landmarks:
            if not isinstance(point, list) or len(point) != 2:
                continue
            px = float(point[0]) * width
            py = float(point[1]) * height
            draw.ellipse(
                (
                    px - point_radius,
                    py - point_radius,
                    px + point_radius,
                    py + point_radius,
                ),
                fill=(*color, 220),
                outline=(0, 0, 0, 255),
            )

    return image.convert("RGB")


def _discover_platforms(parity_dir: Path) -> list[str]:
    platforms = []
    if not parity_dir.exists():
        return platforms

    for child in sorted(parity_dir.iterdir()):
        if not child.is_dir():
            continue
        if (child / "results.json").exists():
            platforms.append(child.name)
    return platforms


def _load_platform_results(results_path: Path) -> list[Mapping[str, Any]]:
    payload = json.loads(results_path.read_text())
    results = payload.get("results")
    if not isinstance(results, list):
        raise ValueError(f"{results_path} must contain `results: []`")
    typed_results: list[Mapping[str, Any]] = []
    for item in results:
        if isinstance(item, Mapping):
            typed_results.append(item)
    return typed_results


def _iter_file_results(
    results: list[Mapping[str, Any]],
    *,
    only_file_ids: set[str] | None,
    min_score: float,
) -> list[tuple[str, list[Mapping[str, Any]]]]:
    selected: list[tuple[str, list[Mapping[str, Any]]]] = []
    for item in results:
        file_id = item.get("file_id")
        faces = item.get("faces")
        if not isinstance(file_id, str):
            continue
        if only_file_ids is not None and file_id not in only_file_ids:
            continue
        if not isinstance(faces, list):
            continue
        typed_faces = []
        for face in faces:
            if not isinstance(face, Mapping):
                continue
            score_value = face.get("score")
            if not isinstance(score_value, (int, float)):
                continue
            if float(score_value) < min_score:
                continue
            typed_faces.append(face)
        selected.append((file_id, typed_faces))
    return selected


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Render annotated face detection overlays for parity results. "
            "Writes files to out/parity/detections/<platform>/."
        ),
    )
    parser.add_argument(
        "--manifest",
        default="infra/ml/test/ground_truth/manifest.json",
        help="Path to manifest.json.",
    )
    parser.add_argument(
        "--parity-dir",
        default="infra/ml/test/out/parity",
        help="Parity output directory containing <platform>/results.json.",
    )
    parser.add_argument(
        "--output-dir",
        help=(
            "Output directory for annotated images. "
            "Defaults to <parity-dir>/detections."
        ),
    )
    parser.add_argument(
        "--platform",
        action="append",
        default=[],
        help="Platform name to render (repeatable). Defaults to all detected platforms.",
    )
    parser.add_argument(
        "--file-id",
        action="append",
        default=[],
        help="Only render specific file_id values (repeatable).",
    )
    parser.add_argument(
        "--min-score",
        type=float,
        default=0.8,
        help="Minimum detection score required to draw a face overlay (default: 0.8).",
    )
    args = parser.parse_args()

    root = repo_root()
    manifest_path = resolve_repo_relative(args.manifest, repo_root=root)
    parity_dir = resolve_repo_relative(args.parity_dir, repo_root=root)
    output_dir = (
        resolve_repo_relative(args.output_dir, repo_root=root)
        if args.output_dir
        else parity_dir / "detections"
    )

    sources_by_id = _load_manifest_sources(
        manifest_path=manifest_path,
        repo_root=root,
    )

    requested_platforms = args.platform or _discover_platforms(parity_dir)
    if not requested_platforms:
        raise ValueError(f"No platform results discovered in {parity_dir}")

    only_file_ids = set(args.file_id) if args.file_id else None

    total_rendered = 0
    total_skipped = 0
    for platform in requested_platforms:
        results_path = parity_dir / platform / "results.json"
        if not results_path.exists():
            print(f"[skip] {platform}: missing {results_path}")
            total_skipped += 1
            continue

        platform_results = _load_platform_results(results_path)
        file_results = _iter_file_results(
            platform_results,
            only_file_ids=only_file_ids,
            min_score=args.min_score,
        )
        if not file_results:
            print(f"[skip] {platform}: no matching results")
            total_skipped += 1
            continue

        platform_output_dir = output_dir / platform
        platform_output_dir.mkdir(parents=True, exist_ok=True)

        rendered_for_platform = 0
        for file_id, faces in file_results:
            source_path = sources_by_id.get(file_id)
            if source_path is None:
                print(f"[skip] {platform}/{file_id}: no source path in manifest")
                total_skipped += 1
                continue
            if not source_path.exists():
                print(f"[skip] {platform}/{file_id}: source file missing at {source_path}")
                total_skipped += 1
                continue

            try:
                image_rgb = decode_image_rgb(source_path)
            except Exception as exc:  # noqa: BLE001
                print(f"[skip] {platform}/{file_id}: failed to decode source ({exc})")
                total_skipped += 1
                continue

            rendered = _render_detections(
                image_rgb=image_rgb,
                file_id=file_id,
                platform=platform,
                faces=faces,
                min_score=args.min_score,
            )
            output_path = platform_output_dir / f"{_safe_output_name(file_id)}.png"
            rendered.save(output_path)
            rendered_for_platform += 1
            total_rendered += 1

        print(
            f"[ok] {platform}: rendered {rendered_for_platform} file(s) -> {platform_output_dir}"
        )

    print(f"Done. Rendered {total_rendered} file(s), skipped {total_skipped}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
