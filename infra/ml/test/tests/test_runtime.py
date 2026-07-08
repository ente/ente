from __future__ import annotations

import numpy as np
from PIL import Image
from pathlib import Path

import ground_truth._runtime as runtime


def _sample_image() -> Image.Image:
    # Width != height so orientation swaps are easy to assert.
    pixels = np.array(
        [
            [[255, 0, 0], [0, 255, 0], [0, 0, 255]],
            [[10, 20, 30], [40, 50, 60], [70, 80, 90]],
        ],
        dtype=np.uint8,
    )
    return Image.fromarray(pixels, mode="RGB")


def test_correct_image_orientation_applies_standard_exif_orientation() -> None:
    image = _sample_image()
    exif = image.getexif()
    exif[274] = 6
    image.info["exif"] = exif.tobytes()

    corrected = runtime._correct_image_orientation(image)

    assert corrected.size == (2, 3)


def test_correct_image_orientation_uses_original_orientation_when_exif_is_normalized() -> None:
    image = _sample_image()
    exif = image.getexif()
    exif[274] = 1
    image.info["exif"] = exif.tobytes()
    image.info["original_orientation"] = 6

    corrected = runtime._correct_image_orientation(image)

    assert corrected.size == (2, 3)


def test_correct_image_orientation_leaves_image_unchanged_without_orientation_metadata() -> None:
    image = _sample_image()

    corrected = runtime._correct_image_orientation(image)

    assert corrected.size == image.size


def test_correct_image_orientation_skips_original_orientation_for_heif_with_primary_transform(
    monkeypatch,
) -> None:
    image = _sample_image()
    exif = image.getexif()
    exif[274] = 1
    image.info["exif"] = exif.tobytes()
    image.info["original_orientation"] = 6

    monkeypatch.setattr(
        runtime,
        "_heif_primary_item_has_orientation_transform",
        lambda _: True,
    )

    corrected = runtime._correct_image_orientation(
        image,
        source_path=Path("/tmp/example.HEIC"),
    )

    assert corrected.size == image.size
