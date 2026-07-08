#!/usr/bin/env python3
from __future__ import annotations

import argparse
import html
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


def _render_comparison(comparison: dict[str, Any]) -> str:
    reference = str(comparison.get("reference_platform", "unknown"))
    candidate = str(comparison.get("candidate_platform", "unknown"))
    file_summary = comparison.get("file_summary") or {}
    pass_count = int(file_summary.get("pass_count", 0))
    warning_count = int(file_summary.get("warning_count", 0))
    fail_count = int(file_summary.get("fail_count", 0))
    total_files = int(
        file_summary.get(
            "total_files",
            file_summary.get("total_reference_files", 0),
        )
    )
    findings = comparison.get("findings", [])
    warnings = comparison.get("warnings", [])
    finding_count = len(findings) if isinstance(findings, list) else 0
    warning_finding_count = len(warnings) if isinstance(warnings, list) else 0

    html_parts: list[str] = []
    html_parts.append(f"<h2>{html.escape(candidate)} vs {html.escape(reference)}</h2>")
    html_parts.append(
        "<table><thead><tr><th>Pass</th><th>Warning</th><th>Fail</th><th>Total</th>"
        "<th>Findings</th></tr></thead><tbody>"
    )
    html_parts.append(
        "<tr>"
        f"<td class='pass'>{pass_count}</td>"
        f"<td class='warning'>{warning_count}</td>"
        f"<td class='fail'>{fail_count}</td>"
        f"<td>{total_files}</td>"
        f"<td>{finding_count} fail / {warning_finding_count} warning</td>"
        "</tr>"
    )
    html_parts.append("</tbody></table>")

    missing_files = comparison.get("missing_files", [])
    extra_files = comparison.get("extra_files", [])
    if isinstance(missing_files, list) and missing_files:
        html_parts.append("<p><strong>Missing files:</strong> " + ", ".join(html.escape(str(value)) for value in missing_files) + "</p>")
    if isinstance(extra_files, list) and extra_files:
        html_parts.append("<p><strong>Extra files:</strong> " + ", ".join(html.escape(str(value)) for value in extra_files) + "</p>")

    statuses = comparison.get("file_statuses", [])
    if not isinstance(statuses, list):
        statuses = []

    rows: list[dict[str, Any]] = []
    for status in statuses:
        if not isinstance(status, dict):
            continue
        rows.append(status)

    rows.sort(
        key=lambda row: (
            status_rank(
                row.get("status"),
                passed=optional_bool(row.get("passed")),
            ),
            str(row.get("file_id", "")),
        )
    )

    html_parts.append("<h3>Files</h3>")
    if not rows:
        html_parts.append("<p class='muted'>No file-level entries.</p>")
        return "".join(html_parts)

    for status in rows:
        file_id = str(status.get("file_id", ""))
        file_status = normalize_status(
            status.get("status"),
            passed=optional_bool(status.get("passed")),
        )
        failures = status.get("failures", [])
        if not isinstance(failures, list):
            failures = []
        warnings = status.get("warnings", [])
        if not isinstance(warnings, list):
            warnings = []
        metrics = status.get("metrics", [])
        if not isinstance(metrics, list):
            metrics = []

        html_parts.append(
            f"<details><summary>{html.escape(file_id)} "
            f"<span class='{normalize_status(file_status)}'>{status_label(file_status)}</span> "
            f"(fail: {len(failures)}, warning: {len(warnings)})"
            "</summary>"
        )

        html_parts.append(
            "<table><thead><tr>"
            "<th>Metric</th><th>Value</th><th>Threshold</th><th>Direction</th>"
            "<th>Status</th><th>Count</th><th>Applicable</th><th>Note</th>"
            "</tr></thead><tbody>"
        )
        if metrics:
            for metric in metrics:
                if not isinstance(metric, dict):
                    continue
                metric_name = html.escape(str(metric.get("metric", "-")))
                value = html.escape(format_value(metric.get("value")))
                threshold = html.escape(format_value(metric.get("threshold")))
                direction = html.escape(format_value(metric.get("direction")))
                metric_status = normalize_status(
                    metric.get("status"),
                    passed=optional_bool(metric.get("passed")),
                )
                count = html.escape(format_value(metric.get("count")))
                applicable = bool(metric.get("applicable", True))
                message = html.escape(str(metric.get("message", "")))
                html_parts.append(
                    "<tr>"
                    f"<td>{metric_name}</td>"
                    f"<td>{value}</td>"
                    f"<td>{threshold}</td>"
                    f"<td>{direction}</td>"
                    f"<td class='{normalize_status(metric_status)}'>{status_label(metric_status)}</td>"
                    f"<td>{count}</td>"
                    f"<td>{'yes' if applicable else 'no'}</td>"
                    f"<td>{message}</td>"
                    "</tr>"
                )
        else:
            html_parts.append(
                "<tr><td colspan='8' class='muted'>No metrics available in report for this file.</td></tr>"
            )
        html_parts.append("</tbody></table>")

        html_parts.append("<h4>Threshold Failures</h4>")
        html_parts.append(
            "<table><thead><tr><th>Metric</th><th>Value</th><th>Threshold</th>"
            "<th>Severity</th><th>Message</th></tr></thead><tbody>"
        )
        if failures:
            for failure in failures:
                if not isinstance(failure, dict):
                    continue
                severity = normalize_status(
                    failure.get("severity"),
                    passed=optional_bool(failure.get("passed")),
                )
                html_parts.append(
                    "<tr>"
                    f"<td>{html.escape(str(failure.get('metric', '-')))}</td>"
                    f"<td>{html.escape(format_value(failure.get('value')))}</td>"
                    f"<td>{html.escape(format_value(failure.get('threshold')))}</td>"
                    f"<td class='{normalize_status(severity)}'>{status_label(severity)}</td>"
                    f"<td>{html.escape(str(failure.get('message', '')))}</td>"
                    "</tr>"
                )
        else:
            html_parts.append("<tr><td colspan='5' class='muted'>None</td></tr>")
        html_parts.append("</tbody></table>")

        html_parts.append("<h4>Threshold Warnings</h4>")
        html_parts.append(
            "<table><thead><tr><th>Metric</th><th>Value</th><th>Threshold</th>"
            "<th>Severity</th><th>Message</th></tr></thead><tbody>"
        )
        if warnings:
            for warning in warnings:
                if not isinstance(warning, dict):
                    continue
                severity = normalize_status(
                    warning.get("severity"),
                    passed=optional_bool(warning.get("passed")),
                )
                html_parts.append(
                    "<tr>"
                    f"<td>{html.escape(str(warning.get('metric', '-')))}</td>"
                    f"<td>{html.escape(format_value(warning.get('value')))}</td>"
                    f"<td>{html.escape(format_value(warning.get('threshold')))}</td>"
                    f"<td class='{normalize_status(severity)}'>{status_label(severity)}</td>"
                    f"<td>{html.escape(str(warning.get('message', '')))}</td>"
                    "</tr>"
                )
        else:
            html_parts.append("<tr><td colspan='5' class='muted'>None</td></tr>")
        html_parts.append("</tbody></table>")

        html_parts.append("</details>")

    return "".join(html_parts)


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

    report_dir = report_path.parent
    stats = platform_stats(report_dir)
    generated_at = format_generated_timestamp(payload.get("generated_at"))

    html_parts: list[str] = []
    html_parts.append("<!doctype html><html><head><meta charset='utf-8'><title>ML Indexing Parity Report</title>")
    html_parts.append(
        "<style>"
        "body{font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif;margin:20px;line-height:1.35;color:#111827;}"
        "h1,h2,h3,h4{margin:14px 0 8px;}"
        "table{border-collapse:collapse;width:100%;margin:8px 0 14px;table-layout:fixed;}"
        "th,td{border:1px solid #d0d5dd;padding:8px;vertical-align:top;overflow-wrap:anywhere;word-break:break-word;}"
        "th{background:#f9fafb;text-align:left;}"
        "details{margin:10px 0;border:1px solid #e4e7ec;border-radius:8px;padding:8px 10px;background:#fff;}"
        "summary{cursor:pointer;font-weight:600;}"
        ".pass{color:#067647;font-weight:600;}"
        ".warning{color:#b54708;font-weight:600;}"
        ".fail{color:#b42318;font-weight:600;}"
        ".muted{color:#667085;}"
        ".chip{display:inline-block;padding:3px 8px;border-radius:999px;background:#f2f4f7;margin-right:6px;font-size:12px;}"
        "</style>"
    )
    html_parts.append("</head><body>")

    html_parts.append("<h1>ML Indexing Parity Report</h1>")
    html_parts.append(
        f"<p><span class='chip'>Generated (IST): {html.escape(generated_at)}</span>"
        f"<span class='chip'>Ground truth: {html.escape(ground_truth_platform)}</span>"
        f"<span class='chip'>Comparisons shown: {len(comparisons)}</span></p>"
    )

    html_parts.append("<h2>Platform Outputs</h2>")
    html_parts.append("<table><thead><tr><th>Platform</th><th>Output File</th><th>Results</th><th>Runner Errors</th><th>Status</th></tr></thead><tbody>")
    for platform in PLATFORMS:
        info = stats[platform]
        status_text = "generated" if info["available"] else "missing"
        status_class = "pass" if info["available"] else "fail"
        results = format_value(info.get("result_count"))
        errors = format_value(info.get("error_count"))
        html_parts.append(
            "<tr>"
            f"<td>{html.escape(platform)}</td>"
            f"<td><code>{html.escape(info['path'])}</code></td>"
            f"<td>{html.escape(results)}</td>"
            f"<td>{html.escape(errors)}</td>"
            f"<td class='{status_class}'>{status_text}</td>"
            "</tr>"
        )
    html_parts.append("</tbody></table>")

    if not comparisons:
        html_parts.append("<p class='muted'>No comparisons available.</p>")
    else:
        comparisons = sorted(
            comparisons,
            key=lambda comparison: (
                str(comparison.get("reference_platform", "")),
                str(comparison.get("candidate_platform", "")),
            ),
        )
        for comparison in comparisons:
            if not isinstance(comparison, dict):
                continue
            html_parts.append(_render_comparison(comparison))

    html_parts.append("<h2>Runner Errors</h2>")
    for platform in ("desktop", "ios", "android", "python"):
        info = stats[platform]
        html_parts.append(f"<h3>{html.escape(platform)}</h3>")
        errors = info.get("errors") if info.get("available") else None
        if not errors:
            html_parts.append("<p class='muted'>None</p>")
            continue
        html_parts.append("<table><thead><tr><th>File</th><th>Error</th></tr></thead><tbody>")
        for error in errors:
            if not isinstance(error, dict):
                continue
            html_parts.append(
                "<tr>"
                f"<td>{html.escape(str(error.get('file_id', '-')))}</td>"
                f"<td>{html.escape(str(error.get('error', '-')))}</td>"
                "</tr>"
            )
        html_parts.append("</tbody></table>")

    html_parts.append("</body></html>")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("".join(html_parts))


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Render a readable HTML report from ML parity comparison JSON.",
    )
    parser.add_argument(
        "--report",
        required=True,
        help="Path to comparison_report.json",
    )
    parser.add_argument(
        "--output",
        help="Output HTML path (default: <report_dir>/parity_report.html)",
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
        output_path = report_path.parent / "parity_report.html"

    render_report(
        report_path=report_path,
        output_path=output_path,
        include_pairwise=args.include_pairwise,
    )
    print(output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
