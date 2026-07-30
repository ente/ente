"""Helpers shared by the parity report renderers.

Stdlib-only: the renderers are invoked with the system `python3` by
`run_ml_parity_tests.sh`.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
from typing import Any

IST = timezone(timedelta(hours=5, minutes=30), name="IST")
STATUS_ORDER = {"fail": 0, "warning": 1, "pass": 2}
PLATFORMS = ("python", "desktop", "android", "ios")
AGGREGATE_FILE_ID = "*aggregate*"


def format_value(value: object) -> str:
    if isinstance(value, float):
        return f"{value:.6f}"
    if isinstance(value, int):
        return str(value)
    if value is None:
        return "-"
    return str(value)


def optional_bool(value: object) -> bool | None:
    return value if isinstance(value, bool) else None


def normalize_status(value: object, *, passed: bool | None = None) -> str:
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in STATUS_ORDER:
            return normalized
    if passed is not None:
        return "pass" if passed else "fail"
    return "fail"


def status_label(value: object, *, passed: bool | None = None) -> str:
    return normalize_status(value, passed=passed).upper()


def status_rank(value: object, *, passed: bool | None = None) -> int:
    return STATUS_ORDER[normalize_status(value, passed=passed)]


def count_file_findings(findings: object) -> int:
    if not isinstance(findings, list):
        return 0
    return sum(
        1
        for finding in findings
        if (
            isinstance(finding, dict)
            and str(finding.get("file_id", "")) != AGGREGATE_FILE_ID
        )
    )


def format_generated_timestamp(value: object) -> str:
    if value is None:
        return "-"

    raw = str(value).strip()
    if not raw:
        return "-"

    normalized = raw[:-1] + "+00:00" if raw.endswith("Z") else raw
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return raw

    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(IST).strftime("%Y-%m-%d %H:%M:%S")


def platform_stats(report_dir: Path) -> dict[str, dict[str, Any]]:
    stats: dict[str, dict[str, Any]] = {}
    for platform in PLATFORMS:
        path = report_dir / platform / "results.json"
        if not path.exists():
            stats[platform] = {
                "path": str(path),
                "available": False,
                "result_count": None,
                "error_count": None,
                "errors": [],
            }
            continue

        payload = json.loads(path.read_text())
        results = payload.get("results", [])
        errors = payload.get("errors", [])
        stats[platform] = {
            "path": str(path),
            "available": True,
            "result_count": len(results) if isinstance(results, list) else None,
            "error_count": len(errors) if isinstance(errors, list) else None,
            "errors": errors if isinstance(errors, list) else [],
        }

    return stats
