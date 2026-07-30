from __future__ import annotations

from dataclasses import dataclass
import hashlib
import os
from pathlib import Path
import sys
import tempfile
from typing import Final
import warnings

import cv2
import numpy as np
import onnxruntime as ort
from PIL import Image, ImageOps
import requests

try:
    from pillow_heif import register_heif_opener

    register_heif_opener()
except Exception:
    # HEIF support is optional at import time; decode errors surface later with context.
    pass


DEFAULT_MODEL_BASE_URL: Final[str] = "https://models.ente.com/"
DEFAULT_PADDING_RGB: Final[tuple[int, int, int]] = (114, 114, 114)
ALLOW_OPENCV_FALLBACK_ENV: Final[str] = "ML_PARITY_ALLOW_OPENCV_DECODE_FALLBACK"
EXIF_ORIENTATION_TAG: Final[int] = 274
ORIENTATION_TRANSPOSE_METHODS: Final[dict[int, Image.Transpose]] = {
    2: Image.Transpose.FLIP_LEFT_RIGHT,
    3: Image.Transpose.ROTATE_180,
    4: Image.Transpose.FLIP_TOP_BOTTOM,
    5: Image.Transpose.TRANSPOSE,
    6: Image.Transpose.ROTATE_270,
    7: Image.Transpose.TRANSVERSE,
    8: Image.Transpose.ROTATE_90,
}
HEIF_EXTENSIONS: Final[frozenset[str]] = frozenset({".heic", ".heif"})


@dataclass(frozen=True)
class ModelArtifact:
    file_name: str
    path: Path
    sha256: str
    etag: str | None


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ensure_model(
    *,
    file_name: str,
    cache_dir: Path,
    base_url: str = DEFAULT_MODEL_BASE_URL,
) -> ModelArtifact:
    cache_dir.mkdir(parents=True, exist_ok=True)
    model_path = cache_dir / file_name

    if model_path.exists() and model_path.stat().st_size > 0:
        return ModelArtifact(
            file_name=file_name,
            path=model_path,
            sha256=_sha256_file(model_path),
            etag=None,
        )

    model_url = f"{base_url.rstrip('/')}/{file_name}"
    with requests.get(model_url, stream=True, timeout=(10, 300)) as response:
        response.raise_for_status()
        etag = response.headers.get("ETag")

        with tempfile.NamedTemporaryFile(
            dir=cache_dir,
            prefix=f"{file_name}.",
            suffix=".tmp",
            delete=False,
        ) as tmp_file:
            tmp_path = Path(tmp_file.name)
            for chunk in response.iter_content(chunk_size=1024 * 1024):
                if chunk:
                    tmp_file.write(chunk)

    tmp_path.replace(model_path)
    return ModelArtifact(
        file_name=file_name,
        path=model_path,
        sha256=_sha256_file(model_path),
        etag=etag,
    )


def create_ort_session(model_path: Path) -> ort.InferenceSession:
    options = ort.SessionOptions()
    options.inter_op_num_threads = 1
    options.intra_op_num_threads = 1
    options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL

    return ort.InferenceSession(
        str(model_path),
        sess_options=options,
        providers=["CPUExecutionProvider"],
    )


def l2_normalize_rows(values: np.ndarray) -> np.ndarray:
    values = np.asarray(values, dtype=np.float32)
    if values.ndim == 1:
        norm = float(np.linalg.norm(values))
        if norm == 0.0:
            raise ValueError("cannot normalize zero vector")
        return values / norm

    norms = np.linalg.norm(values, axis=1, keepdims=True)
    if np.any(norms == 0.0):
        raise ValueError("cannot normalize zero vector rows")
    return values / norms


def _parse_orientation(value: object) -> int | None:
    try:
        orientation = int(value)
    except (TypeError, ValueError):
        return None
    return orientation if 1 <= orientation <= 8 else None


def _iter_bmff_boxes(
    payload: bytes,
    *,
    start: int = 0,
    end: int | None = None,
) -> list[tuple[bytes, int, int, int]]:
    if end is None:
        end = len(payload)
    boxes: list[tuple[bytes, int, int, int]] = []
    cursor = start
    while cursor + 8 <= end:
        box_start = cursor
        size_32 = int.from_bytes(payload[cursor : cursor + 4], byteorder="big")
        box_type = payload[cursor + 4 : cursor + 8]
        cursor += 8

        if size_32 == 1:
            if cursor + 8 > end:
                break
            box_size = int.from_bytes(payload[cursor : cursor + 8], byteorder="big")
            cursor += 8
        elif size_32 == 0:
            box_size = end - box_start
        else:
            box_size = size_32

        if box_type == b"uuid":
            if cursor + 16 > end:
                break
            cursor += 16

        header_size = cursor - box_start
        if box_size < header_size:
            break
        box_end = box_start + box_size
        if box_end > end:
            break

        boxes.append((box_type, box_start, cursor, box_end))
        cursor = box_end
        if box_size == 0:
            break

    return boxes


def _parse_pitm_item_id(meta_payload: bytes, pitm_box: tuple[bytes, int, int, int]) -> int | None:
    _, _, payload_start, payload_end = pitm_box
    if payload_start + 4 > payload_end:
        return None
    version = meta_payload[payload_start]
    cursor = payload_start + 4
    if version == 0:
        if cursor + 2 > payload_end:
            return None
        return int.from_bytes(meta_payload[cursor : cursor + 2], byteorder="big")
    if version == 1:
        if cursor + 4 > payload_end:
            return None
        return int.from_bytes(meta_payload[cursor : cursor + 4], byteorder="big")
    return None


def _parse_ipco_properties(
    payload: bytes,
    ipco_box: tuple[bytes, int, int, int],
) -> list[tuple[bytes, bytes]]:
    _, _, payload_start, payload_end = ipco_box
    properties: list[tuple[bytes, bytes]] = []
    for prop_type, _, prop_payload_start, prop_payload_end in _iter_bmff_boxes(
        payload, start=payload_start, end=payload_end
    ):
        properties.append((prop_type, payload[prop_payload_start:prop_payload_end]))
    return properties


def _parse_primary_item_ipma_associations(
    payload: bytes,
    ipma_box: tuple[bytes, int, int, int],
    *,
    primary_item_id: int,
) -> list[int]:
    _, _, payload_start, payload_end = ipma_box
    if payload_start + 8 > payload_end:
        return []

    version = payload[payload_start]
    flags = int.from_bytes(payload[payload_start + 1 : payload_start + 4], byteorder="big")
    cursor = payload_start + 4
    entry_count = int.from_bytes(payload[cursor : cursor + 4], byteorder="big")
    cursor += 4
    use_extended_property_index = bool(flags & 0x1)

    associations: list[int] = []
    for _ in range(entry_count):
        if version == 0:
            if cursor + 2 > payload_end:
                break
            item_id = int.from_bytes(payload[cursor : cursor + 2], byteorder="big")
            cursor += 2
        elif version == 1:
            if cursor + 4 > payload_end:
                break
            item_id = int.from_bytes(payload[cursor : cursor + 4], byteorder="big")
            cursor += 4
        else:
            break

        if cursor + 1 > payload_end:
            break
        association_count = payload[cursor]
        cursor += 1

        for _ in range(association_count):
            if use_extended_property_index:
                if cursor + 2 > payload_end:
                    break
                value = int.from_bytes(payload[cursor : cursor + 2], byteorder="big")
                cursor += 2
                property_index = value & 0x7FFF
            else:
                if cursor + 1 > payload_end:
                    break
                value = payload[cursor]
                cursor += 1
                property_index = value & 0x7F

            if item_id == primary_item_id and property_index > 0:
                associations.append(property_index)

    return associations


def _heif_primary_item_has_orientation_transform(source_path: Path) -> bool:
    try:
        payload = source_path.read_bytes()
    except Exception:
        return False

    top_level = _iter_bmff_boxes(payload)
    meta_box = next((box for box in top_level if box[0] == b"meta"), None)
    if meta_box is None:
        return False

    _, _, meta_payload_start, meta_payload_end = meta_box
    if meta_payload_start + 4 > meta_payload_end:
        return False
    # Skip full box header (version + flags).
    meta_children_start = meta_payload_start + 4
    meta_children = _iter_bmff_boxes(payload, start=meta_children_start, end=meta_payload_end)

    pitm_box = next((box for box in meta_children if box[0] == b"pitm"), None)
    if pitm_box is None:
        return False
    primary_item_id = _parse_pitm_item_id(payload, pitm_box)
    if primary_item_id is None:
        return False

    iprp_box = next((box for box in meta_children if box[0] == b"iprp"), None)
    if iprp_box is None:
        return False

    _, _, iprp_payload_start, iprp_payload_end = iprp_box
    iprp_children = _iter_bmff_boxes(payload, start=iprp_payload_start, end=iprp_payload_end)

    ipco_properties: list[tuple[bytes, bytes]] = []
    for ipco_box in [box for box in iprp_children if box[0] == b"ipco"]:
        ipco_properties.extend(_parse_ipco_properties(payload, ipco_box))
    if not ipco_properties:
        return False

    associated_property_indexes: list[int] = []
    for ipma_box in [box for box in iprp_children if box[0] == b"ipma"]:
        associated_property_indexes.extend(
            _parse_primary_item_ipma_associations(
                payload,
                ipma_box,
                primary_item_id=primary_item_id,
            )
        )
    if not associated_property_indexes:
        return False

    for property_index in associated_property_indexes:
        if property_index > len(ipco_properties):
            continue
        property_type, property_payload = ipco_properties[property_index - 1]
        if property_type == b"imir":
            return True
        if property_type == b"irot" and property_payload:
            if (property_payload[0] & 0x03) != 0:
                return True

    return False


def _correct_image_orientation(image: Image.Image, *, source_path: Path | None = None) -> Image.Image:
    exif_orientation = _parse_orientation(image.getexif().get(EXIF_ORIENTATION_TAG, 1)) or 1
    # pillow-heif can normalize EXIF orientation to 1 while preserving the original
    # value in `image.info["original_orientation"]`.
    original_orientation = _parse_orientation(image.info.get("original_orientation"))

    corrected = ImageOps.exif_transpose(image)
    if exif_orientation != 1:
        return corrected

    manual_method = ORIENTATION_TRANSPOSE_METHODS.get(original_orientation)
    if manual_method is None:
        return corrected

    if source_path is not None and source_path.suffix.lower() in HEIF_EXTENSIONS:
        # Some HEIF images carry irot/imir primary-item transforms. In those
        # cases, applying original_orientation from pillow-heif can double-rotate.
        if _heif_primary_item_has_orientation_transform(source_path):
            return corrected

    return corrected.transpose(manual_method)


def decode_image_rgb(source_path: Path) -> np.ndarray:
    source_path = source_path.expanduser().resolve()

    try:
        with Image.open(source_path) as image:
            image = _correct_image_orientation(image, source_path=source_path)
            image = image.convert("RGB")
            pixels = np.array(image, dtype=np.uint8, copy=True)
            return np.ascontiguousarray(pixels)
    except Exception as pillow_error:
        fallback_enabled = os.environ.get(ALLOW_OPENCV_FALLBACK_ENV, "").strip().lower() in {
            "1",
            "true",
            "yes",
            "on",
        }
        if not fallback_enabled:
            suffix = source_path.suffix.lower()
            heif_note = (
                " Install pillow-heif to decode HEIC/HEIF files."
                if suffix in {".heic", ".heif"}
                else ""
            )
            raise RuntimeError(
                f"Failed to decode image '{source_path}' with Pillow ({pillow_error}). "
                "OpenCV decode fallback is DISABLED by default because it may diverge from "
                "Pillow EXIF-orientation behavior and can break parity trust."
                f"{heif_note} To force fallback anyway, set {ALLOW_OPENCV_FALLBACK_ENV}=1."
            ) from pillow_error

        warning_message = (
            f"FALLING BACK to OpenCV decode for '{source_path}' after Pillow failure "
            f"({pillow_error}). This can diverge from Pillow EXIF-orientation semantics and "
            "may produce unreliable parity results."
        )
        warnings.warn(warning_message, RuntimeWarning, stacklevel=2)
        print(f"[ml_parity][WARNING] {warning_message}", file=sys.stderr)

        raw = np.fromfile(str(source_path), dtype=np.uint8)
        decoded = cv2.imdecode(raw, cv2.IMREAD_COLOR)
        if decoded is None:
            suffix = source_path.suffix.lower()
            heif_note = (
                " Install pillow-heif to decode HEIC/HEIF files."
                if suffix in {".heic", ".heif"}
                else ""
            )
            raise RuntimeError(
                f"Failed to decode image '{source_path}' with Pillow ({pillow_error})"
                f" and OpenCV.{heif_note}"
            ) from pillow_error

        rgb = cv2.cvtColor(decoded, cv2.COLOR_BGR2RGB)
        return np.ascontiguousarray(rgb)
