#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from _report_common import (
    PLATFORMS,
    format_generated_timestamp,
    format_value,
    normalize_status,
    optional_bool,
    platform_stats,
    status_label,
    status_rank,
)


def _escape_cell(value: object) -> str:
    text = str(value)
    text = text.replace("|", "\\|")
    text = text.replace("\n", "<br>")
    return text


def _render_platform_outputs(stats: dict[str, dict[str, Any]]) -> list[str]:
    lines = [
        "## Platform Outputs",
        "",
        "| Platform | Output File | Results | Runner Errors | Status |",
        "| --- | --- | ---: | ---: | --- |",
    ]
    for platform in PLATFORMS:
        info = stats[platform]
        status = "generated" if info["available"] else "missing"
        lines.append(
            "| "
            + " | ".join(
                [
                    platform,
                    f"`{_escape_cell(info['path'])}`",
                    _escape_cell(format_value(info.get("result_count"))),
                    _escape_cell(format_value(info.get("error_count"))),
                    status,
                ]
            )
            + " |"
        )
    lines.append("")
    return lines


def _render_aggregate_table(aggregates: dict[str, Any]) -> list[str]:
    lines = [
        (
            "| Metric | Count | P95 | P99 | Max | Threshold | Warning Threshold | "
            "Status |"
        ),
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
    ]
    for metric_name in sorted(aggregates):
        metric = aggregates[metric_name]
        if not isinstance(metric, dict):
            continue
        status = normalize_status(
            metric.get("status"),
            passed=optional_bool(metric.get("passed")),
        )
        lines.append(
            "| "
            + " | ".join(
                [
                    _escape_cell(metric_name),
                    _escape_cell(format_value(metric.get("count"))),
                    _escape_cell(format_value(metric.get("p95"))),
                    _escape_cell(format_value(metric.get("p99"))),
                    _escape_cell(format_value(metric.get("max"))),
                    _escape_cell(format_value(metric.get("threshold"))),
                    _escape_cell(format_value(metric.get("warning_threshold"))),
                    status_label(status),
                ]
            )
            + " |"
        )
    lines.append("")
    return lines


def _render_metric_rows(metrics: list[dict[str, Any]]) -> list[str]:
    lines = [
        "| Metric | Value | Threshold | Direction | Status | Count | Applicable | Note |",
        "| --- | ---: | ---: | --- | --- | ---: | --- | --- |",
    ]
    if not metrics:
        lines.append("| - | - | - | - | - | - | - | No metrics available |")
        lines.append("")
        return lines

    for metric in metrics:
        if not isinstance(metric, dict):
            continue
        status = normalize_status(
            metric.get("status"),
            passed=optional_bool(metric.get("passed")),
        )
        lines.append(
            "| "
            + " | ".join(
                [
                    _escape_cell(metric.get("metric", "-")),
                    _escape_cell(format_value(metric.get("value"))),
                    _escape_cell(format_value(metric.get("threshold"))),
                    _escape_cell(format_value(metric.get("direction"))),
                    status_label(status),
                    _escape_cell(format_value(metric.get("count"))),
                    "yes" if bool(metric.get("applicable", True)) else "no",
                    _escape_cell(metric.get("message", "")),
                ]
            )
            + " |"
        )
    lines.append("")
    return lines


def _render_finding_rows(findings: list[dict[str, Any]]) -> list[str]:
    lines = [
        "| Metric | Value | Threshold | Severity | Message |",
        "| --- | ---: | ---: | --- | --- |",
    ]
    if not findings:
        lines.append("| - | - | - | - | None |")
        lines.append("")
        return lines

    for finding in findings:
        if not isinstance(finding, dict):
            continue
        severity = normalize_status(
            finding.get("severity"),
            passed=optional_bool(finding.get("passed")),
        )
        lines.append(
            "| "
            + " | ".join(
                [
                    _escape_cell(finding.get("metric", "-")),
                    _escape_cell(format_value(finding.get("value"))),
                    _escape_cell(format_value(finding.get("threshold"))),
                    status_label(severity),
                    _escape_cell(finding.get("message", "")),
                ]
            )
            + " |"
        )
    lines.append("")
    return lines


def _render_file_statuses(statuses: list[dict[str, Any]]) -> list[str]:
    lines: list[str] = []
    if not statuses:
        return ["No file-level entries.", ""]

    statuses = sorted(
        statuses,
        key=lambda status: (
            status_rank(
                status.get("status"),
                passed=optional_bool(status.get("passed")),
            ),
            str(status.get("file_id", "")),
        ),
    )

    lines.extend(
        [
            "### File Status Index",
            "",
            "| File | Status | Failure Count | Warning Count |",
            "| --- | --- | ---: | ---: |",
        ]
    )
    for status in statuses:
        if not isinstance(status, dict):
            continue
        file_status = normalize_status(
            status.get("status"),
            passed=optional_bool(status.get("passed")),
        )
        lines.append(
            "| "
            + " | ".join(
                [
                    _escape_cell(status.get("file_id", "-")),
                    status_label(file_status),
                    _escape_cell(format_value(status.get("failure_count"))),
                    _escape_cell(format_value(status.get("warning_count"))),
                ]
            )
            + " |"
        )
    lines.append("")

    lines.append("### File Details")
    lines.append("")
    for status in statuses:
        if not isinstance(status, dict):
            continue
        file_id = str(status.get("file_id", "-"))
        file_status = normalize_status(
            status.get("status"),
            passed=optional_bool(status.get("passed")),
        )
        metrics = status.get("metrics", [])
        if not isinstance(metrics, list):
            metrics = []
        failures = status.get("failures", [])
        if not isinstance(failures, list):
            failures = []
        warnings = status.get("warnings", [])
        if not isinstance(warnings, list):
            warnings = []

        lines.append(f"#### `{file_id}` ({status_label(file_status)})")
        lines.append("")
        lines.append("Metrics:")
        lines.extend(_render_metric_rows(metrics))
        lines.append("Threshold failures:")
        lines.extend(_render_finding_rows(failures))
        lines.append("Threshold warnings:")
        lines.extend(_render_finding_rows(warnings))

    return lines


def _render_comparison(comparison: dict[str, Any]) -> list[str]:
    reference = str(comparison.get("reference_platform", "unknown"))
    candidate = str(comparison.get("candidate_platform", "unknown"))
    file_summary = comparison.get("file_summary") or {}
    if not isinstance(file_summary, dict):
        file_summary = {}

    pass_count = int(file_summary.get("pass_count", 0))
    warning_count = int(file_summary.get("warning_count", 0))
    fail_count = int(file_summary.get("fail_count", 0))
    total_files = int(
        file_summary.get(
            "total_files",
            file_summary.get("total_reference_files", 0),
        )
    )
    reference_total_files = int(
        file_summary.get("total_reference_files", comparison.get("total_reference_files", 0))
    )
    checked_files = int(file_summary.get("checked_files", comparison.get("checked_files", 0)))
    findings = comparison.get("findings", [])
    warnings = comparison.get("warnings", [])
    finding_count = len(findings) if isinstance(findings, list) else 0
    warning_finding_count = len(warnings) if isinstance(warnings, list) else 0
    total_summary = (
        f"{total_files} total files"
        if total_files == reference_total_files
        else f"{total_files} total files ({reference_total_files} reference)"
    )

    lines: list[str] = [
        f"## {candidate} vs {reference}",
        "",
        (
            f"- Summary: {pass_count} pass / {warning_count} warning / {fail_count} fail / "
            f"{total_summary}"
        ),
        f"- Checked files: {checked_files}",
        f"- Threshold findings: {finding_count} fail / {warning_finding_count} warning",
        "",
    ]

    missing_files = comparison.get("missing_files", [])
    if isinstance(missing_files, list) and missing_files:
        lines.append("- Missing files:")
        for file_id in sorted(str(file_id) for file_id in missing_files):
            lines.append(f"  - `{file_id}`")
        lines.append("")

    extra_files = comparison.get("extra_files", [])
    if isinstance(extra_files, list) and extra_files:
        lines.append("- Extra files:")
        for file_id in sorted(str(file_id) for file_id in extra_files):
            lines.append(f"  - `{file_id}`")
        lines.append("")

    aggregates = comparison.get("aggregates", {})
    if isinstance(aggregates, dict) and aggregates:
        lines.append("### Aggregate Metrics")
        lines.append("")
        lines.extend(_render_aggregate_table(aggregates))

    statuses = comparison.get("file_statuses", [])
    if not isinstance(statuses, list):
        statuses = []
    lines.extend(_render_file_statuses(statuses))
    lines.append("")
    return lines


def _render_runner_errors(stats: dict[str, dict[str, Any]]) -> list[str]:
    lines = ["## Runner Errors", ""]
    for platform in ("desktop", "ios", "android", "python"):
        lines.append(f"### {platform}")
        lines.append("")
        info = stats[platform]
        errors = info.get("errors") if info.get("available") else None
        if not errors:
            lines.append("None")
            lines.append("")
            continue
        lines.append("| File | Error |")
        lines.append("| --- | --- |")
        for error in errors:
            if not isinstance(error, dict):
                continue
            lines.append(
                "| "
                + " | ".join(
                    [
                        _escape_cell(error.get("file_id", "-")),
                        _escape_cell(error.get("error", "-")),
                    ]
                )
                + " |"
            )
        lines.append("")
    return lines


def render_report(
    *,
    report_path: Path,
    output_path: Path,
    include_pairwise: bool,
) -> None:
    payload = json.loads(report_path.read_text())
    ground_truth_platform = str(payload.get("ground_truth_platform", "python"))

    comparisons = payload.get("comparisons", [])
    if not isinstance(comparisons, list):
        comparisons = []

    if not include_pairwise:
        comparisons = [
            comparison
            for comparison in comparisons
            if isinstance(comparison, dict)
            and str(comparison.get("reference_platform", "")) == ground_truth_platform
        ]

    comparisons = sorted(
        (comparison for comparison in comparisons if isinstance(comparison, dict)),
        key=lambda comparison: (
            str(comparison.get("reference_platform", "")),
            str(comparison.get("candidate_platform", "")),
        ),
    )

    stats = platform_stats(report_path.parent)
    generated_at = format_generated_timestamp(payload.get("generated_at"))

    lines: list[str] = [
        "# ML Indexing Parity Report (LLM-Optimized Markdown)",
        "",
        f"- Generated (IST): {generated_at}",
        f"- Ground truth platform: {ground_truth_platform}",
        f"- Comparisons shown: {len(comparisons)}",
        "",
        "This report is structured for agent parsing and includes exhaustive file-level data.",
        "",
    ]

    lines.extend(_render_platform_outputs(stats))

    if not comparisons:
        lines.extend(["## Comparisons", "", "No comparisons available.", ""])
    else:
        lines.append("## Comparisons")
        lines.append("")
        for comparison in comparisons:
            lines.extend(_render_comparison(comparison))

    lines.extend(_render_runner_errors(stats))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines))


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Render an LLM-friendly Markdown report from ML parity comparison JSON.",
    )
    parser.add_argument(
        "--report",
        required=True,
        help="Path to comparison_report.json",
    )
    parser.add_argument(
        "--output",
        help="Output Markdown path (default: <report_dir>/parity_report.llm.md)",
    )
    parser.add_argument(
        "--include-pairwise",
        action="store_true",
        help="Include non-ground-truth pairwise comparisons in the report.",
    )
    args = parser.parse_args()

    report_path = Path(args.report)
    if args.output:
        output_path = Path(args.output)
    else:
        output_path = report_path.parent / "parity_report.llm.md"

    render_report(
        report_path=report_path,
        output_path=output_path,
        include_pairwise=args.include_pairwise,
    )
    print(output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
