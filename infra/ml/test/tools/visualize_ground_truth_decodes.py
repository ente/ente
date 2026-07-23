#!/usr/bin/env python3
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import html
import json
from pathlib import Path
import re
import subprocess
from typing import Any

from PIL import Image

from _paths import ML_DIR, repo_root, resolve_ml_relative, resolve_repo_relative

from ground_truth._runtime import EXIF_ORIENTATION_TAG, decode_image_rgb


def _sanitize_file_name(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]", "_", name)


def _build_html(records: list[dict[str, Any]]) -> str:
    generated_at = datetime.now(timezone.utc).isoformat()
    cards: list[str] = []
    for record in records:
        file_id = html.escape(str(record["file_id"]))
        source = html.escape(str(record["source"]))
        decoded_image = html.escape(str(record["decoded_png_rel"]))
        source_size = html.escape(str(record["source_size"]))
        decoded_size = html.escape(str(record["decoded_size"]))
        exif_orientation = html.escape(str(record["exif_orientation"]))
        original_orientation = html.escape(str(record["original_orientation"]))
        tags = html.escape(", ".join(record["tags"]))

        cards.append(
            (
                "<article class='card'>"
                f"<a href='{decoded_image}' target='_blank' rel='noreferrer'>"
                f"<img src='{decoded_image}' alt='{file_id}' loading='lazy' /></a>"
                f"<h2>{file_id}</h2>"
                "<ul>"
                f"<li><strong>source</strong>: {source}</li>"
                f"<li><strong>source_size</strong>: {source_size}</li>"
                f"<li><strong>decoded_size</strong>: {decoded_size}</li>"
                f"<li><strong>EXIF orientation</strong>: {exif_orientation}</li>"
                f"<li><strong>original_orientation</strong>: {original_orientation}</li>"
                f"<li><strong>tags</strong>: {tags}</li>"
                "</ul>"
                "</article>"
            )
        )

    cards_markup = "\n".join(cards)
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>ML Ground Truth Decode Preview</title>
  <style>
    :root {{
      color-scheme: light;
      --bg: #f7f8fa;
      --fg: #1d232f;
      --card: #ffffff;
      --border: #d9dde6;
      --muted: #4f5d75;
      --link: #0d66d0;
    }}
    body {{
      margin: 0;
      padding: 24px;
      background: radial-gradient(circle at top left, #fefcf6 0%, var(--bg) 45%);
      color: var(--fg);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
    }}
    h1 {{
      margin: 0 0 8px;
      font-size: 28px;
    }}
    p.meta {{
      margin: 0 0 20px;
      color: var(--muted);
      font-size: 14px;
    }}
    .grid {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
      gap: 16px;
    }}
    .card {{
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 12px;
      box-shadow: 0 1px 6px rgba(17, 24, 39, 0.05);
    }}
    img {{
      width: 100%;
      max-height: 280px;
      object-fit: contain;
      border: 1px solid var(--border);
      border-radius: 8px;
      background: #111;
    }}
    h2 {{
      margin: 10px 0 8px;
      font-size: 16px;
      line-height: 1.3;
      word-break: break-word;
    }}
    ul {{
      margin: 0;
      padding-left: 18px;
      color: var(--muted);
      font-size: 13px;
      line-height: 1.35;
    }}
    a {{
      color: var(--link);
    }}
  </style>
</head>
<body>
  <h1>ML Ground Truth Decode Preview</h1>
  <p class="meta">
    Generated: {html.escape(generated_at)} | Count: {len(records)} | Decoder:
    ground_truth._runtime.decode_image_rgb
  </p>
  <div class="grid">
    {cards_markup}
  </div>
</body>
</html>
"""


def _decode_all(
    *,
    manifest_items: list[dict[str, Any]],
    output_dir: Path,
) -> list[dict[str, Any]]:
    decoded_dir = output_dir / "decoded"
    decoded_dir.mkdir(parents=True, exist_ok=True)

    records: list[dict[str, Any]] = []
    for index, item in enumerate(manifest_items, start=1):
        file_id = str(item.get("file_id", ""))
        source_value = str(item.get("source", ""))
        source_path = resolve_ml_relative(source_value)
        if not source_path.exists():
            raise FileNotFoundError(
                f"Source file missing for manifest item '{file_id}': {source_path}"
            )

        with Image.open(source_path) as source_img:
            source_size = f"{source_img.width}x{source_img.height}"
            exif_orientation = source_img.getexif().get(EXIF_ORIENTATION_TAG)
            original_orientation = source_img.info.get("original_orientation")

        decoded = decode_image_rgb(source_path)
        decoded_img = Image.fromarray(decoded, mode="RGB")
        decoded_size = f"{decoded_img.width}x{decoded_img.height}"

        file_stem = _sanitize_file_name(file_id.replace("/", "__"))
        if not file_stem:
            file_stem = f"item_{index:03d}"
        output_png = decoded_dir / f"{index:03d}_{file_stem}.png"
        decoded_img.save(output_png, format="PNG")

        records.append(
            {
                "file_id": file_id,
                "source": str(source_path.relative_to(ML_DIR)),
                "source_size": source_size,
                "decoded_size": decoded_size,
                "decoded_png_rel": str(output_png.relative_to(output_dir)),
                "exif_orientation": exif_orientation,
                "original_orientation": original_orientation,
                "tags": list(item.get("tags") or []),
            }
        )

    return records


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Decode all ML parity fixtures via ground_truth._runtime.decode_image_rgb "
            "and generate an HTML gallery for visual inspection."
        )
    )
    parser.add_argument(
        "--manifest",
        default="infra/ml/test/ground_truth/manifest.json",
        help="Path to parity manifest.json.",
    )
    parser.add_argument(
        "--output-dir",
        default="infra/ml/test/out/parity/python_decode_preview",
        help="Directory where decoded PNGs and index.html are written.",
    )
    parser.add_argument(
        "--open",
        action="store_true",
        help="Open generated index.html in the default browser.",
    )
    args = parser.parse_args()

    root = repo_root()
    manifest_path = resolve_repo_relative(args.manifest, repo_root=root)
    output_dir = resolve_repo_relative(args.output_dir, repo_root=root)
    output_dir.mkdir(parents=True, exist_ok=True)

    manifest_payload = json.loads(manifest_path.read_text())
    items = list(manifest_payload.get("items") or [])
    if not items:
        raise ValueError(f"No manifest items found in {manifest_path}")

    records = _decode_all(
        manifest_items=items,
        output_dir=output_dir,
    )

    index_path = output_dir / "index.html"
    index_path.write_text(_build_html(records), encoding="utf-8")

    if args.open:
        subprocess.run(["open", str(index_path)], check=False)

    print(f"Decoded {len(records)} fixture image(s).")
    print(f"Gallery: {index_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
