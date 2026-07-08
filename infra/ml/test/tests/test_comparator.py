from __future__ import annotations

import math

import pytest

from comparator.compare import (
    ThresholdConfig,
    compare_platform_matrix,
    compare_result_sets,
)
from ground_truth.schema import ClipResult, FaceResult, ParityResult, RunnerMetadata


def _unit_vector(length: int, seed: int) -> tuple[float, ...]:
    values = [(((index + 5) * (seed + 13)) % 67) - 33 for index in range(length)]
    norm = math.sqrt(sum(value * value for value in values))
    return tuple(value / norm for value in values)


def _jittered_vector(vector: tuple[float, ...], *, index: int, delta: float) -> tuple[float, ...]:
    mutable = list(vector)
    mutable[index] += delta
    norm = math.sqrt(sum(value * value for value in mutable))
    return tuple(value / norm for value in mutable)


def _metadata(platform: str) -> RunnerMetadata:
    return RunnerMetadata(
        platform=platform,
        runtime="pytest",
        models={
            "clip": "clip-hash",
            "face_detection": "fd-hash",
            "face_embedding": "fe-hash",
        },
        code_revision="deadbee",
    )


def _face(seed: int, *, x: float, y: float, score: float) -> FaceResult:
    return FaceResult(
        box=(x, y, 0.22, 0.24),
        landmarks=(
            (x + 0.06, y + 0.09),
            (x + 0.16, y + 0.09),
            (x + 0.11, y + 0.14),
            (x + 0.07, y + 0.20),
            (x + 0.15, y + 0.20),
        ),
        score=score,
        embedding=_unit_vector(192, seed=seed),
    )


def _face_with_box(
    seed: int,
    *,
    x: float,
    y: float,
    width: float,
    height: float,
    score: float,
) -> FaceResult:
    return FaceResult(
        box=(x, y, width, height),
        landmarks=(
            (x + width * 0.30, y + height * 0.35),
            (x + width * 0.70, y + height * 0.35),
            (x + width * 0.50, y + height * 0.55),
            (x + width * 0.35, y + height * 0.78),
            (x + width * 0.65, y + height * 0.78),
        ),
        score=score,
        embedding=_unit_vector(192, seed=seed),
    )


def _result(
    *,
    file_id: str,
    platform: str,
    clip_seed: int,
    faces: tuple[FaceResult, ...],
) -> ParityResult:
    return ParityResult(
        file_id=file_id,
        clip=ClipResult(embedding=_unit_vector(512, seed=clip_seed)),
        faces=faces,
        runner_metadata=_metadata(platform),
    )


def _status_for_file(report: object, file_id: str):
    return next(status for status in report.file_statuses if status.file_id == file_id)


def test_compare_result_sets_passes_when_within_thresholds() -> None:
    reference_faces = (_face(100, x=0.22, y=0.10, score=0.95),)
    reference = _result(
        file_id="man.jpeg",
        platform="python",
        clip_seed=10,
        faces=reference_faces,
    )

    candidate_face = FaceResult(
        box=(0.2205, 0.101, 0.22, 0.24),
        landmarks=(
            (0.279, 0.188),
            (0.381, 0.188),
            (0.331, 0.241),
            (0.292, 0.300),
            (0.367, 0.300),
        ),
        score=0.952,
        embedding=_jittered_vector(reference_faces[0].embedding, index=0, delta=0.001),
    )
    candidate = ParityResult(
        file_id="man.jpeg",
        clip=ClipResult(
            embedding=_jittered_vector(reference.clip.embedding, index=0, delta=0.001)
        ),
        faces=(candidate_face,),
        runner_metadata=_metadata("android"),
    )

    report = compare_result_sets(
        reference_platform="python",
        candidate_platform="android",
        reference_results={reference.file_id: reference},
        candidate_results={candidate.file_id: candidate},
    )

    assert report.passed is True
    assert report.findings == ()
    assert report.aggregates["clip_cosine_distance"].count == 1
    assert report.total_reference_files == 1
    assert report.passing_files == ("man.jpeg",)
    assert report.failing_files == ()
    file_status = _status_for_file(report, "man.jpeg")
    assert file_status.passed is True
    metric_names = {metric.metric for metric in file_status.metrics}
    assert "clip_cosine_distance" in metric_names
    assert "face_count_delta" in metric_names
    clip_metric = next(
        metric
        for metric in file_status.metrics
        if metric.metric == "clip_cosine_distance"
    )
    assert clip_metric.passed is True


def test_compare_result_sets_fails_on_clip_drift() -> None:
    reference = _result(
        file_id="people.jpeg",
        platform="python",
        clip_seed=1,
        faces=(_face(200, x=0.2, y=0.1, score=0.91),),
    )
    candidate = _result(
        file_id="people.jpeg",
        platform="ios",
        clip_seed=999,
        faces=(_face(200, x=0.2, y=0.1, score=0.91),),
    )

    report = compare_result_sets(
        reference_platform="python",
        candidate_platform="ios",
        reference_results={reference.file_id: reference},
        candidate_results={candidate.file_id: candidate},
    )

    assert report.passed is False
    assert any(finding.metric == "clip_cosine_distance" for finding in report.findings)


def test_compare_result_sets_marks_clip_warning_band() -> None:
    reference = _result(
        file_id="clip-warning.jpeg",
        platform="python",
        clip_seed=10,
        faces=(_face(910, x=0.2, y=0.1, score=0.91),),
    )
    candidate = ParityResult(
        file_id=reference.file_id,
        clip=ClipResult(
            embedding=_jittered_vector(reference.clip.embedding, index=0, delta=0.25)
        ),
        faces=reference.faces,
        runner_metadata=_metadata("ios"),
    )

    report = compare_result_sets(
        reference_platform="python",
        candidate_platform="ios",
        reference_results={reference.file_id: reference},
        candidate_results={candidate.file_id: candidate},
    )

    assert report.status == "warning"
    assert report.passed is True
    assert report.findings == ()
    assert report.warning_files == ("*aggregate*", "clip-warning.jpeg")
    assert report.failing_files == ()
    assert any(
        warning.metric == "clip_cosine_distance"
        and warning.file_id == "clip-warning.jpeg"
        for warning in report.warnings
    )
    assert any(
        warning.metric == "clip_cosine_distance" and warning.file_id == "*aggregate*"
        for warning in report.warnings
    )

    file_status = _status_for_file(report, "clip-warning.jpeg")
    assert file_status.status == "warning"
    assert file_status.passed is True
    assert file_status.failures == ()
    assert any(
        warning.metric == "clip_cosine_distance" for warning in file_status.warnings
    )

    clip_metric = next(
        metric
        for metric in file_status.metrics
        if metric.metric == "clip_cosine_distance"
    )
    assert clip_metric.status == "warning"
    assert clip_metric.passed is True
    assert clip_metric.value is not None
    assert 0.015 < clip_metric.value <= 0.035


def test_compare_result_sets_passes_when_iou_above_single_loose_threshold() -> None:
    reference_face = _face_with_box(
        310,
        x=0.20,
        y=0.20,
        width=0.20,
        height=0.20,
        score=0.92,
    )
    reference = _result(
        file_id="loose-iou-face.webp",
        platform="python",
        clip_seed=11,
        faces=(reference_face,),
    )
    candidate_face = _face_with_box(
        310,
        x=0.21,
        y=0.21,
        width=0.20,
        height=0.20,
        score=0.92,
    )
    candidate = ParityResult(
        file_id=reference.file_id,
        clip=reference.clip,
        faces=(candidate_face,),
        runner_metadata=_metadata("android"),
    )

    report = compare_result_sets(
        reference_platform="python",
        candidate_platform="android",
        reference_results={reference.file_id: reference},
        candidate_results={candidate.file_id: candidate},
    )

    assert report.passed is True
    assert not any(finding.metric == "face_box_iou" for finding in report.findings)
    file_status = _status_for_file(report, reference.file_id)
    iou_shortfall_metric = next(
        metric
        for metric in file_status.metrics
        if metric.metric == "face_box_iou_shortfall_max"
    )
    assert iou_shortfall_metric.passed is True
    assert iou_shortfall_metric.value == pytest.approx(0.0)


def test_compare_result_sets_fails_when_iou_below_single_loose_threshold() -> None:
    reference_face = _face_with_box(
        701,
        x=0.20,
        y=0.20,
        width=0.20,
        height=0.20,
        score=0.92,
    )
    reference = _result(
        file_id="loose-iou-fail-face.webp",
        platform="python",
        clip_seed=21,
        faces=(reference_face,),
    )
    candidate_face = _face_with_box(
        999,
        x=0.23,
        y=0.23,
        width=0.20,
        height=0.20,
        score=0.92,
    )
    candidate = ParityResult(
        file_id=reference.file_id,
        clip=reference.clip,
        faces=(candidate_face,),
        runner_metadata=_metadata("android"),
    )

    report = compare_result_sets(
        reference_platform="python",
        candidate_platform="android",
        reference_results={reference.file_id: reference},
        candidate_results={candidate.file_id: candidate},
    )

    assert report.passed is False
    iou_failures = [finding for finding in report.findings if finding.metric == "face_box_iou"]
    assert iou_failures
    assert iou_failures[0].threshold == pytest.approx(0.80)

    file_status = _status_for_file(report, reference.file_id)
    iou_shortfall_metric = next(
        metric
        for metric in file_status.metrics
        if metric.metric == "face_box_iou_shortfall_max"
    )
    assert iou_shortfall_metric.passed is False
    assert iou_shortfall_metric.value is not None
    assert iou_shortfall_metric.value > 0.0


def test_compare_result_sets_fails_on_face_count_mismatch() -> None:
    reference = _result(
        file_id="people.jpeg",
        platform="python",
        clip_seed=4,
        faces=(
            _face(10, x=0.2, y=0.1, score=0.9),
            _face(11, x=0.5, y=0.2, score=0.87),
        ),
    )
    candidate = _result(
        file_id="people.jpeg",
        platform="desktop",
        clip_seed=4,
        faces=(_face(10, x=0.2, y=0.1, score=0.9),),
    )

    report = compare_result_sets(
        reference_platform="python",
        candidate_platform="desktop",
        reference_results={reference.file_id: reference},
        candidate_results={candidate.file_id: candidate},
    )

    assert report.passed is False
    assert any(finding.metric == "face_count" for finding in report.findings)
    assert report.total_reference_files == 1
    assert report.passing_files == ()
    assert report.failing_files == ("people.jpeg",)
    file_status = _status_for_file(report, "people.jpeg")
    assert any(
        failure.metric == "face_count" for failure in file_status.failures
    )
    face_count_metric = next(
        metric
        for metric in file_status.metrics
        if metric.metric == "face_count_delta"
    )
    assert face_count_metric.passed is False


def test_compare_result_sets_ignores_faces_below_min_score_threshold() -> None:
    reference = _result(
        file_id="score-filter.jpeg",
        platform="python",
        clip_seed=41,
        faces=(
            _face(510, x=0.18, y=0.14, score=0.95),
            _face(511, x=0.62, y=0.50, score=0.79),
        ),
    )
    candidate = _result(
        file_id="score-filter.jpeg",
        platform="android",
        clip_seed=41,
        faces=(
            _face(510, x=0.18, y=0.14, score=0.95),
        ),
    )

    report = compare_result_sets(
        reference_platform="python",
        candidate_platform="android",
        reference_results={reference.file_id: reference},
        candidate_results={candidate.file_id: candidate},
    )

    assert report.status == "pass"
    assert report.passed is True
    assert report.findings == ()
    assert report.warning_files == ()
    assert report.failing_files == ()
    assert report.passing_files == ("score-filter.jpeg",)

    file_status = _status_for_file(report, "score-filter.jpeg")
    assert file_status.status == "pass"
    assert file_status.passed is True
    assert file_status.failures == ()
    assert file_status.warnings == ()

    reference_count = next(
        metric for metric in file_status.metrics if metric.metric == "reference_face_count"
    )
    candidate_count = next(
        metric for metric in file_status.metrics if metric.metric == "candidate_face_count"
    )
    assert reference_count.value == pytest.approx(1.0)
    assert candidate_count.value == pytest.approx(1.0)
    assert not any(finding.metric == "face_count" for finding in report.findings)


def test_compare_result_sets_marks_face_embedding_warning_band() -> None:
    reference_face = _face(620, x=0.24, y=0.20, score=0.93)
    candidate_face = FaceResult(
        box=reference_face.box,
        landmarks=reference_face.landmarks,
        score=reference_face.score,
        embedding=_jittered_vector(reference_face.embedding, index=0, delta=0.2),
    )
    reference = _result(
        file_id="embedding-warning.jpeg",
        platform="python",
        clip_seed=17,
        faces=(reference_face,),
    )
    candidate = ParityResult(
        file_id=reference.file_id,
        clip=reference.clip,
        faces=(candidate_face,),
        runner_metadata=_metadata("ios"),
    )

    report = compare_result_sets(
        reference_platform="python",
        candidate_platform="ios",
        reference_results={reference.file_id: reference},
        candidate_results={candidate.file_id: candidate},
    )

    assert report.status == "warning"
    assert report.passed is True
    assert report.findings == ()
    assert report.failing_files == ()
    assert report.warning_files == ("*aggregate*", "embedding-warning.jpeg")
    assert report.passing_files == ()
    assert any(
        warning.metric == "face_embedding_cosine_distance"
        and warning.file_id == "embedding-warning.jpeg"
        for warning in report.warnings
    )
    assert any(warning.file_id == "*aggregate*" for warning in report.warnings)

    file_status = _status_for_file(report, "embedding-warning.jpeg")
    assert file_status.status == "warning"
    assert file_status.passed is True
    assert file_status.failures == ()
    assert any(
        warning.metric == "face_embedding_cosine_distance"
        for warning in file_status.warnings
    )

    embedding_metric = next(
        metric
        for metric in file_status.metrics
        if metric.metric == "face_embedding_cosine_distance_max"
    )
    assert embedding_metric.status == "warning"
    assert embedding_metric.passed is True
    assert embedding_metric.value is not None
    assert 0.015 < embedding_metric.value <= 0.035


def test_compare_result_sets_fails_face_embedding_above_warning_band() -> None:
    reference_face = _face(721, x=0.16, y=0.21, score=0.91)
    candidate_face = FaceResult(
        box=reference_face.box,
        landmarks=reference_face.landmarks,
        score=reference_face.score,
        embedding=_jittered_vector(reference_face.embedding, index=0, delta=0.3),
    )
    reference = _result(
        file_id="embedding-fail.jpeg",
        platform="python",
        clip_seed=29,
        faces=(reference_face,),
    )
    candidate = ParityResult(
        file_id=reference.file_id,
        clip=reference.clip,
        faces=(candidate_face,),
        runner_metadata=_metadata("desktop"),
    )

    report = compare_result_sets(
        reference_platform="python",
        candidate_platform="desktop",
        reference_results={reference.file_id: reference},
        candidate_results={candidate.file_id: candidate},
    )

    assert report.status == "fail"
    assert report.passed is False
    assert report.failing_files == ("*aggregate*", "embedding-fail.jpeg")
    assert report.warning_files == ()
    assert any(
        finding.metric == "face_embedding_cosine_distance" for finding in report.findings
    )

    file_status = _status_for_file(report, "embedding-fail.jpeg")
    assert file_status.status == "fail"
    assert file_status.passed is False

    embedding_metric = next(
        metric
        for metric in file_status.metrics
        if metric.metric == "face_embedding_cosine_distance_max"
    )
    assert embedding_metric.status == "fail"
    assert embedding_metric.passed is False
    assert embedding_metric.value is not None
    assert embedding_metric.value > 0.035


def test_compare_result_sets_reports_unmatched_faces_after_iou_gating() -> None:
    reference = _result(
        file_id="offset-face.jpeg",
        platform="python",
        clip_seed=19,
        faces=(
            _face_with_box(
                901,
                x=0.10,
                y=0.10,
                width=0.20,
                height=0.20,
                score=0.88,
            ),
        ),
    )
    candidate = _result(
        file_id="offset-face.jpeg",
        platform="desktop",
        clip_seed=19,
        faces=(
            _face_with_box(
                902,
                x=0.70,
                y=0.70,
                width=0.20,
                height=0.20,
                score=0.88,
            ),
        ),
    )

    report = compare_result_sets(
        reference_platform="python",
        candidate_platform="desktop",
        reference_results={reference.file_id: reference},
        candidate_results={candidate.file_id: candidate},
    )

    assert report.passed is False
    assert any(
        finding.metric == "unmatched_reference_face_count" for finding in report.findings
    )
    assert any(
        finding.metric == "unmatched_candidate_face_count" for finding in report.findings
    )
    assert not any(finding.metric == "face_box_iou" for finding in report.findings)

    file_status = _status_for_file(report, "offset-face.jpeg")
    matched_metric = next(
        metric for metric in file_status.metrics if metric.metric == "matched_face_count"
    )
    assert matched_metric.value == pytest.approx(0.0)
    assert matched_metric.passed is False

    unmatched_reference_metric = next(
        metric
        for metric in file_status.metrics
        if metric.metric == "unmatched_reference_face_count"
    )
    unmatched_candidate_metric = next(
        metric
        for metric in file_status.metrics
        if metric.metric == "unmatched_candidate_face_count"
    )
    assert unmatched_reference_metric.value == pytest.approx(1.0)
    assert unmatched_candidate_metric.value == pytest.approx(1.0)
    assert unmatched_reference_metric.passed is False
    assert unmatched_candidate_metric.passed is False


def test_aggregate_gate_failure_is_reported() -> None:
    reference_results = {}
    candidate_results = {}
    for index, delta in enumerate((0.0, 0.001, 0.04)):
        file_id = f"file-{index}.jpeg"
        reference = _result(
            file_id=file_id,
            platform="python",
            clip_seed=33 + index,
            faces=(_face(50 + index, x=0.2, y=0.2, score=0.95),),
        )
        if index == 2:
            candidate_clip = tuple(-value for value in reference.clip.embedding)
        else:
            candidate_clip = _jittered_vector(reference.clip.embedding, index=0, delta=delta)
        candidate = ParityResult(
            file_id=file_id,
            clip=ClipResult(embedding=candidate_clip),
            faces=reference.faces,
            runner_metadata=_metadata("android"),
        )
        reference_results[file_id] = reference
        candidate_results[file_id] = candidate

    report = compare_result_sets(
        reference_platform="python",
        candidate_platform="android",
        reference_results=reference_results,
        candidate_results=candidate_results,
        thresholds=ThresholdConfig(clip_cosine_distance=0.01),
    )

    assert report.passed is False
    assert any(finding.file_id == "*aggregate*" for finding in report.findings)
    assert "*aggregate*" in report.failing_files
    aggregate_status = next(
        status for status in report.file_statuses if status.file_id == "*aggregate*"
    )
    assert aggregate_status.status == "fail"
    assert any(metric.metric == "clip_cosine_distance" for metric in aggregate_status.metrics)


def test_extra_candidate_file_is_included_in_file_status_summary() -> None:
    extra_candidate = _result(
        file_id="unexpected.jpeg",
        platform="desktop",
        clip_seed=55,
        faces=(),
    )

    report = compare_result_sets(
        reference_platform="python",
        candidate_platform="desktop",
        reference_results={},
        candidate_results={extra_candidate.file_id: extra_candidate},
    )

    assert report.status == "fail"
    assert report.passed is False
    assert report.failing_files == ("unexpected.jpeg",)
    status = next(
        file_status
        for file_status in report.file_statuses
        if file_status.file_id == "unexpected.jpeg"
    )
    assert status.status == "fail"
    assert any(failure.metric == "file_presence" for failure in status.failures)


def test_compare_platform_matrix_includes_pairwise_reports() -> None:
    reference = _result(
        file_id="man.jpeg",
        platform="python",
        clip_seed=6,
        faces=(_face(200, x=0.25, y=0.12, score=0.9),),
    )
    android = ParityResult(
        file_id=reference.file_id,
        clip=ClipResult(embedding=_jittered_vector(reference.clip.embedding, index=0, delta=0.001)),
        faces=reference.faces,
        runner_metadata=_metadata("android"),
    )
    ios = ParityResult(
        file_id=reference.file_id,
        clip=ClipResult(embedding=_jittered_vector(reference.clip.embedding, index=1, delta=0.001)),
        faces=reference.faces,
        runner_metadata=_metadata("ios"),
    )
    desktop = ParityResult(
        file_id=reference.file_id,
        clip=ClipResult(embedding=_jittered_vector(reference.clip.embedding, index=2, delta=0.001)),
        faces=reference.faces,
        runner_metadata=_metadata("desktop"),
    )

    reports = compare_platform_matrix(
        {
            "python": (reference,),
            "android": (android,),
            "ios": (ios,),
            "desktop": (desktop,),
        }
    )

    assert len(reports) == 6
    assert all(report.passed for report in reports)


def test_compare_platform_matrix_rejects_duplicate_file_ids() -> None:
    reference = _result(
        file_id="man.jpeg",
        platform="python",
        clip_seed=6,
        faces=(_face(200, x=0.25, y=0.12, score=0.9),),
    )
    android_primary = _result(
        file_id="man.jpeg",
        platform="android",
        clip_seed=6,
        faces=(_face(200, x=0.25, y=0.12, score=0.9),),
    )
    android_duplicate = _result(
        file_id="man.jpeg",
        platform="android",
        clip_seed=7,
        faces=(_face(201, x=0.25, y=0.12, score=0.9),),
    )

    with pytest.raises(ValueError, match="platform 'android' emitted duplicate file_id values"):
        compare_platform_matrix(
            {
                "python": (reference,),
                "android": (android_primary, android_duplicate),
            }
        )


def test_threshold_config_rejects_invalid_warning_threshold() -> None:
    with pytest.raises(
        ValueError,
        match="face_embedding_warning_cosine_distance must be >=",
    ):
        ThresholdConfig(
            face_embedding_cosine_distance=0.02,
            face_embedding_warning_cosine_distance=0.01,
        )


def test_threshold_config_rejects_invalid_clip_warning_threshold() -> None:
    with pytest.raises(
        ValueError,
        match="clip_warning_cosine_distance must be >=",
    ):
        ThresholdConfig(
            clip_cosine_distance=0.02,
            clip_warning_cosine_distance=0.01,
        )


def test_threshold_config_rejects_invalid_cross_platform_clip_warning_threshold() -> None:
    with pytest.raises(
        ValueError,
        match="cross_platform_clip_warning_cosine_distance must be >=",
    ):
        ThresholdConfig(
            cross_platform_clip_cosine_distance=0.02,
            cross_platform_clip_warning_cosine_distance=0.01,
        )
