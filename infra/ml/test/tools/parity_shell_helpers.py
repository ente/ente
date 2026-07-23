#!/usr/bin/env python3
"""Stdlib-only subcommands for run_ml_parity_tests.sh.

Each subcommand was extracted from an inline python3 heredoc in the shell
script; bodies and exit codes are preserved. Runs under the system python3.
"""
from __future__ import annotations

import base64
from collections import OrderedDict
import hashlib
import json
from pathlib import Path
import re
import socket
import subprocess
import sys
import time
from urllib.parse import quote


def cmd_b64_file(args: list[str]) -> None:
    manifest_path = Path(args[0])
    print(base64.b64encode(manifest_path.read_bytes()).decode("ascii"))


def cmd_sha256_file(args: list[str]) -> None:
    digest = hashlib.sha256()
    with open(args[0], "rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    print(digest.hexdigest())


def cmd_reserve_port(args: list[str]) -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
    sock.close()


def cmd_manifest_fixtures(args: list[str]) -> None:
    manifest = json.loads(Path(args[0]).read_text())
    for item in manifest.get("items", []):
        source = str(item.get("source", "")).strip()
        source_url = str(item.get("source_url", "")).strip()
        source_sha = str(item.get("source_sha256", "")).strip()
        print(f"{source}\t{source_url}\t{source_sha}")


def cmd_model_assets(args: list[str]) -> None:
    asset_lock = json.loads(Path(args[0]).read_text())
    for model in asset_lock.get("models", {}).values():
        file_name = str(model.get("file_name", "")).strip()
        url = str(model.get("url", "")).strip()
        sha256 = str(model.get("sha256", "")).strip()
        print(f"{file_name}\t{url}\t{sha256}")


def cmd_file_url(args: list[str]) -> None:
    posix_path = Path(args[0]).resolve().as_posix()
    if not posix_path.startswith("/"):
        posix_path = "/" + posix_path
    print("file://" + quote(posix_path, safe="/:._-~"))


def cmd_pick_device(args: list[str]) -> None:
    platform = args[0]
    requested_device_id = args[1] if len(args) > 1 else ""

    def command_output(command: list[str]) -> str | None:
        try:
            return subprocess.check_output(command, stderr=subprocess.STDOUT, text=True)
        except Exception:
            return None

    def command_json(command: list[str]) -> object | None:
        output = command_output(command)
        if output is None:
            return None
        try:
            return json.loads(output)
        except json.JSONDecodeError:
            return None

    raw = command_output(["flutter", "devices", "--machine"])
    if raw is None:
        sys.exit(2)

    try:
        devices = json.loads(raw)
    except json.JSONDecodeError:
        sys.exit(2)

    if not isinstance(devices, list):
        sys.exit(2)

    def is_match(device: dict[str, object]) -> bool:
        target = str(device.get("targetPlatform", "")).lower()
        name = str(device.get("name", "")).lower()
        if platform == "android":
            return "android" in target or "android" in name
        if platform == "ios":
            return "ios" in target or "iphone" in name or "ipad" in name
        return False

    def ios_simulator_metadata() -> dict[str, dict[str, object]]:
        payload = command_json(["xcrun", "simctl", "list", "devices", "--json"])
        if not isinstance(payload, dict):
            return {}
        devices_by_runtime = payload.get("devices", {})
        if not isinstance(devices_by_runtime, dict):
            return {}

        metadata: dict[str, dict[str, object]] = {}
        for simulator_list in devices_by_runtime.values():
            if not isinstance(simulator_list, list):
                continue
            for simulator in simulator_list:
                if not isinstance(simulator, dict):
                    continue
                udid = str(simulator.get("udid", "")).strip()
                if not udid:
                    continue
                metadata[udid] = {
                    "is_available": bool(simulator.get("isAvailable", True)),
                    "is_booted": str(simulator.get("state", "")).strip().lower() == "booted",
                }
        return metadata

    def ios_physical_available_ids() -> set[str]:
        payload = command_json(["xcrun", "xcdevice", "list"])
        if not isinstance(payload, list):
            return set()

        available_ids: set[str] = set()
        for device in payload:
            if not isinstance(device, dict):
                continue
            if bool(device.get("simulator", False)):
                continue
            identifier = str(device.get("identifier", "")).strip()
            if not identifier:
                continue
            if bool(device.get("available", False)):
                available_ids.add(identifier)
        return available_ids

    def android_device_states() -> dict[str, str]:
        adb_output = command_output(["adb", "devices"])
        if adb_output is None:
            return {}

        states: dict[str, str] = {}
        for line in adb_output.splitlines()[1:]:
            parts = line.strip().split()
            if len(parts) >= 2:
                states[parts[0]] = parts[1]
        return states

    ios_simulators = ios_simulator_metadata() if platform == "ios" else {}
    ios_physical_ids = ios_physical_available_ids() if platform == "ios" else set()
    android_states = android_device_states() if platform == "android" else {}
    android_state_probe_attempted = platform == "android"

    candidates: list[tuple[tuple[int, str, int], str]] = []
    for index, device in enumerate(devices):
        if not isinstance(device, dict):
            continue
        if not is_match(device):
            continue
        if not bool(device.get("isSupported", True)):
            continue

        identifier = str(device.get("id", "")).strip()
        if not identifier:
            continue

        name = str(device.get("name", "")).strip().lower()
        is_emulator = bool(device.get("emulator", False))

        if platform == "ios":
            if is_emulator:
                simulator = ios_simulators.get(identifier)
                if simulator is not None:
                    if not bool(simulator.get("is_available", True)):
                        continue
                    score = 0 if bool(simulator.get("is_booted", False)) else 1
                else:
                    # Keep flutter-visible simulators even when simctl metadata is unavailable.
                    score = 2
            else:
                if ios_physical_ids and identifier not in ios_physical_ids:
                    continue
                score = 10
        elif platform == "android":
            if android_states:
                if android_states.get(identifier) != "device":
                    continue
            elif android_state_probe_attempted:
                # adb unavailable/unreadable; keep flutter-visible devices as fallback.
                pass

            if is_emulator or identifier.startswith("emulator-"):
                score = 0
            else:
                score = 1
        else:
            continue

        candidates.append(((score, name, index), identifier))

    if requested_device_id:
        for _, identifier in candidates:
            if identifier == requested_device_id:
                print(identifier)
                sys.exit(0)
        sys.exit(1)

    if not candidates:
        sys.exit(1)

    candidates.sort(key=lambda item: item[0])
    print(candidates[0][1])
    sys.exit(0)


def cmd_pick_ios_simulator(args: list[str]) -> None:
    preferred_udid = args[0] if args else ""

    try:
        raw = subprocess.check_output(
            ["xcrun", "simctl", "list", "devices", "available", "--json"],
            stderr=subprocess.STDOUT,
            text=True,
        )
        payload = json.loads(raw)
    except Exception:
        sys.exit(2)

    devices_by_runtime = payload.get("devices", {})
    candidates: list[tuple[tuple[object, ...], str]] = []

    for runtime, devices in devices_by_runtime.items():
        runtime_lower = str(runtime).lower()
        if "ios" not in runtime_lower:
            continue
        if any(blocked in runtime_lower for blocked in ("tvos", "watchos", "visionos")):
            continue

        for device in devices:
            if not bool(device.get("isAvailable", True)):
                continue

            udid = str(device.get("udid", "")).strip()
            if not udid:
                continue

            name = str(device.get("name", "")).strip()
            state = str(device.get("state", "")).strip().lower()

            score = (
                0 if state == "booted" else 1,
                0 if "iphone" in name.lower() else 1,
                name.lower(),
                udid.lower(),
            )
            candidates.append((score, udid))

    if preferred_udid:
        for _, udid in candidates:
            if udid == preferred_udid:
                print(udid)
                sys.exit(0)

    if not candidates:
        sys.exit(1)

    candidates.sort(key=lambda entry: entry[0])
    print(candidates[0][1])


def cmd_wait_ios_boot(args: list[str]) -> None:
    udid = args[0]
    timeout_seconds = float(args[1])
    deadline = time.time() + timeout_seconds

    while time.time() < deadline:
        try:
            raw = subprocess.check_output(
                ["xcrun", "simctl", "list", "devices", "--json"],
                stderr=subprocess.STDOUT,
                text=True,
            )
            payload = json.loads(raw)
        except Exception:
            time.sleep(2.0)
            continue

        for devices in payload.get("devices", {}).values():
            for device in devices:
                if str(device.get("udid", "")).strip() != udid:
                    continue
                state = str(device.get("state", "")).strip().lower()
                if state == "booted":
                    sys.exit(0)
                break
        time.sleep(2.0)

    sys.exit(1)


def cmd_is_ios_simulator_udid(args: list[str]) -> None:
    device_id = args[0]

    try:
        raw = subprocess.check_output(
            ["xcrun", "simctl", "list", "devices", "--json"],
            stderr=subprocess.STDOUT,
            text=True,
        )
        payload = json.loads(raw)
    except Exception:
        sys.exit(1)

    for devices in payload.get("devices", {}).values():
        for device in devices:
            if str(device.get("udid", "")).strip() == device_id:
                sys.exit(0)
    sys.exit(1)


def cmd_list_android_emulators(args: list[str]) -> None:
    adb_bin = args[0]
    emulator_line = re.compile(r"^(emulator-\d+)\s+\S+$")

    try:
        output = subprocess.check_output(
            [adb_bin, "devices"],
            stderr=subprocess.STDOUT,
            text=True,
        )
    except Exception:
        sys.exit(0)

    for line in output.splitlines()[1:]:
        match = emulator_line.match(line.strip())
        if match:
            print(match.group(1))


def cmd_wait_android_boot(args: list[str]) -> None:
    adb_bin = args[0]
    timeout_seconds = float(args[1])
    existing_serials = {value for value in args[2].split(",") if value}
    deadline = time.time() + timeout_seconds
    emulator_line = re.compile(r"^(emulator-\d+)\s+device$")

    while time.time() < deadline:
        try:
            output = subprocess.check_output(
                [adb_bin, "devices"],
                stderr=subprocess.STDOUT,
                text=True,
            )
        except Exception:
            time.sleep(2.0)
            continue

        serials: list[str] = []
        for line in output.splitlines()[1:]:
            match = emulator_line.match(line.strip())
            if match:
                serials.append(match.group(1))

        for serial in serials:
            if serial in existing_serials:
                continue

            try:
                boot_completed = (
                    subprocess.check_output(
                        [adb_bin, "-s", serial, "shell", "getprop", "sys.boot_completed"],
                        stderr=subprocess.DEVNULL,
                        text=True,
                        timeout=5,
                    )
                    .strip()
                    .replace("\r", "")
                )
            except Exception:
                continue

            if boot_completed == "1":
                print(serial)
                sys.exit(0)

        time.sleep(2.0)

    sys.exit(1)


LOWER_IS_WORSE_METRICS = {"face_box_iou"}
STATUS_ORDER = {"FAIL": 0, "WARNING": 1, "PASS": 2}


def _fmt_float(value: float) -> str:
    return f"{value:.6f}"


def _summarize_metric_failures(metric: str, failures: list[dict[str, object]]) -> str:
    numeric_values = [
        float(value)
        for value in (failure.get("value") for failure in failures)
        if isinstance(value, (int, float))
    ]
    threshold_values = [
        float(threshold)
        for threshold in (failure.get("threshold") for failure in failures)
        if isinstance(threshold, (int, float))
    ]
    threshold = threshold_values[0] if threshold_values else None
    occurrence_count = len(failures)

    if numeric_values:
        if metric in LOWER_IS_WORSE_METRICS:
            worst_value = min(numeric_values)
            if threshold is None:
                return (
                    f"{metric} x{occurrence_count}: "
                    f"worst={_fmt_float(worst_value)}"
                )
            shortfall = threshold - worst_value
            return (
                f"{metric} x{occurrence_count}: "
                f"worst={_fmt_float(worst_value)} < {_fmt_float(threshold)} "
                f"(shortfall {_fmt_float(shortfall)})"
            )

        worst_value = max(numeric_values)
        if threshold is None:
            return (
                f"{metric} x{occurrence_count}: "
                f"worst={_fmt_float(worst_value)}"
            )
        overshoot = worst_value - threshold
        return (
            f"{metric} x{occurrence_count}: "
            f"worst={_fmt_float(worst_value)} > {_fmt_float(threshold)} "
            f"(overshoot {_fmt_float(overshoot)})"
        )

    message = str(failures[0].get("message", "threshold violation"))
    return f"{metric} x{occurrence_count}: {message}"


def _summarize_file_failures(failures: list[dict[str, object]]) -> str:
    if not failures:
        return "-"

    by_metric: "OrderedDict[str, list[dict[str, object]]]" = OrderedDict()
    for failure in failures:
        metric = str(failure.get("metric", "unknown_metric"))
        by_metric.setdefault(metric, []).append(failure)

    return "; ".join(
        _summarize_metric_failures(metric, metric_failures)
        for metric, metric_failures in by_metric.items()
    )


def _summarize_file_warnings(warnings: list[dict[str, object]]) -> str:
    if not warnings:
        return "-"

    by_metric: "OrderedDict[str, list[dict[str, object]]]" = OrderedDict()
    for warning in warnings:
        metric = str(warning.get("metric", "unknown_metric"))
        by_metric.setdefault(metric, []).append(warning)

    summaries: list[str] = []
    for metric, metric_warnings in by_metric.items():
        occurrence_count = len(metric_warnings)
        message = str(metric_warnings[0].get("message", "threshold warning"))
        summaries.append(f"{metric} x{occurrence_count}: {message}")
    return "; ".join(summaries)


def _escape_cell(value: str) -> str:
    return value.replace("|", "\\|")


def cmd_file_level_tables(args: list[str]) -> None:
    report_path = Path(args[0])
    if not report_path.exists():
        print(f"Comparison report not found at {report_path}")
        raise SystemExit(0)

    payload = json.loads(report_path.read_text())
    ground_truth_platform = str(payload.get("ground_truth_platform", "python"))
    comparisons = payload.get("comparisons", [])
    if not isinstance(comparisons, list) or not comparisons:
        print("No platform comparisons were generated.")
        raise SystemExit(0)

    printed_any_table = False
    for comparison in comparisons:
        if not isinstance(comparison, dict):
            continue
        if comparison.get("reference_platform") != ground_truth_platform:
            continue

        candidate_platform = str(comparison.get("candidate_platform", "unknown"))
        file_summary = comparison.get("file_summary") or {}
        if not isinstance(file_summary, dict):
            file_summary = {}
        total_files = int(
            file_summary.get(
                "total_files",
                file_summary.get("total_reference_files", comparison.get("total_reference_files", 0)),
            )
        )
        pass_count = int(file_summary.get("pass_count", len(comparison.get("passing_files", []))))
        warning_count = int(file_summary.get("warning_count", len(comparison.get("warning_files", []))))
        fail_count = int(file_summary.get("fail_count", len(comparison.get("failing_files", []))))

        file_statuses = comparison.get("file_statuses", [])
        if not isinstance(file_statuses, list):
            file_statuses = []

        rows: list[tuple[str, str, str]] = []
        if file_statuses:
            for file_status in file_statuses:
                if not isinstance(file_status, dict):
                    continue
                file_id = str(file_status.get("file_id", ""))
                status_value = str(file_status.get("status", "")).strip().upper()
                if status_value not in STATUS_ORDER:
                    status_value = "PASS" if bool(file_status.get("passed", False)) else "FAIL"
                failures = file_status.get("failures", [])
                if not isinstance(failures, list):
                    failures = []
                warnings = file_status.get("warnings", [])
                if not isinstance(warnings, list):
                    warnings = []
                if status_value == "FAIL":
                    details = _summarize_file_failures(failures)
                elif status_value == "WARNING":
                    details = _summarize_file_warnings(warnings)
                else:
                    details = "-"
                rows.append((file_id, status_value, details))
        else:
            passing_files = [str(file_id) for file_id in comparison.get("passing_files", [])]
            warning_files = [str(file_id) for file_id in comparison.get("warning_files", [])]
            failing_files = [str(file_id) for file_id in comparison.get("failing_files", [])]
            for file_id in passing_files:
                rows.append((file_id, "PASS", "-"))
            for file_id in warning_files:
                rows.append((file_id, "WARNING", "No warning detail available in report"))
            for file_id in failing_files:
                rows.append((file_id, "FAIL", "No failure detail available in report"))

        if not rows:
            continue

        rows.sort(key=lambda row: (STATUS_ORDER.get(row[1], 3), row[0]))

        print()
        print(
            f"### {candidate_platform} vs {ground_truth_platform} "
            f"({pass_count} pass / {warning_count} warning / {fail_count} fail / {total_files} total)"
        )
        print("| File | Status | Details |")
        print("| --- | --- | --- |")
        for file_id, status, details in rows:
            print(
                "| "
                + " | ".join(
                    (
                        _escape_cell(file_id),
                        status,
                        _escape_cell(details),
                    )
                )
                + " |"
            )
        printed_any_table = True

    if not printed_any_table:
        print("No ground-truth platform comparisons were available for file-level tables.")


def cmd_compact_summary(args: list[str]) -> None:
    report_path = Path(args[0])
    selected_platforms = args[1:]

    if not report_path.exists():
        print("File-level summary unavailable: comparison report not found.")
        raise SystemExit(0)

    payload = json.loads(report_path.read_text())
    ground_truth_platform = str(payload.get("ground_truth_platform", "python"))
    comparisons = payload.get("comparisons", [])
    if not isinstance(comparisons, list):
        comparisons = []

    summary_by_platform: dict[str, tuple[int, int, int]] = {}
    for comparison in comparisons:
        if not isinstance(comparison, dict):
            continue
        if str(comparison.get("reference_platform", "")) != ground_truth_platform:
            continue

        candidate_platform = str(comparison.get("candidate_platform", "unknown"))
        file_summary = comparison.get("file_summary") or {}
        if not isinstance(file_summary, dict):
            file_summary = {}
        pass_count = int(file_summary.get("pass_count", len(comparison.get("passing_files", []))))
        warning_count = int(file_summary.get("warning_count", len(comparison.get("warning_files", []))))
        fail_count = int(file_summary.get("fail_count", len(comparison.get("failing_files", []))))
        total_files = int(
            file_summary.get(
                "total_files",
                file_summary.get("total_reference_files", comparison.get("total_reference_files", 0)),
            )
        )
        summary_by_platform[candidate_platform] = (
            pass_count,
            warning_count,
            fail_count,
            total_files,
        )

    print(f"File-level summary (vs {ground_truth_platform}):")
    for platform in selected_platforms:
        if platform == ground_truth_platform:
            continue
        if platform in summary_by_platform:
            pass_count, warning_count, fail_count, total_files = summary_by_platform[platform]
            print(
                f"  {platform}: "
                f"{pass_count} pass / {warning_count} warning / {fail_count} fail / {total_files} total"
            )
        else:
            print(f"  {platform}: unavailable (no platform results)")


COMMANDS = {
    "b64-file": cmd_b64_file,
    "sha256-file": cmd_sha256_file,
    "reserve-port": cmd_reserve_port,
    "manifest-fixtures": cmd_manifest_fixtures,
    "model-assets": cmd_model_assets,
    "file-url": cmd_file_url,
    "pick-device": cmd_pick_device,
    "pick-ios-simulator": cmd_pick_ios_simulator,
    "wait-ios-boot": cmd_wait_ios_boot,
    "is-ios-simulator-udid": cmd_is_ios_simulator_udid,
    "list-android-emulators": cmd_list_android_emulators,
    "wait-android-boot": cmd_wait_android_boot,
    "file-level-tables": cmd_file_level_tables,
    "compact-summary": cmd_compact_summary,
}


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print(
            "usage: parity_shell_helpers.py <" + "|".join(sorted(COMMANDS)) + "> [args...]",
            file=sys.stderr,
        )
        return 2
    COMMANDS[sys.argv[1]](sys.argv[2:])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
