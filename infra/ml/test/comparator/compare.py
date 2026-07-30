from __future__ import annotations

from dataclasses import dataclass
import math
from typing import Any, Mapping, Sequence

from ground_truth.schema import FaceResult, ParityResult, l2_norm

STATUS_PASS = "pass"
STATUS_WARNING = "warning"
STATUS_FAIL = "fail"
AGGREGATE_FILE_ID = "*aggregate*"


def _threshold_status(
    value: float,
    threshold: float,
    warning_threshold: float | None = None,
) -> str:
    if value <= threshold:
        return STATUS_PASS
    if warning_threshold is not None and value <= warning_threshold:
        return STATUS_WARNING
    return STATUS_FAIL


def cosine_distance(left: Sequence[float], right: Sequence[float]) -> float:
    if len(left) != len(right):
        raise ValueError("cosine distance vectors must have equal dimensions")
    dot = sum(x * y for x, y in zip(left, right, strict=True))
    denominator = l2_norm(left) * l2_norm(right)
    if denominator == 0:
        raise ValueError("cosine distance cannot be computed for zero vectors")
    similarity = dot / denominator
    similarity = max(-1.0, min(1.0, similarity))
    return 1.0 - similarity


def _box_iou(left: Sequence[float], right: Sequence[float]) -> float:
    lx, ly, lw, lh = left
    rx, ry, rw, rh = right

    left_x2 = lx + lw
    left_y2 = ly + lh
    right_x2 = rx + rw
    right_y2 = ry + rh

    inter_x1 = max(lx, rx)
    inter_y1 = max(ly, ry)
    inter_x2 = min(left_x2, right_x2)
    inter_y2 = min(left_y2, right_y2)

    inter_w = max(0.0, inter_x2 - inter_x1)
    inter_h = max(0.0, inter_y2 - inter_y1)
    inter_area = inter_w * inter_h
    left_area = max(0.0, lw * lh)
    right_area = max(0.0, rw * rh)

    denominator = left_area + right_area - inter_area
    if denominator <= 0:
        return 0.0

    return inter_area / denominator


def _landmark_error(left: Sequence[Sequence[float]], right: Sequence[Sequence[float]]) -> float:
    if len(left) != len(right):
        raise ValueError("landmark count mismatch")
    if not left:
        return 0.0

    distances = []
    for left_point, right_point in zip(left, right, strict=True):
        dx = left_point[0] - right_point[0]
        dy = left_point[1] - right_point[1]
        distances.append(math.sqrt(dx * dx + dy * dy))

    return sum(distances) / len(distances)


def _percentile(values: Sequence[float], percentile: float) -> float:
    if not values:
        return 0.0

    sorted_values = sorted(values)
    if len(sorted_values) == 1:
        return sorted_values[0]

    rank = (len(sorted_values) - 1) * (percentile / 100.0)
    lower_index = math.floor(rank)
    upper_index = math.ceil(rank)
    if lower_index == upper_index:
        return sorted_values[lower_index]

    lower_value = sorted_values[lower_index]
    upper_value = sorted_values[upper_index]
    weight = rank - lower_index
    return lower_value + (upper_value - lower_value) * weight


@dataclass(frozen=True)
class ThresholdConfig:
    clip_cosine_distance: float = 0.015
    clip_warning_cosine_distance: float = 0.035
    face_embedding_cosine_distance: float = 0.015
    face_embedding_warning_cosine_distance: float = 0.035
    box_iou_threshold: float = 0.80
    face_duplicate_iou_threshold: float = 0.80
    face_match_iou_floor: float = 0.05
    landmark_error_threshold: float = 0.03
    score_delta_threshold: float = 0.05
    min_face_score_for_comparison: float = 0.80

    def __post_init__(self) -> None:
        if self.clip_warning_cosine_distance < self.clip_cosine_distance:
            raise ValueError(
                "clip_warning_cosine_distance must be >= clip_cosine_distance"
            )
        if self.face_embedding_warning_cosine_distance < self.face_embedding_cosine_distance:
            raise ValueError(
                "face_embedding_warning_cosine_distance must be >= face_embedding_cosine_distance"
            )

    def to_dict(self) -> dict[str, float]:
        return {
            "clip_cosine_distance": self.clip_cosine_distance,
            "clip_warning_cosine_distance": self.clip_warning_cosine_distance,
            "face_embedding_cosine_distance": self.face_embedding_cosine_distance,
            "face_embedding_warning_cosine_distance": self.face_embedding_warning_cosine_distance,
            "box_iou_threshold": self.box_iou_threshold,
            "face_duplicate_iou_threshold": self.face_duplicate_iou_threshold,
            "face_match_iou_floor": self.face_match_iou_floor,
            "landmark_error_threshold": self.landmark_error_threshold,
            "score_delta_threshold": self.score_delta_threshold,
            "min_face_score_for_comparison": self.min_face_score_for_comparison,
        }


@dataclass(frozen=True)
class AggregateMetric:
    count: int
    p95: float
    p99: float
    max: float
    threshold: float
    warning_threshold: float | None
    status: str
    passed: bool

    def to_dict(self) -> dict[str, float | int | bool | str | None]:
        return {
            "count": self.count,
            "p95": self.p95,
            "p99": self.p99,
            "max": self.max,
            "threshold": self.threshold,
            "warning_threshold": self.warning_threshold,
            "status": self.status,
            "passed": self.passed,
        }


@dataclass(frozen=True)
class ComparisonFinding:
    file_id: str
    metric: str
    message: str
    value: float | None = None
    threshold: float | None = None
    severity: str = STATUS_FAIL

    def to_dict(self) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "file_id": self.file_id,
            "metric": self.metric,
            "message": self.message,
            "severity": self.severity,
        }
        if self.value is not None:
            payload["value"] = self.value
        if self.threshold is not None:
            payload["threshold"] = self.threshold
        return payload


@dataclass(frozen=True)
class FileMetricMeasurement:
    metric: str
    value: float | None
    threshold: float | None
    status: str
    passed: bool
    direction: str | None = None
    count: int | None = None
    applicable: bool = True
    message: str | None = None

    def to_dict(self) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "metric": self.metric,
            "value": self.value,
            "threshold": self.threshold,
            "status": self.status,
            "passed": self.passed,
            "direction": self.direction,
            "count": self.count,
            "applicable": self.applicable,
            "message": self.message,
        }
        return payload


@dataclass(frozen=True)
class FileComparisonStatus:
    file_id: str
    status: str
    passed: bool
    metrics: tuple[FileMetricMeasurement, ...]
    failures: tuple[ComparisonFinding, ...]
    warnings: tuple[ComparisonFinding, ...]

    def to_dict(self) -> dict[str, Any]:
        return {
            "file_id": self.file_id,
            "status": self.status,
            "passed": self.passed,
            "metrics": [metric.to_dict() for metric in self.metrics],
            "failure_count": len(self.failures),
            "failures": [failure.to_dict() for failure in self.failures],
            "warning_count": len(self.warnings),
            "warnings": [warning.to_dict() for warning in self.warnings],
        }


@dataclass(frozen=True)
class ComparisonReport:
    reference_platform: str
    candidate_platform: str
    total_reference_files: int
    checked_files: int
    missing_files: tuple[str, ...]
    extra_files: tuple[str, ...]
    aggregates: Mapping[str, AggregateMetric]
    findings: tuple[ComparisonFinding, ...]
    warnings: tuple[ComparisonFinding, ...]
    file_statuses: tuple[FileComparisonStatus, ...]
    passing_files: tuple[str, ...]
    warning_files: tuple[str, ...]
    failing_files: tuple[str, ...]
    status: str
    passed: bool

    def to_dict(self) -> dict[str, Any]:
        file_statuses = tuple(
            file_status
            for file_status in self.file_statuses
            if file_status.file_id != AGGREGATE_FILE_ID
        )
        total_files = len(file_statuses)
        non_reference_file_count = max(0, total_files - self.total_reference_files)
        file_summary = {
            "total_reference_files": self.total_reference_files,
            "total_files": total_files,
            "non_reference_file_count": non_reference_file_count,
            "checked_files": self.checked_files,
            "pass_count": len(self.passing_files),
            "warning_count": len(self.warning_files),
            "fail_count": len(self.failing_files),
            "passing_files": list(self.passing_files),
            "warning_files": list(self.warning_files),
            "failing_files": list(self.failing_files),
        }
        return {
            "reference_platform": self.reference_platform,
            "candidate_platform": self.candidate_platform,
            "total_reference_files": self.total_reference_files,
            "checked_files": self.checked_files,
            "missing_files": list(self.missing_files),
            "extra_files": list(self.extra_files),
            "aggregates": {
                metric_name: metric.to_dict()
                for metric_name, metric in self.aggregates.items()
            },
            "findings": [finding.to_dict() for finding in self.findings],
            "warnings": [warning.to_dict() for warning in self.warnings],
            "file_summary": file_summary,
            "file_statuses": [file_status.to_dict() for file_status in self.file_statuses],
            "passing_files": list(self.passing_files),
            "warning_files": list(self.warning_files),
            "failing_files": list(self.failing_files),
            "status": self.status,
            "passed": self.passed,
        }


def _make_aggregate(
    values: list[float],
    threshold: float,
    *,
    warning_threshold: float | None = None,
) -> AggregateMetric:
    if not values:
        return AggregateMetric(
            count=0,
            p95=0.0,
            p99=0.0,
            max=0.0,
            threshold=threshold,
            warning_threshold=warning_threshold,
            status=STATUS_PASS,
            passed=True,
        )

    p95 = _percentile(values, 95.0)
    p99 = _percentile(values, 99.0)
    maximum = max(values)
    if p95 <= threshold and p99 <= threshold and maximum <= threshold:
        status = STATUS_PASS
    elif (
        warning_threshold is not None
        and p95 <= warning_threshold
        and p99 <= warning_threshold
        and maximum <= warning_threshold
    ):
        status = STATUS_WARNING
    else:
        status = STATUS_FAIL
    return AggregateMetric(
        count=len(values),
        p95=p95,
        p99=p99,
        max=maximum,
        threshold=threshold,
        warning_threshold=warning_threshold,
        status=status,
        passed=status != STATUS_FAIL,
    )


def _index_results(
    results: Sequence[ParityResult],
    *,
    platform: str,
) -> dict[str, ParityResult]:
    indexed: dict[str, ParityResult] = {}
    duplicate_ids: set[str] = set()

    for result in results:
        if result.file_id in indexed:
            duplicate_ids.add(result.file_id)
            continue
        indexed[result.file_id] = result

    if duplicate_ids:
        duplicates = ", ".join(sorted(duplicate_ids))
        raise ValueError(
            f"platform '{platform}' emitted duplicate file_id values: {duplicates}"
        )

    return indexed


def _match_faces(
    reference_faces: Sequence[FaceResult],
    candidate_faces: Sequence[FaceResult],
    *,
    min_iou_for_match: float = 0.0,
) -> list[tuple[int, int, float]]:
    pairs: list[tuple[float, int, int]] = []
    for reference_index, reference_face in enumerate(reference_faces):
        for candidate_index, candidate_face in enumerate(candidate_faces):
            iou = _box_iou(reference_face.box, candidate_face.box)
            pairs.append((iou, reference_index, candidate_index))

    pairs.sort(key=lambda entry: (-entry[0], entry[1], entry[2]))
    used_reference: set[int] = set()
    used_candidate: set[int] = set()
    matches: list[tuple[int, int, float]] = []
    for iou, reference_index, candidate_index in pairs:
        if iou < min_iou_for_match:
            break
        if reference_index in used_reference or candidate_index in used_candidate:
            continue
        used_reference.add(reference_index)
        used_candidate.add(candidate_index)
        matches.append((reference_index, candidate_index, iou))

    matches.sort(key=lambda entry: entry[0])
    return matches


def _dedupe_faces(
    faces: Sequence[FaceResult],
    *,
    min_iou_for_duplicate: float,
) -> tuple[FaceResult, ...]:
    kept: list[tuple[int, FaceResult]] = []
    for face_index, face in sorted(
        enumerate(faces),
        key=lambda entry: (-entry[1].score, entry[0]),
    ):
        if any(
            _box_iou(face.box, kept_face.box) >= min_iou_for_duplicate
            for _, kept_face in kept
        ):
            continue
        kept.append((face_index, face))

    kept.sort(key=lambda entry: entry[0])
    return tuple(face for _, face in kept)


def compare_result_sets(
    *,
    reference_platform: str,
    candidate_platform: str,
    reference_results: Mapping[str, ParityResult],
    candidate_results: Mapping[str, ParityResult],
    thresholds: ThresholdConfig | None = None,
    clip_threshold: float | None = None,
    clip_warning_threshold: float | None = None,
) -> ComparisonReport:
    thresholds = thresholds or ThresholdConfig()
    clip_threshold = (
        thresholds.clip_cosine_distance if clip_threshold is None else clip_threshold
    )
    clip_warning_threshold = (
        thresholds.clip_warning_cosine_distance
        if clip_warning_threshold is None
        else clip_warning_threshold
    )
    if clip_warning_threshold < clip_threshold:
        raise ValueError("clip_warning_threshold must be >= clip_threshold")

    missing_files = tuple(sorted(set(reference_results) - set(candidate_results)))
    extra_files = tuple(sorted(set(candidate_results) - set(reference_results)))
    findings: list[ComparisonFinding] = []
    warnings: list[ComparisonFinding] = []
    file_failures: dict[str, list[ComparisonFinding]] = {}
    file_warnings: dict[str, list[ComparisonFinding]] = {}
    file_metrics: dict[str, list[FileMetricMeasurement]] = {}

    def ensure_file_entry(file_id: str) -> None:
        if file_id not in file_failures:
            file_failures[file_id] = []
        if file_id not in file_warnings:
            file_warnings[file_id] = []
        if file_id not in file_metrics:
            file_metrics[file_id] = []

    for file_id in reference_results:
        ensure_file_entry(file_id)

    def add_failure(finding: ComparisonFinding) -> None:
        findings.append(finding)
        ensure_file_entry(finding.file_id)
        file_failures[finding.file_id].append(finding)

    def add_warning(warning: ComparisonFinding) -> None:
        warnings.append(warning)
        ensure_file_entry(warning.file_id)
        file_warnings[warning.file_id].append(warning)

    def add_file_metric(
        *,
        file_id: str,
        metric: str,
        value: float | None,
        threshold: float | None,
        status: str,
        passed: bool,
        direction: str | None = None,
        count: int | None = None,
        applicable: bool = True,
        message: str | None = None,
    ) -> None:
        ensure_file_entry(file_id)
        file_metrics[file_id].append(
            FileMetricMeasurement(
                metric=metric,
                value=value,
                threshold=threshold,
                status=status,
                passed=passed,
                direction=direction,
                count=count,
                applicable=applicable,
                message=message,
            )
        )

    def add_matched_max_metric(
        *,
        file_id: str,
        metric: str,
        values: list[float],
        threshold: float,
        passes_when_empty: bool,
        warning_threshold: float | None = None,
        message: str,
    ) -> None:
        if values:
            maximum = max(values)
            status = _threshold_status(maximum, threshold, warning_threshold)
            add_file_metric(
                file_id=file_id,
                metric=metric,
                value=maximum,
                threshold=threshold,
                status=status,
                passed=status != STATUS_FAIL,
                direction="<=",
                count=len(values),
                message=message,
            )
        else:
            add_file_metric(
                file_id=file_id,
                metric=metric,
                value=None,
                threshold=threshold,
                status=STATUS_PASS if passes_when_empty else STATUS_FAIL,
                passed=passes_when_empty,
                direction="<=",
                count=0,
                applicable=False,
                message="No matched faces",
            )

    for missing_file in missing_files:
        add_failure(
            ComparisonFinding(
                file_id=missing_file,
                metric="file_presence",
                message=f"Missing from {candidate_platform}",
                severity=STATUS_FAIL,
            ),
        )
        add_file_metric(
            file_id=missing_file,
            metric="file_presence",
            value=0.0,
            threshold=1.0,
            status=STATUS_FAIL,
            passed=False,
            direction="==",
            message=f"Missing from {candidate_platform}",
        )
    for extra_file in extra_files:
        add_failure(
            ComparisonFinding(
                file_id=extra_file,
                metric="file_presence",
                message=f"Unexpected file in {candidate_platform}",
                severity=STATUS_FAIL,
            ),
        )
        add_file_metric(
            file_id=extra_file,
            metric="file_presence",
            value=1.0,
            threshold=0.0,
            status=STATUS_FAIL,
            passed=False,
            direction="==",
            message=f"Unexpected file in {candidate_platform}",
        )

    clip_distances: list[float] = []
    iou_errors: list[float] = []
    landmark_errors: list[float] = []
    score_deltas: list[float] = []
    face_embedding_distances: list[float] = []

    shared_file_ids = sorted(set(reference_results) & set(candidate_results))
    for file_id in shared_file_ids:
        reference = reference_results[file_id]
        candidate = candidate_results[file_id]

        reference_faces = _dedupe_faces(
            reference.faces,
            min_iou_for_duplicate=thresholds.face_duplicate_iou_threshold,
        )
        candidate_faces = _dedupe_faces(
            candidate.faces,
            min_iou_for_duplicate=thresholds.face_duplicate_iou_threshold,
        )

        clip_distance = cosine_distance(reference.clip.embedding, candidate.clip.embedding)
        clip_distances.append(clip_distance)
        clip_status = _threshold_status(clip_distance, clip_threshold, clip_warning_threshold)
        add_file_metric(
            file_id=file_id,
            metric="clip_cosine_distance",
            value=clip_distance,
            threshold=clip_threshold,
            status=clip_status,
            passed=clip_status != STATUS_FAIL,
            direction="<=",
            message="CLIP cosine distance",
        )
        if clip_status == STATUS_WARNING:
            add_warning(
                ComparisonFinding(
                    file_id=file_id,
                    metric="clip_cosine_distance",
                    message=(
                        "CLIP cosine distance in warning band "
                        f"({clip_threshold:.3f} - {clip_warning_threshold:.3f})"
                    ),
                    value=clip_distance,
                    threshold=clip_warning_threshold,
                    severity=STATUS_WARNING,
                ),
            )
        elif clip_status == STATUS_FAIL:
            add_failure(
                ComparisonFinding(
                    file_id=file_id,
                    metric="clip_cosine_distance",
                    message="CLIP cosine distance exceeded threshold",
                    value=clip_distance,
                    threshold=clip_threshold,
                    severity=STATUS_FAIL,
                ),
            )

        all_matches = _match_faces(
            reference_faces,
            candidate_faces,
            min_iou_for_match=thresholds.face_match_iou_floor,
        )
        matched_reference_indices = {
            reference_index for reference_index, _, _ in all_matches
        }
        matched_candidate_indices = {
            candidate_index for _, candidate_index, _ in all_matches
        }
        relevant_matches = tuple(
            (reference_index, candidate_index, iou)
            for reference_index, candidate_index, iou in all_matches
            if (
                reference_faces[reference_index].score
                >= thresholds.min_face_score_for_comparison
                or candidate_faces[candidate_index].score
                >= thresholds.min_face_score_for_comparison
            )
        )
        unmatched_reference_indices = tuple(
            reference_index
            for reference_index, face in enumerate(reference_faces)
            if (
                face.score >= thresholds.min_face_score_for_comparison
                and reference_index not in matched_reference_indices
            )
        )
        unmatched_candidate_indices = tuple(
            candidate_index
            for candidate_index, face in enumerate(candidate_faces)
            if (
                face.score >= thresholds.min_face_score_for_comparison
                and candidate_index not in matched_candidate_indices
            )
        )
        comparable_reference_indices = {
            reference_index for reference_index, _, _ in relevant_matches
        } | set(unmatched_reference_indices)
        comparable_candidate_indices = {
            candidate_index for _, candidate_index, _ in relevant_matches
        } | set(unmatched_candidate_indices)

        reference_face_count = len(comparable_reference_indices)
        candidate_face_count = len(comparable_candidate_indices)
        no_faces = reference_face_count == 0 and candidate_face_count == 0
        add_file_metric(
            file_id=file_id,
            metric="reference_face_count",
            value=float(reference_face_count),
            threshold=None,
            status=STATUS_PASS,
            passed=True,
            message=(
                f"{reference_platform} comparable face count "
                f"(matched if either score >= {thresholds.min_face_score_for_comparison:.2f})"
            ),
        )
        add_file_metric(
            file_id=file_id,
            metric="candidate_face_count",
            value=float(candidate_face_count),
            threshold=None,
            status=STATUS_PASS,
            passed=True,
            message=(
                f"{candidate_platform} comparable face count "
                f"(matched if either score >= {thresholds.min_face_score_for_comparison:.2f})"
            ),
        )
        face_count_delta = abs(reference_face_count - candidate_face_count)
        add_file_metric(
            file_id=file_id,
            metric="face_count_delta",
            value=float(face_count_delta),
            threshold=0.0,
            status=STATUS_PASS if face_count_delta == 0 else STATUS_FAIL,
            passed=face_count_delta == 0,
            direction="<=",
            message="Absolute face count difference",
        )

        if reference_face_count != candidate_face_count:
            add_failure(
                ComparisonFinding(
                    file_id=file_id,
                    metric="face_count",
                    message="Face count mismatch",
                    value=float(face_count_delta),
                    severity=STATUS_FAIL,
                ),
            )

        maximum_possible_matches = min(reference_face_count, candidate_face_count)
        add_file_metric(
            file_id=file_id,
            metric="matched_face_count",
            value=float(len(relevant_matches)),
            threshold=float(maximum_possible_matches),
            status=(
                STATUS_PASS
                if len(relevant_matches) == maximum_possible_matches
                else STATUS_FAIL
            ),
            passed=len(relevant_matches) == maximum_possible_matches,
            direction="==",
            count=len(relevant_matches),
            message="Greedy IoU-gated face matches",
        )

        unmatched_reference_face_count = len(unmatched_reference_indices)
        unmatched_candidate_face_count = len(unmatched_candidate_indices)
        add_file_metric(
            file_id=file_id,
            metric="unmatched_reference_face_count",
            value=float(unmatched_reference_face_count),
            threshold=0.0,
            status=STATUS_PASS if unmatched_reference_face_count == 0 else STATUS_FAIL,
            passed=unmatched_reference_face_count == 0,
            direction="<=",
            message=(
                "Reference faces without a valid IoU-gated match "
                f"(IoU floor: {thresholds.face_match_iou_floor:.2f})"
            ),
        )
        add_file_metric(
            file_id=file_id,
            metric="unmatched_candidate_face_count",
            value=float(unmatched_candidate_face_count),
            threshold=0.0,
            status=STATUS_PASS if unmatched_candidate_face_count == 0 else STATUS_FAIL,
            passed=unmatched_candidate_face_count == 0,
            direction="<=",
            message=(
                "Candidate faces without a valid IoU-gated match "
                f"(IoU floor: {thresholds.face_match_iou_floor:.2f})"
            ),
        )

        if unmatched_reference_face_count > 0:
            add_failure(
                ComparisonFinding(
                    file_id=file_id,
                    metric="unmatched_reference_face_count",
                    message="Unmatched reference faces after IoU-gated matching",
                    value=float(unmatched_reference_face_count),
                    threshold=0.0,
                    severity=STATUS_FAIL,
                ),
            )
        if unmatched_candidate_face_count > 0:
            add_failure(
                ComparisonFinding(
                    file_id=file_id,
                    metric="unmatched_candidate_face_count",
                    message="Unmatched candidate faces after IoU-gated matching",
                    value=float(unmatched_candidate_face_count),
                    threshold=0.0,
                    severity=STATUS_FAIL,
                ),
            )

        add_file_metric(
            file_id=file_id,
            metric="face_match_iou_floor",
            value=thresholds.face_match_iou_floor,
            threshold=None,
            status=STATUS_PASS,
            passed=True,
            message="Minimum IoU required to keep a match",
        )

        file_ious: list[float] = []
        file_iou_shortfalls: list[float] = []
        file_landmark_errors: list[float] = []
        file_score_deltas: list[float] = []
        file_embedding_distances: list[float] = []
        for reference_index, candidate_index, iou in relevant_matches:
            reference_face = reference_faces[reference_index]
            candidate_face = candidate_faces[candidate_index]

            embedding_distance = cosine_distance(
                reference_face.embedding,
                candidate_face.embedding,
            )
            file_embedding_distances.append(embedding_distance)
            face_embedding_distances.append(embedding_distance)

            iou_threshold = thresholds.box_iou_threshold

            file_ious.append(iou)
            iou_shortfall = max(0.0, iou_threshold - iou)
            file_iou_shortfalls.append(iou_shortfall)
            iou_errors.append(iou_shortfall)
            if iou_shortfall > 0:
                add_failure(
                    ComparisonFinding(
                        file_id=file_id,
                        metric="face_box_iou",
                        message="Face box IoU below threshold",
                        value=iou,
                        threshold=iou_threshold,
                        severity=STATUS_FAIL,
                    ),
                )

            try:
                landmark_error = _landmark_error(
                    reference_face.landmarks,
                    candidate_face.landmarks,
                )
            except ValueError:
                add_failure(
                    ComparisonFinding(
                        file_id=file_id,
                        metric="landmarks",
                        message="Landmark count mismatch",
                        severity=STATUS_FAIL,
                    ),
                )
            else:
                file_landmark_errors.append(landmark_error)
                landmark_errors.append(landmark_error)
                if landmark_error > thresholds.landmark_error_threshold:
                    add_failure(
                        ComparisonFinding(
                            file_id=file_id,
                            metric="landmark_error",
                            message="Landmark error exceeded threshold",
                            value=landmark_error,
                            threshold=thresholds.landmark_error_threshold,
                            severity=STATUS_FAIL,
                        ),
                    )

            score_delta = abs(reference_face.score - candidate_face.score)
            file_score_deltas.append(score_delta)
            score_deltas.append(score_delta)
            if score_delta > thresholds.score_delta_threshold:
                add_failure(
                    ComparisonFinding(
                        file_id=file_id,
                        metric="score_delta",
                        message="Face score delta exceeded threshold",
                        value=score_delta,
                        threshold=thresholds.score_delta_threshold,
                        severity=STATUS_FAIL,
                    ),
                )

            embedding_status = _threshold_status(
                embedding_distance,
                thresholds.face_embedding_cosine_distance,
                thresholds.face_embedding_warning_cosine_distance,
            )
            if embedding_status == STATUS_WARNING:
                add_warning(
                    ComparisonFinding(
                        file_id=file_id,
                        metric="face_embedding_cosine_distance",
                        message=(
                            "Face embedding cosine distance in warning band "
                            f"({thresholds.face_embedding_cosine_distance:.3f} - "
                            f"{thresholds.face_embedding_warning_cosine_distance:.3f})"
                        ),
                        value=embedding_distance,
                        threshold=thresholds.face_embedding_warning_cosine_distance,
                        severity=STATUS_WARNING,
                    ),
                )
            elif embedding_status == STATUS_FAIL:
                add_failure(
                    ComparisonFinding(
                        file_id=file_id,
                        metric="face_embedding_cosine_distance",
                        message="Face embedding cosine distance exceeded threshold",
                        value=embedding_distance,
                        threshold=thresholds.face_embedding_cosine_distance,
                        severity=STATUS_FAIL,
                    ),
                )

        if file_ious:
            add_file_metric(
                file_id=file_id,
                metric="face_box_iou_min",
                value=min(file_ious),
                threshold=None,
                status=STATUS_PASS,
                passed=True,
                count=len(file_ious),
                message="Minimum IoU across matched faces",
            )
        else:
            add_file_metric(
                file_id=file_id,
                metric="face_box_iou_min",
                value=None,
                threshold=None,
                status=STATUS_PASS if no_faces else STATUS_FAIL,
                passed=no_faces,
                count=0,
                applicable=False,
                message="No matched faces",
            )
        add_matched_max_metric(
            file_id=file_id,
            metric="face_box_iou_shortfall_max",
            values=file_iou_shortfalls,
            threshold=0.0,
            passes_when_empty=no_faces,
            message="Maximum IoU shortfall against configured threshold",
        )
        add_matched_max_metric(
            file_id=file_id,
            metric="landmark_error_max",
            values=file_landmark_errors,
            threshold=thresholds.landmark_error_threshold,
            passes_when_empty=no_faces,
            message="Maximum landmark error across matched faces",
        )
        add_matched_max_metric(
            file_id=file_id,
            metric="score_delta_max",
            values=file_score_deltas,
            threshold=thresholds.score_delta_threshold,
            passes_when_empty=no_faces,
            message="Maximum face score delta across matched faces",
        )
        add_matched_max_metric(
            file_id=file_id,
            metric="face_embedding_cosine_distance_max",
            values=file_embedding_distances,
            threshold=thresholds.face_embedding_cosine_distance,
            passes_when_empty=no_faces,
            warning_threshold=thresholds.face_embedding_warning_cosine_distance,
            message="Maximum face embedding cosine distance across matched faces",
        )

    aggregates = {
        "clip_cosine_distance": _make_aggregate(
            clip_distances,
            clip_threshold,
            warning_threshold=clip_warning_threshold,
        ),
        "face_box_iou_error": _make_aggregate(
            iou_errors,
            0.0,
        ),
        "landmark_error": _make_aggregate(
            landmark_errors,
            thresholds.landmark_error_threshold,
        ),
        "score_delta": _make_aggregate(score_deltas, thresholds.score_delta_threshold),
        "face_embedding_cosine_distance": _make_aggregate(
            face_embedding_distances,
            thresholds.face_embedding_cosine_distance,
            warning_threshold=thresholds.face_embedding_warning_cosine_distance,
        ),
    }

    for metric_name, metric in aggregates.items():
        if metric.status == STATUS_PASS:
            continue
        threshold = metric.warning_threshold if metric.status == STATUS_WARNING else metric.threshold
        add_file_metric(
            file_id=AGGREGATE_FILE_ID,
            metric=metric_name,
            value=metric.max,
            threshold=threshold,
            status=metric.status,
            passed=metric.status != STATUS_FAIL,
            direction="<=",
            count=metric.count,
            applicable=metric.count > 0,
            message="Aggregate threshold gate",
        )
        if metric.status == STATUS_WARNING:
            add_warning(
                ComparisonFinding(
                    file_id=AGGREGATE_FILE_ID,
                    metric=metric_name,
                    message="Aggregate threshold gate in warning band",
                    value=metric.max,
                    threshold=metric.warning_threshold,
                    severity=STATUS_WARNING,
                ),
            )
            continue
        add_failure(
            ComparisonFinding(
                file_id=AGGREGATE_FILE_ID,
                metric=metric_name,
                message="Aggregate threshold gate failed",
                value=metric.max,
                threshold=metric.threshold,
                severity=STATUS_FAIL,
            ),
        )

    report_findings = tuple(findings)
    report_warnings = tuple(warnings)
    sorted_file_ids = sorted(
        set(reference_results)
        | set(file_failures)
        | set(file_warnings)
        | set(file_metrics),
    )
    file_statuses = tuple(
        FileComparisonStatus(
            file_id=file_id,
            status=(
                STATUS_FAIL
                if file_failures[file_id]
                else STATUS_WARNING
                if file_warnings[file_id]
                else STATUS_PASS
            ),
            passed=not file_failures[file_id],
            metrics=tuple(file_metrics[file_id]),
            failures=tuple(file_failures[file_id]),
            warnings=tuple(file_warnings[file_id]),
        )
        for file_id in sorted_file_ids
    )
    passing_files = tuple(
        file_status.file_id
        for file_status in file_statuses
        if (
            file_status.file_id != AGGREGATE_FILE_ID
            and file_status.status == STATUS_PASS
        )
    )
    warning_files = tuple(
        file_status.file_id
        for file_status in file_statuses
        if (
            file_status.file_id != AGGREGATE_FILE_ID
            and file_status.status == STATUS_WARNING
        )
    )
    failing_files = tuple(
        file_status.file_id
        for file_status in file_statuses
        if (
            file_status.file_id != AGGREGATE_FILE_ID
            and file_status.status == STATUS_FAIL
        )
    )
    report_status = (
        STATUS_FAIL
        if report_findings
        else STATUS_WARNING
        if report_warnings
        else STATUS_PASS
    )

    return ComparisonReport(
        reference_platform=reference_platform,
        candidate_platform=candidate_platform,
        total_reference_files=len(reference_results),
        checked_files=len(shared_file_ids),
        missing_files=missing_files,
        extra_files=extra_files,
        aggregates=aggregates,
        findings=report_findings,
        warnings=report_warnings,
        file_statuses=file_statuses,
        passing_files=passing_files,
        warning_files=warning_files,
        failing_files=failing_files,
        status=report_status,
        passed=report_status != STATUS_FAIL,
    )


def compare_platform_matrix(
    platform_results: Mapping[str, Sequence[ParityResult]],
    *,
    ground_truth_platform: str = "python",
    thresholds: ThresholdConfig | None = None,
) -> tuple[ComparisonReport, ...]:
    thresholds = thresholds or ThresholdConfig()

    if ground_truth_platform not in platform_results:
        raise ValueError(f"ground truth platform '{ground_truth_platform}' missing")

    by_platform: dict[str, dict[str, ParityResult]] = {
        platform: _index_results(results, platform=platform)
        for platform, results in platform_results.items()
    }

    reports: list[ComparisonReport] = []
    reference = by_platform[ground_truth_platform]
    non_ground_truth_platforms = [
        platform for platform in by_platform if platform != ground_truth_platform
    ]

    for platform in sorted(non_ground_truth_platforms):
        reports.append(
            compare_result_sets(
                reference_platform=ground_truth_platform,
                candidate_platform=platform,
                reference_results=reference,
                candidate_results=by_platform[platform],
                thresholds=thresholds,
            ),
        )

    return tuple(reports)
