from __future__ import annotations

from dataclasses import dataclass, field
import json
import math
from typing import Any, Mapping, Sequence

CLIP_EMBEDDING_DIM = 512
FACE_EMBEDDING_DIM = 192
EMBEDDING_NORM_TOLERANCE = 1e-3
FLOAT_TOLERANCE = 1e-8


def l2_norm(values: Sequence[float]) -> float:
    return math.sqrt(sum(value * value for value in values))


def _coerce_float(value: Any, field_name: str) -> float:
    try:
        parsed = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{field_name} must be numeric") from exc

    if not math.isfinite(parsed):
        raise ValueError(f"{field_name} must be finite")

    return parsed


def _coerce_float_tuple(
    values: Sequence[Any],
    *,
    field_name: str,
    expected_len: int | None = None,
) -> tuple[float, ...]:
    if not isinstance(values, Sequence):
        raise ValueError(f"{field_name} must be a sequence")

    result = tuple(_coerce_float(value, field_name) for value in values)
    if expected_len is not None and len(result) != expected_len:
        raise ValueError(f"{field_name} must have exactly {expected_len} values")

    return result


def _validate_normalized_vector(
    values: Sequence[Any],
    *,
    field_name: str,
    expected_len: int,
) -> tuple[float, ...]:
    vector = _coerce_float_tuple(values, field_name=field_name, expected_len=expected_len)
    norm = l2_norm(vector)
    if norm <= FLOAT_TOLERANCE:
        raise ValueError(f"{field_name} must not be zero")

    if abs(norm - 1.0) > EMBEDDING_NORM_TOLERANCE:
        raise ValueError(f"{field_name} must be L2 normalized")

    return vector


def _validate_normalized_point(point: Sequence[Any], *, field_name: str) -> tuple[float, float]:
    x, y = _coerce_float_tuple(point, field_name=field_name, expected_len=2)
    if x < 0.0 or x > 1.0 or y < 0.0 or y > 1.0:
        raise ValueError(f"{field_name} values must be in [0, 1]")
    return x, y


@dataclass(frozen=True)
class ClipResult:
    embedding: tuple[float, ...]

    def __post_init__(self) -> None:
        object.__setattr__(
            self,
            "embedding",
            _validate_normalized_vector(
                self.embedding,
                field_name="clip.embedding",
                expected_len=CLIP_EMBEDDING_DIM,
            ),
        )

    @classmethod
    def from_dict(cls, payload: Mapping[str, Any]) -> ClipResult:
        return cls(embedding=_coerce_float_tuple(payload["embedding"], field_name="clip.embedding"))

    def to_dict(self) -> dict[str, Any]:
        return {"embedding": list(self.embedding)}


@dataclass(frozen=True)
class FaceResult:
    box: tuple[float, float, float, float]
    landmarks: tuple[tuple[float, float], ...]
    score: float
    embedding: tuple[float, ...]

    def __post_init__(self) -> None:
        x, y, width, height = _coerce_float_tuple(
            self.box,
            field_name="faces[].box",
            expected_len=4,
        )
        if width < 0.0 or height < 0.0:
            raise ValueError("faces[].box width and height must be non-negative")
        if x < 0.0 or y < 0.0 or x + width > 1.0 + FLOAT_TOLERANCE or y + height > 1.0 + FLOAT_TOLERANCE:
            raise ValueError("faces[].box must be normalized to [0, 1]")
        object.__setattr__(self, "box", (x, y, width, height))

        if not isinstance(self.landmarks, Sequence):
            raise ValueError("faces[].landmarks must be a sequence")
        normalized_landmarks = tuple(
            _validate_normalized_point(point, field_name="faces[].landmarks")
            for point in self.landmarks
        )
        object.__setattr__(self, "landmarks", normalized_landmarks)

        object.__setattr__(self, "score", _coerce_float(self.score, "faces[].score"))
        object.__setattr__(
            self,
            "embedding",
            _validate_normalized_vector(
                self.embedding,
                field_name="faces[].embedding",
                expected_len=FACE_EMBEDDING_DIM,
            ),
        )

    def sort_key(self) -> tuple[float, float, float, float, float]:
        return (
            round(self.box[0], 8),
            round(self.box[1], 8),
            round(self.box[2], 8),
            round(self.box[3], 8),
            -round(self.score, 8),
        )

    @classmethod
    def from_dict(cls, payload: Mapping[str, Any]) -> FaceResult:
        return cls(
            box=tuple(payload["box"]),
            landmarks=tuple(tuple(point) for point in payload["landmarks"]),
            score=payload["score"],
            embedding=tuple(payload["embedding"]),
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "box": [*self.box],
            "landmarks": [[x, y] for x, y in self.landmarks],
            "score": self.score,
            "embedding": [*self.embedding],
        }


@dataclass(frozen=True)
class RunnerMetadata:
    platform: str
    runtime: str
    models: Mapping[str, str]
    code_revision: str
    timing_ms: Mapping[str, float] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if not self.platform:
            raise ValueError("runner_metadata.platform is required")
        if not self.runtime:
            raise ValueError("runner_metadata.runtime is required")
        if not self.code_revision:
            raise ValueError("runner_metadata.code_revision is required")
        if not self.models:
            raise ValueError("runner_metadata.models must not be empty")

        normalized_models: dict[str, str] = {}
        for model_name, model_hash in self.models.items():
            if not model_name or not model_hash:
                raise ValueError("runner_metadata.models entries must have name and hash")
            normalized_models[str(model_name)] = str(model_hash)
        object.__setattr__(self, "models", normalized_models)

        normalized_timing: dict[str, float] = {}
        for key, value in self.timing_ms.items():
            parsed = _coerce_float(value, f"runner_metadata.timing_ms.{key}")
            if parsed < 0:
                raise ValueError("runner_metadata.timing_ms values must be non-negative")
            normalized_timing[str(key)] = parsed
        object.__setattr__(self, "timing_ms", normalized_timing)

    @classmethod
    def from_dict(cls, payload: Mapping[str, Any]) -> RunnerMetadata:
        return cls(
            platform=str(payload["platform"]),
            runtime=str(payload["runtime"]),
            models=dict(payload["models"]),
            code_revision=str(payload["code_revision"]),
            timing_ms=dict(payload.get("timing_ms", {})),
        )

    def to_dict(self) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "platform": self.platform,
            "runtime": self.runtime,
            "models": dict(self.models),
            "code_revision": self.code_revision,
        }
        if self.timing_ms:
            payload["timing_ms"] = dict(self.timing_ms)
        return payload


@dataclass(frozen=True)
class ParityResult:
    file_id: str
    clip: ClipResult
    faces: tuple[FaceResult, ...]
    runner_metadata: RunnerMetadata

    def __post_init__(self) -> None:
        if not self.file_id:
            raise ValueError("file_id is required")

        canonical_faces = tuple(sorted(self.faces, key=lambda face: face.sort_key()))
        object.__setattr__(self, "faces", canonical_faces)

    @classmethod
    def from_dict(cls, payload: Mapping[str, Any]) -> ParityResult:
        return cls(
            file_id=str(payload["file_id"]),
            clip=ClipResult.from_dict(payload["clip"]),
            faces=tuple(FaceResult.from_dict(face_payload) for face_payload in payload["faces"]),
            runner_metadata=RunnerMetadata.from_dict(payload["runner_metadata"]),
        )

    @classmethod
    def from_json(cls, payload: str) -> ParityResult:
        return cls.from_dict(json.loads(payload))

    def to_dict(self) -> dict[str, Any]:
        return {
            "file_id": self.file_id,
            "clip": self.clip.to_dict(),
            "faces": [face.to_dict() for face in self.faces],
            "runner_metadata": self.runner_metadata.to_dict(),
        }

    def to_json(self) -> str:
        return json.dumps(self.to_dict(), sort_keys=True, separators=(",", ":"))


def load_results_document(payload: Any) -> tuple[ParityResult, ...]:
    if isinstance(payload, Mapping):
        if "results" in payload:
            raw_results = payload["results"]
        else:
            raw_results = [payload]
    else:
        raw_results = payload

    if not isinstance(raw_results, Sequence):
        raise ValueError("result payload must be a result object, list of results, or {'results': [...]}")

    return tuple(ParityResult.from_dict(raw_result) for raw_result in raw_results)


def dump_results_document(results: Sequence[ParityResult], *, platform: str | None = None) -> str:
    payload: dict[str, Any] = {"results": [result.to_dict() for result in results]}
    if platform:
        payload["platform"] = platform
    return json.dumps(payload, indent=2, sort_keys=True)
