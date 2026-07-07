#!/usr/bin/env python3
from __future__ import annotations

import argparse
from datetime import UTC, datetime
import json
from pathlib import Path
from typing import Any

import _paths  # noqa: F401  # puts the ML test dir on sys.path

from comparator.compare import (
    AGGREGATE_FILE_ID,
    ThresholdConfig,
    compare_platform_matrix,
)
from ground_truth.schema import load_results_document


def _load_results(path: Path) -> tuple[str | None, tuple[Any, ...]]:
    payload = json.loads(path.read_text())
    platform = payload.get("platform") if isinstance(payload, dict) else None
    return platform, load_results_document(payload)


def _finding_counts(report_findings: tuple[Any, ...]) -> tuple[int, int]:
    file_count = sum(
        1
        for finding in report_findings
        if getattr(finding, "file_id", "") != AGGREGATE_FILE_ID
    )
    return file_count, len(report_findings) - file_count


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compare platform ML indexing results against Python ground truth.",
    )
    parser.add_argument(
        "--ground-truth",
        required=True,
        help="Path to a JSON file containing Python ground truth results.",
    )
    parser.add_argument(
        "--platform-result",
        action="append",
        default=[],
        metavar="platform=path",
        help="Platform result to compare, for example android=out/android/results.json.",
    )
    parser.add_argument(
        "--output",
        help="Optional path to write machine-readable comparison JSON.",
    )
    parser.add_argument(
        "--fail-on-any-file-failure",
        action="store_true",
        help=(
            "Exit non-zero when any compared file fails thresholds. "
            "By default, this command reports file-level failures but exits zero."
        ),
    )
    args = parser.parse_args()

    ground_truth_path = Path(args.ground_truth)
    ground_truth_platform, ground_truth_results = _load_results(ground_truth_path)
    if not ground_truth_platform:
        ground_truth_platform = "python"

    platform_results = {ground_truth_platform: ground_truth_results}
    for platform_result in args.platform_result:
        if "=" not in platform_result:
            raise ValueError(
                f"Invalid --platform-result value '{platform_result}'. Use platform=path."
            )
        platform, path = platform_result.split("=", 1)
        _, results = _load_results(Path(path))
        platform_results[platform] = results

    thresholds = ThresholdConfig()
    reports = compare_platform_matrix(
        platform_results,
        ground_truth_platform=ground_truth_platform,
        thresholds=thresholds,
    )

    overall_status = (
        "fail"
        if any(report.status == "fail" for report in reports)
        else "warning"
        if any(report.status == "warning" for report in reports)
        else "pass"
    )
    all_files_passed = all(report.passed for report in reports)
    output_payload = {
        "generated_at": datetime.now(UTC).isoformat(),
        "ground_truth_platform": ground_truth_platform,
        "thresholds": thresholds.to_dict(),
        "all_files_passed": all_files_passed,
        "status": overall_status,
        "passed": all_files_passed,
        "comparisons": [report.to_dict() for report in reports],
    }

    if args.output:
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(output_payload, indent=2, sort_keys=True))

    failed_reports = [report for report in reports if report.status == "fail"]
    warning_reports = [report for report in reports if report.status == "warning"]
    print(f"Comparisons executed: {len(reports)}")
    print("Comparison mode: file-level (no global pass/fail gate)")
    print(f"Overall comparison status: {overall_status.upper()}")
    for report in reports:
        print(
            f"  {report.reference_platform} -> {report.candidate_platform}: "
            f"{len(report.passing_files)} pass, "
            f"{len(report.warning_files)} warning, "
            f"{len(report.failing_files)} fail "
            f"(total: {report.total_reference_files})"
        )
    if failed_reports:
        print("Comparisons with failing findings:")
        for report in failed_reports:
            file_findings, aggregate_findings = _finding_counts(report.findings)
            print(
                f"  {report.reference_platform} -> {report.candidate_platform} "
                f"({file_findings} file findings, "
                f"{aggregate_findings} aggregate findings)"
            )
    if warning_reports:
        print("Comparisons with warning findings:")
        for report in warning_reports:
            file_warnings, aggregate_warnings = _finding_counts(report.warnings)
            print(
                f"  {report.reference_platform} -> {report.candidate_platform} "
                f"({file_warnings} file warnings, "
                f"{aggregate_warnings} aggregate warnings)"
            )

    if args.fail_on_any_file_failure and failed_reports:
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
