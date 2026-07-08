from __future__ import annotations

from dataclasses import dataclass
from time import perf_counter

import cv2
import numpy as np

from ._runtime import DEFAULT_PADDING_RGB, ModelArtifact, create_ort_session


YOLO_INPUT_WIDTH = 640
YOLO_INPUT_HEIGHT = 640
YOLO_IOU_THRESHOLD = 0.4
YOLO_SCORE_THRESHOLD = 0.5
YOLO_NUM_KEYPOINTS = 5


@dataclass(frozen=True)
class FaceDetection:
    score: float
    box_xyxy: tuple[float, float, float, float]
    landmarks: tuple[tuple[float, float], ...]

    def to_box_xywh(self) -> tuple[float, float, float, float]:
        x_min, y_min, x_max, y_max = self.box_xyxy
        return (x_min, y_min, max(0.0, x_max - x_min), max(0.0, y_max - y_min))


def preprocess_image_yolo_face(
    image_rgb: np.ndarray,
) -> tuple[np.ndarray, tuple[int, int]]:
    if image_rgb.ndim != 3 or image_rgb.shape[2] != 3:
        raise ValueError("face detection expects an RGB image with shape [H, W, 3]")

    image_height, image_width = image_rgb.shape[:2]
    scale = min(YOLO_INPUT_WIDTH / image_width, YOLO_INPUT_HEIGHT / image_height)
    scaled_width = int(round(image_width * scale))
    scaled_height = int(round(image_height * scale))

    resized = cv2.resize(
        image_rgb,
        (scaled_width, scaled_height),
        interpolation=cv2.INTER_LINEAR,
    )

    canvas = np.full(
        (YOLO_INPUT_HEIGHT, YOLO_INPUT_WIDTH, 3),
        DEFAULT_PADDING_RGB,
        dtype=np.uint8,
    )
    canvas[:scaled_height, :scaled_width] = resized

    chw = np.transpose(canvas.astype(np.float32) / 255.0, (2, 0, 1))
    return np.ascontiguousarray(chw), (scaled_width, scaled_height)


def _normalize_xyxy(row: np.ndarray) -> tuple[float, float, float, float]:
    x_center, y_center, width, height = row[:4]
    x_min = float((x_center - width / 2.0) / YOLO_INPUT_WIDTH)
    y_min = float((y_center - height / 2.0) / YOLO_INPUT_HEIGHT)
    x_max = float((x_center + width / 2.0) / YOLO_INPUT_WIDTH)
    y_max = float((y_center + height / 2.0) / YOLO_INPUT_HEIGHT)
    return x_min, y_min, x_max, y_max


def _normalize_landmarks(row: np.ndarray) -> tuple[tuple[float, float], ...]:
    landmarks: list[tuple[float, float]] = []
    for keypoint_index in range(YOLO_NUM_KEYPOINTS):
        x = float(row[5 + keypoint_index * 2] / YOLO_INPUT_WIDTH)
        y = float(row[6 + keypoint_index * 2] / YOLO_INPUT_HEIGHT)
        landmarks.append((x, y))
    return tuple(landmarks)


def _correct_for_aspect_ratio(
    *,
    box_xyxy: tuple[float, float, float, float],
    landmarks: tuple[tuple[float, float], ...],
    scaled_width: int,
    scaled_height: int,
) -> tuple[tuple[float, float, float, float], tuple[tuple[float, float], ...]]:
    if scaled_width <= 0 or scaled_height <= 0:
        raise ValueError("scaled_width and scaled_height must be positive")

    scale_x = YOLO_INPUT_WIDTH / scaled_width
    scale_y = YOLO_INPUT_HEIGHT / scaled_height

    x_min, y_min, x_max, y_max = box_xyxy
    corrected_box = (
        float(np.clip(x_min * scale_x, 0.0, 1.0)),
        float(np.clip(y_min * scale_y, 0.0, 1.0)),
        float(np.clip(x_max * scale_x, 0.0, 1.0)),
        float(np.clip(y_max * scale_y, 0.0, 1.0)),
    )

    corrected_landmarks = tuple(
        (
            float(np.clip(x * scale_x, 0.0, 1.0)),
            float(np.clip(y * scale_y, 0.0, 1.0)),
        )
        for x, y in landmarks
    )

    return corrected_box, corrected_landmarks


def _nms_faces(candidates: list[FaceDetection]) -> list[FaceDetection]:
    if not candidates:
        return []

    boxes = [list(candidate.to_box_xywh()) for candidate in candidates]
    scores = [float(candidate.score) for candidate in candidates]

    indices = cv2.dnn.NMSBoxes(
        bboxes=boxes,
        scores=scores,
        score_threshold=0.0,
        nms_threshold=YOLO_IOU_THRESHOLD,
    )
    if indices is None or len(indices) == 0:
        return []

    selected_indices = sorted(int(index) for index in np.asarray(indices).reshape(-1).tolist())
    return [candidates[index] for index in selected_indices]


def postprocess_yolo_output(
    *,
    raw_output: np.ndarray,
    scaled_width: int,
    scaled_height: int,
) -> list[FaceDetection]:
    output = np.asarray(raw_output, dtype=np.float32)
    if output.ndim == 3:
        output = output[0]
    if output.ndim != 2 or output.shape[1] < 15:
        raise ValueError(f"unexpected YOLO output shape: {output.shape}")

    surviving_rows = output[output[:, 4] >= YOLO_SCORE_THRESHOLD]
    if surviving_rows.size == 0:
        return []

    candidates: list[FaceDetection] = []
    for row in surviving_rows:
        box_xyxy = _normalize_xyxy(row)
        landmarks = _normalize_landmarks(row)
        corrected_box, corrected_landmarks = _correct_for_aspect_ratio(
            box_xyxy=box_xyxy,
            landmarks=landmarks,
            scaled_width=scaled_width,
            scaled_height=scaled_height,
        )
        candidates.append(
            FaceDetection(
                score=float(row[4]),
                box_xyxy=corrected_box,
                landmarks=corrected_landmarks,
            )
        )

    candidates.sort(
        key=lambda face: (
            -face.score,
            face.box_xyxy[0],
            face.box_xyxy[1],
            face.box_xyxy[2],
            face.box_xyxy[3],
        )
    )

    return _nms_faces(candidates)


class FaceDetectionModel:
    def __init__(self, artifact: ModelArtifact) -> None:
        self.artifact = artifact
        self._session = create_ort_session(artifact.path)
        self._input_name = self._session.get_inputs()[0].name

    def detect(self, image_rgb: np.ndarray) -> tuple[tuple[FaceDetection, ...], dict[str, float]]:
        preprocess_start = perf_counter()
        input_tensor, (scaled_width, scaled_height) = preprocess_image_yolo_face(image_rgb)
        preprocess_ms = (perf_counter() - preprocess_start) * 1000.0

        inference_start = perf_counter()
        outputs = self._session.run(None, {self._input_name: input_tensor[np.newaxis, ...]})
        inference_ms = (perf_counter() - inference_start) * 1000.0

        postprocess_start = perf_counter()
        detections = postprocess_yolo_output(
            raw_output=np.asarray(outputs[0], dtype=np.float32),
            scaled_width=scaled_width,
            scaled_height=scaled_height,
        )
        postprocess_ms = (perf_counter() - postprocess_start) * 1000.0

        return (
            tuple(detections),
            {
                "face_detection_preprocess": preprocess_ms,
                "face_detection_inference": inference_ms,
                "face_detection_postprocess": postprocess_ms,
                "face_detection": preprocess_ms + inference_ms + postprocess_ms,
            },
        )
