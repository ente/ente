from __future__ import annotations

from time import perf_counter

import cv2
import numpy as np

from ._runtime import DEFAULT_PADDING_RGB
from .face_detection import FaceDetection


MOBILEFACENET_INPUT_SIZE = 112
MOBILEFACENET_IDEAL_LANDMARKS = np.array(
    [
        [38.2946, 51.6963],
        [73.5318, 51.5014],
        [56.0252, 71.7366],
        [41.5493, 92.3655],
        [70.7299, 92.2041],
    ],
    dtype=np.float32,
)


def _landmarks_to_absolute(
    landmarks: tuple[tuple[float, float], ...],
    *,
    image_width: int,
    image_height: int,
) -> np.ndarray:
    return np.array(
        [[x * image_width, y * image_height] for x, y in landmarks],
        dtype=np.float32,
    )


def _estimate_similarity_transform(src_landmarks: np.ndarray) -> np.ndarray:
    matrix, _ = cv2.estimateAffinePartial2D(
        src_landmarks,
        MOBILEFACENET_IDEAL_LANDMARKS,
        method=cv2.LMEDS,
    )
    if matrix is None:
        raise ValueError("OpenCV could not estimate a similarity transform for face landmarks")
    return matrix.astype(np.float32)


def align_faces_for_mobilefacenet(
    image_rgb: np.ndarray,
    detections: tuple[FaceDetection, ...],
) -> np.ndarray:
    if not detections:
        return np.empty((0, MOBILEFACENET_INPUT_SIZE, MOBILEFACENET_INPUT_SIZE, 3), dtype=np.float32)

    image_height, image_width = image_rgb.shape[:2]
    aligned_faces: list[np.ndarray] = []

    for detection in detections:
        src_landmarks = _landmarks_to_absolute(
            detection.landmarks,
            image_width=image_width,
            image_height=image_height,
        )
        transform = _estimate_similarity_transform(src_landmarks)
        aligned = cv2.warpAffine(
            image_rgb,
            transform,
            (MOBILEFACENET_INPUT_SIZE, MOBILEFACENET_INPUT_SIZE),
            flags=cv2.INTER_CUBIC,
            borderMode=cv2.BORDER_CONSTANT,
            borderValue=DEFAULT_PADDING_RGB,
        )
        normalized = aligned.astype(np.float32) / 127.5 - 1.0
        aligned_faces.append(normalized)

    return np.stack(aligned_faces, axis=0)


class FaceAligner:
    def align(
        self,
        image_rgb: np.ndarray,
        detections: tuple[FaceDetection, ...],
    ) -> tuple[np.ndarray, dict[str, float]]:
        start = perf_counter()
        aligned_faces = align_faces_for_mobilefacenet(image_rgb, detections)
        elapsed_ms = (perf_counter() - start) * 1000.0
        return aligned_faces, {"face_alignment": elapsed_ms}
