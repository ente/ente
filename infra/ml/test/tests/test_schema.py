from __future__ import annotations

import math

import pytest

from ground_truth.schema import (
    CLIP_EMBEDDING_DIM,
    FACE_EMBEDDING_DIM,
    ClipResult,
    FaceResult,
    ParityResult,
    RunnerMetadata,
)


def _unit_vector(length: int, seed: int) -> tuple[float, ...]:
    values = [(((index + 3) * (seed + 7)) % 41) - 20 for index in range(length)]
    norm = math.sqrt(sum(value * value for value in values))
    return tuple(value / norm for value in values)


def _runner_metadata() -> RunnerMetadata:
    return RunnerMetadata(
        platform="python",
        runtime="pytest",
        models={
            "clip": "clip-hash",
            "face_detection": "fd-hash",
            "face_embedding": "fe-hash",
        },
        code_revision="deadbee",
    )


def _face(index: int, *, x: float, score: float) -> FaceResult:
    return FaceResult(
        box=(x, 0.1 + index * 0.05, 0.2, 0.25),
        landmarks=(
            (x + 0.05, 0.15),
            (x + 0.15, 0.15),
            (x + 0.10, 0.20),
            (x + 0.06, 0.28),
            (x + 0.14, 0.28),
        ),
        score=score,
        embedding=_unit_vector(FACE_EMBEDDING_DIM, seed=30 + index),
    )


def test_parity_result_round_trip_and_canonical_face_sorting() -> None:
    unsorted_faces = (_face(0, x=0.4, score=0.91), _face(1, x=0.2, score=0.84))
    result = ParityResult(
        file_id="people.jpeg",
        clip=ClipResult(embedding=_unit_vector(CLIP_EMBEDDING_DIM, seed=11)),
        faces=unsorted_faces,
        runner_metadata=_runner_metadata(),
    )

    assert result.faces[0].box[0] == pytest.approx(0.2)
    assert result.faces[1].box[0] == pytest.approx(0.4)

    payload = result.to_json()
    round_tripped = ParityResult.from_json(payload)
    assert round_tripped == result


def test_invalid_clip_dimension_is_rejected() -> None:
    with pytest.raises(ValueError, match="exactly 512"):
        ClipResult(embedding=_unit_vector(10, seed=5))


def test_non_normalized_face_embedding_is_rejected() -> None:
    invalid_embedding = tuple(1.0 for _ in range(FACE_EMBEDDING_DIM))
    with pytest.raises(ValueError, match="L2 normalized"):
        FaceResult(
            box=(0.1, 0.2, 0.3, 0.3),
            landmarks=((0.2, 0.2),),
            score=0.9,
            embedding=invalid_embedding,
        )
