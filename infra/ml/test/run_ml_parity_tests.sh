#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(
  git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>/dev/null \
    || (cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
)"
ML_DIR="$ROOT_DIR/infra/ml/test"
UV_PROJECT_DIR="$ROOT_DIR/infra/ml"
MANIFEST_PATH="$ROOT_DIR/infra/ml/test/ground_truth/manifest.json"
TEST_DATA_DIR="$ML_DIR/test_data/ml-indexing/v1"

PLATFORMS="all"
FAIL_ON_MISSING_PLATFORM=false
FAIL_ON_PLATFORM_RUNNER_ERROR=false
ALLOW_EMPTY_COMPARISON=false
STRICT=false
CONTINUE_ON_MISSING_DEVICES=true
REQUIRE_COMPARISON_PASS=false
OUTPUT_DIR="$ROOT_DIR/infra/ml/test/out/parity"
VERBOSE=false
RENDER_DETECTION_OVERLAYS=false
REUSE_MOBILE_APPLICATION_BINARY=false
PARALLEL_MOBILE_RUNNERS=true
INCLUDE_PAIRWISE=false
INTERNAL_USER_ROUTE=false

LOCAL_MIRROR_PORT=""
LOCAL_MIRROR_PID=""
LOCAL_MIRROR_LOG=""
LOCAL_MODEL_MIRROR_DIR=""

usage() {
  cat <<EOF
Usage: infra/ml/test/run_ml_parity_tests.sh [flags]

Flags:
  --platforms all|desktop|android|ios   (default: all)
  --strict                              (optional future mode; enforces full pass and complete platform coverage)
  --fail-on-missing-platform            (default: disabled)
  --fail-on-platform-runner-error       (default: disabled)
  --allow-empty-comparison              (default: disabled)
  --output-dir <path>                   (default: infra/ml/test/out/parity)
  --verbose                             (default: disabled)
  --render-detection-overlays           (default: disabled; render annotated face detection images to out/parity/detections/<platform>/)
  --reuse-mobile-application-binary     (default: disabled; reuse an existing built mobile binary when available)
  --no-parallel-mobile-runners          (default: disabled; run android/ios runners sequentially)
  --include-pairwise                    (default: disabled; include non-ground-truth pairwise platform comparisons)
  --internal                            (default: disabled; mobile only, run internal-user Rust ML pipeline)
EOF
}

while (($# > 0)); do
  case "$1" in
    --platforms)
      PLATFORMS="$2"
      shift 2
      ;;
    --strict)
      STRICT=true
      shift
      ;;
    --fail-on-missing-platform)
      FAIL_ON_MISSING_PLATFORM=true
      shift
      ;;
    --fail-on-platform-runner-error)
      FAIL_ON_PLATFORM_RUNNER_ERROR=true
      shift
      ;;
    --allow-empty-comparison)
      ALLOW_EMPTY_COMPARISON=true
      shift
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    --render-detection-overlays)
      RENDER_DETECTION_OVERLAYS=true
      shift
      ;;
    --reuse-mobile-application-binary)
      REUSE_MOBILE_APPLICATION_BINARY=true
      shift
      ;;
    --no-parallel-mobile-runners)
      PARALLEL_MOBILE_RUNNERS=false
      shift
      ;;
    --include-pairwise)
      INCLUDE_PAIRWISE=true
      shift
      ;;
    --internal)
      INTERNAL_USER_ROUTE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown flag: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if $STRICT; then
  CONTINUE_ON_MISSING_DEVICES=false
  FAIL_ON_MISSING_PLATFORM=true
  FAIL_ON_PLATFORM_RUNNER_ERROR=true
  REQUIRE_COMPARISON_PASS=true
fi

if [[ "$OUTPUT_DIR" != /* ]]; then
  OUTPUT_DIR="$ROOT_DIR/$OUTPUT_DIR"
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd -P)"
DETECTION_OVERLAYS_OUTPUT_DIR="$OUTPUT_DIR/detections"
LOG_DIR="$OUTPUT_DIR/logs"
rm -rf "$LOG_DIR"
mkdir -p "$LOG_DIR"
PLATFORM_LOG_DIR="$LOG_DIR/platforms"
mkdir -p "$PLATFORM_LOG_DIR"
LOCAL_MODEL_MIRROR_DIR="$ML_DIR/.cache/local_model_mirror"
LOCAL_MIRROR_LOG="$LOG_DIR/local_parity_mirror.log"
PYTHON_OUTPUT_DIR="$OUTPUT_DIR/python"
rm -rf "$PYTHON_OUTPUT_DIR"
mkdir -p "$PYTHON_OUTPUT_DIR"
MANIFEST_B64="$(
  python3 - "$MANIFEST_PATH" <<'PY'
import base64
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
print(base64.b64encode(manifest_path.read_bytes()).decode("ascii"))
PY
)"
CODE_REVISION="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo local)"

print_kv() {
  local key="$1"
  local value="$2"
  printf '  %-30s %s\n' "$key" "$value"
}

format_elapsed_time() {
  local elapsed_seconds="$1"
  local minutes=$((elapsed_seconds / 60))
  local seconds=$((elapsed_seconds % 60))
  printf '%02dm:%02ds' "$minutes" "$seconds"
}

start_platform_runner_timer() {
  local platform="$1"
  local start_epoch="$2"
  local interval_seconds=15

  while true; do
    sleep "$interval_seconds"
    local now_epoch elapsed
    now_epoch=$(date +%s)
    elapsed=$((now_epoch - start_epoch))
    echo "  [$platform] still running... $(format_elapsed_time "$elapsed") elapsed"
  done
}

run_platform_runner_with_progress() {
  local platform="$1"
  local platform_log="$2"

  local start_epoch timer_pid runner_exit elapsed
  start_epoch=$(date +%s)

  echo "Starting $platform platform runner (updates every 15s)"
  start_platform_runner_timer "$platform" "$start_epoch" &
  timer_pid=$!

  if $VERBOSE; then
    run_platform_runner "$platform" 2>&1 | tee "$platform_log"
    runner_exit=${PIPESTATUS[0]}
  else
    run_platform_runner "$platform" >"$platform_log" 2>&1
    runner_exit=$?
  fi

  kill "$timer_pid" >/dev/null 2>&1 || true
  wait "$timer_pid" >/dev/null 2>&1 || true

  elapsed=$(( $(date +%s) - start_epoch ))
  echo "  [$platform] runner finished in $(format_elapsed_time "$elapsed")"
  return "$runner_exit"
}

print_html_report_urls() {
  local report_path="$1"
  python3 - "$report_path" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import quote

raw_path = sys.argv[1]
resolved_path = Path(raw_path).resolve()
posix_path = resolved_path.as_posix()

def as_posix_file_url(path: str) -> str:
    if not path.startswith("/"):
        path = "/" + path
    return "file://" + quote(path, safe="/:._-~")

mac_linux_url = as_posix_file_url(posix_path)

raw_path_normalized = raw_path.replace("\\", "/")
windows_path = None

drive_match = re.match(r"^([A-Za-z]):/(.*)$", raw_path_normalized)
if drive_match:
    windows_path = f"{drive_match.group(1).upper()}:/{drive_match.group(2)}"

if windows_path is None:
    wsl_match = re.match(r"^/mnt/([A-Za-z])/(.*)$", posix_path)
    if wsl_match:
        windows_path = f"{wsl_match.group(1).upper()}:/{wsl_match.group(2)}"

if windows_path is None:
    msys_match = re.match(r"^/([A-Za-z])/(.*)$", posix_path)
    if msys_match:
        windows_path = f"{msys_match.group(1).upper()}:/{msys_match.group(2)}"

if windows_path is None:
    windows_path = f"C:{posix_path}"

windows_url = "file:///" + quote(windows_path, safe="/:._-~")

print(f"    macOS:   {mac_linux_url}")
print(f"    Linux:   {mac_linux_url}")
print(f"    Windows: {windows_url}")
PY
}

stop_local_mirror_server() {
  if [[ -n "${LOCAL_MIRROR_PID:-}" ]]; then
    kill "$LOCAL_MIRROR_PID" >/dev/null 2>&1 || true
    wait "$LOCAL_MIRROR_PID" >/dev/null 2>&1 || true
    LOCAL_MIRROR_PID=""
  fi
}

cleanup_resources() {
  stop_local_mirror_server
}

trap cleanup_resources EXIT

ensure_goldens_python_runtime_deps() {
  if ! command -v uv >/dev/null 2>&1; then
    echo "Python golden generation requires uv, but uv is unavailable." >&2
    return 1
  fi

  if ! uv sync --project "$UV_PROJECT_DIR" --quiet; then
    echo "Failed to sync Python environment for parity goldens." >&2
    return 1
  fi
}

reserve_localhost_port() {
  python3 <<'PY'
import socket

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.bind(("127.0.0.1", 0))
print(sock.getsockname()[1])
sock.close()
PY
}

prepare_local_model_mirror_cache() {
  local model_dir="$1"
  local downloaded=0
  local reused=0
  local failed=0
  local -a model_files=(
    "yolov5s_face_640_640_dynamic.onnx"
    "mobilefacenet_opset15.onnx"
    "mobileclip_s2_image.onnx"
  )

  mkdir -p "$model_dir"

  for model_file in "${model_files[@]}"; do
    local target_path="$model_dir/$model_file"
    if [[ -f "$target_path" ]]; then
      reused=$((reused + 1))
      continue
    fi

    local tmp_path="$target_path.tmp"
    if curl -fsSL --retry 3 --retry-delay 1 "https://models.ente.io/$model_file" -o "$tmp_path"; then
      mv "$tmp_path" "$target_path"
      downloaded=$((downloaded + 1))
    else
      rm -f "$tmp_path"
      failed=$((failed + 1))
      echo "Local model mirror: failed to download $model_file (runner will fall back to direct model download)."
    fi
  done

  echo "Local model mirror cache: downloaded=$downloaded reused=$reused failed=$failed dir=$model_dir"
}

start_local_mirror_server() {
  local mirror_root="$1"
  local mirror_log="$2"
  local port=""
  local pid=""

  if ! command -v python3 >/dev/null 2>&1; then
    echo "Local parity mirror disabled: python3 is unavailable."
    return 1
  fi
  if ! command -v curl >/dev/null 2>&1; then
    echo "Local parity mirror disabled: curl is unavailable."
    return 1
  fi

  port="$(reserve_localhost_port)"
  if [[ -z "$port" ]]; then
    echo "Local parity mirror disabled: failed to reserve a localhost port."
    return 1
  fi

  nohup python3 -m http.server "$port" --bind 127.0.0.1 --directory "$mirror_root" >"$mirror_log" 2>&1 &
  pid=$!

  for _ in {1..25}; do
    if curl -fsS "http://127.0.0.1:$port/" >/dev/null 2>&1; then
      LOCAL_MIRROR_PORT="$port"
      LOCAL_MIRROR_PID="$pid"
      LOCAL_MIRROR_LOG="$mirror_log"
      echo "Local parity mirror ready: http://127.0.0.1:$port (root: $mirror_root)"
      return 0
    fi
    sleep 0.2
  done

  kill "$pid" >/dev/null 2>&1 || true
  wait "$pid" >/dev/null 2>&1 || true
  echo "Local parity mirror disabled: failed to start http server. Log: $mirror_log"
  return 1
}

echo "Running ML parity suite"
print_kv "platforms:" "$PLATFORMS"
print_kv "output_dir:" "$OUTPUT_DIR"
print_kv "verbose:" "$VERBOSE"
print_kv "strict:" "$STRICT"
print_kv "continue_on_missing_devices:" "$CONTINUE_ON_MISSING_DEVICES"
print_kv "fail_on_missing_platform:" "$FAIL_ON_MISSING_PLATFORM"
print_kv "fail_on_platform_runner_error:" "$FAIL_ON_PLATFORM_RUNNER_ERROR"
print_kv "allow_empty_comparison:" "$ALLOW_EMPTY_COMPARISON"
print_kv "render_detection_overlays:" "$RENDER_DETECTION_OVERLAYS"
print_kv "android_build_mode:" "${ML_PARITY_ANDROID_BUILD_MODE:-profile}"
print_kv "reuse_mobile_application_binary:" "$REUSE_MOBILE_APPLICATION_BINARY"
print_kv "parallel_mobile_runners:" "$PARALLEL_MOBILE_RUNNERS"
print_kv "include_pairwise:" "$INCLUDE_PAIRWISE"
print_kv "internal_user_route:" "$INTERNAL_USER_ROUTE"

declare -a selected_platforms=()
case "$PLATFORMS" in
  all)
    selected_platforms=(desktop android ios)
    ;;
  desktop|android|ios)
    selected_platforms=("$PLATFORMS")
    ;;
  *)
    echo "Unsupported --platforms value: $PLATFORMS" >&2
    exit 1
    ;;
esac

sha256_file() {
  python3 - "$1" <<'PY'
import hashlib
import sys

path = sys.argv[1]
digest = hashlib.sha256()
with open(path, "rb") as file:
    for chunk in iter(lambda: file.read(1024 * 1024), b""):
        digest.update(chunk)
print(digest.hexdigest())
PY
}

cache_key_for_url() {
  python3 - "$1" <<'PY'
import hashlib
import sys

print(hashlib.sha256(sys.argv[1].encode("utf-8")).hexdigest())
PY
}

platform_device_id() {
  local platform="$1"
  local requested_device_id="${2:-}"
  local selected
  selected="$(
    python3 - "$platform" "$requested_device_id" <<'PY'
from __future__ import annotations

import json
import subprocess
import sys

platform = sys.argv[1]
requested_device_id = sys.argv[2]


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
PY
  )"

  if [[ -n "$selected" ]]; then
    echo "$selected"
    return 0
  fi

  return 1
}

preflight_platform_device_available() {
  local platform="$1"
  local device_lookup_exit=0
  if platform_device_id "$platform" >/dev/null 2>&1; then
    return 0
  else
    device_lookup_exit=$?
  fi
  case "$device_lookup_exit" in
    1)
      return 1
      ;;
    *)
      return 2
      ;;
  esac
}

preflight_platform_device_id_available() {
  local platform="$1"
  local device_id="$2"
  local selected
  local device_lookup_exit=0
  if selected="$(platform_device_id "$platform" "$device_id" 2>/dev/null)"; then
    :
  else
    device_lookup_exit=$?
    case "$device_lookup_exit" in
      1)
        return 1
        ;;
      *)
        return 2
        ;;
    esac
  fi

  if [[ "$selected" == "$device_id" ]]; then
    return 0
  fi
  return 1
}

resolve_android_tool_path() {
  local binary_name="$1"
  local relative_path="$2"
  local sdk_root=""
  local candidate=""

  if command -v "$binary_name" >/dev/null 2>&1; then
    command -v "$binary_name"
    return 0
  fi

  for sdk_root in "${ANDROID_SDK_ROOT:-}" "${ANDROID_HOME:-}" "$HOME/Library/Android/sdk"; do
    if [[ -z "$sdk_root" ]]; then
      continue
    fi

    candidate="$sdk_root/$relative_path"
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

pick_ios_simulator_udid() {
  local preferred_udid="${1:-}"
  python3 - "$preferred_udid" <<'PY'
from __future__ import annotations

import json
import subprocess
import sys

preferred_udid = sys.argv[1]

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
PY
}

wait_for_ios_simulator_boot() {
  local udid="$1"
  local timeout_seconds="${2:-180}"
  python3 - "$udid" "$timeout_seconds" <<'PY'
from __future__ import annotations

import json
import subprocess
import sys
import time

udid = sys.argv[1]
timeout_seconds = float(sys.argv[2])
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
PY
}

ensure_ios_simulator_running() {
  local explicit_device_id="${ML_PARITY_IOS_DEVICE_ID:-}"
  local preferred_udid="$explicit_device_id"
  local selected_udid=""

  if [[ -n "$explicit_device_id" ]]; then
    if preflight_platform_device_id_available "ios" "$explicit_device_id"; then
      return 0
    fi
  elif preflight_platform_device_available "ios"; then
    return 0
  fi

  if ! command -v xcrun >/dev/null 2>&1; then
    echo "iOS auto-boot skipped: xcrun is unavailable."
    return 1
  fi

  if ! selected_udid="$(pick_ios_simulator_udid "$preferred_udid")"; then
    echo "iOS auto-boot skipped: no available iOS simulator could be selected."
    return 1
  fi

  if [[ -z "$selected_udid" ]]; then
    echo "iOS auto-boot skipped: simulator selection returned an empty UDID."
    return 1
  fi

  if [[ -n "$explicit_device_id" && "$explicit_device_id" != "$selected_udid" ]]; then
    echo "Configured iOS device '$explicit_device_id' is unavailable; using simulator '$selected_udid' instead."
  fi

  echo "Auto-booting iOS simulator: $selected_udid"
  set +e
  xcrun simctl boot "$selected_udid" >/dev/null 2>&1
  local boot_exit=$?
  set -e
  if ((boot_exit != 0)); then
    local simulator_line=""
    simulator_line="$(xcrun simctl list devices "$selected_udid" 2>/dev/null | tr -d '\r' || true)"
    if ! printf '%s\n' "$simulator_line" | grep -q "Booted"; then
      echo "iOS auto-boot failed for simulator '$selected_udid'."
      return 1
    fi
  fi

  if ! wait_for_ios_simulator_boot "$selected_udid" "${ML_PARITY_IOS_BOOT_TIMEOUT_SECONDS:-180}"; then
    echo "iOS simulator '$selected_udid' did not reach Booted state in time."
    return 1
  fi

  export ML_PARITY_IOS_DEVICE_ID="$selected_udid"
  echo "iOS simulator ready: $selected_udid"
  return 0
}

ios_device_id_is_simulator_udid() {
  local device_id="$1"
  python3 - "$device_id" <<'PY'
from __future__ import annotations

import json
import subprocess
import sys

device_id = sys.argv[1]

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
PY
}

pick_android_avd_name() {
  local emulator_bin="$1"
  local preferred_avd="${ML_PARITY_ANDROID_AVD:-}"
  local listed_avds=""

  listed_avds="$("$emulator_bin" -list-avds 2>/dev/null || true)"
  if [[ -z "$listed_avds" ]]; then
    return 1
  fi

  if [[ -n "$preferred_avd" ]]; then
    if printf '%s\n' "$listed_avds" | grep -Fxq "$preferred_avd"; then
      echo "$preferred_avd"
      return 0
    fi
    echo "Configured Android AVD '$preferred_avd' was not found; selecting the first available AVD."
  fi

  printf '%s\n' "$listed_avds" | awk 'NF {print; exit}'
  return 0
}

list_android_emulator_serials() {
  local adb_bin="$1"
  python3 - "$adb_bin" <<'PY'
from __future__ import annotations

import re
import subprocess
import sys

adb_bin = sys.argv[1]
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
PY
}

wait_for_android_emulator_boot() {
  local adb_bin="$1"
  local timeout_seconds="${2:-300}"
  local existing_serials_csv="${3:-}"
  python3 - "$adb_bin" "$timeout_seconds" "$existing_serials_csv" <<'PY'
from __future__ import annotations

import re
import subprocess
import sys
import time

adb_bin = sys.argv[1]
timeout_seconds = float(sys.argv[2])
existing_serials = {value for value in sys.argv[3].split(",") if value}
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
PY
}

ensure_android_emulator_running() {
  local explicit_device_id="${ML_PARITY_ANDROID_DEVICE_ID:-}"
  local emulator_bin=""
  local adb_bin=""
  local avd_name=""
  local booted_serial=""
  local existing_emulator_serials_csv=""
  local emulator_log="${PLATFORM_LOG_DIR:-$LOG_DIR/platforms}/android_emulator_boot.log"

  if [[ -n "$explicit_device_id" ]]; then
    if preflight_platform_device_id_available "android" "$explicit_device_id"; then
      return 0
    fi
  elif preflight_platform_device_available "android"; then
    return 0
  fi

  if ! emulator_bin="$(resolve_android_tool_path "emulator" "emulator/emulator")"; then
    echo "Android auto-boot skipped: emulator tool is unavailable."
    return 1
  fi

  if ! adb_bin="$(resolve_android_tool_path "adb" "platform-tools/adb")"; then
    echo "Android auto-boot skipped: adb tool is unavailable."
    return 1
  fi

  if ! avd_name="$(pick_android_avd_name "$emulator_bin")"; then
    echo "Android auto-boot skipped: no AVDs are available."
    return 1
  fi

  "$adb_bin" start-server >/dev/null 2>&1 || true
  existing_emulator_serials_csv="$(
    list_android_emulator_serials "$adb_bin" | tr '\n' ',' | sed 's/,$//'
  )"

  echo "Auto-booting Android emulator: $avd_name"
  nohup "$emulator_bin" -avd "$avd_name" -no-snapshot-save -no-boot-anim >"$emulator_log" 2>&1 &

  if ! booted_serial="$(
    wait_for_android_emulator_boot \
      "$adb_bin" \
      "${ML_PARITY_ANDROID_BOOT_TIMEOUT_SECONDS:-300}" \
      "$existing_emulator_serials_csv"
  )"; then
    echo "Android emulator '$avd_name' did not report boot completion in time. Boot log: $emulator_log"
    return 1
  fi

  if [[ -n "$explicit_device_id" && "$explicit_device_id" != "$booted_serial" ]]; then
    echo "Configured Android device '$explicit_device_id' is unavailable; using emulator '$booted_serial' instead."
  fi

  export ML_PARITY_ANDROID_DEVICE_ID="$booted_serial"
  echo "Android emulator ready: $booted_serial"
  return 0
}

ensure_selected_mobile_devices_running() {
  local -a auto_boot_failures=()

  for platform in "${selected_platforms[@]}"; do
    case "$platform" in
      android)
        if ! ensure_android_emulator_running; then
          auto_boot_failures+=("android")
        fi
        ;;
      ios)
        if ! ensure_ios_simulator_running; then
          auto_boot_failures+=("ios")
        fi
        ;;
    esac
  done

  if ((${#auto_boot_failures[@]} > 0)); then
    echo "Auto-boot did not guarantee device availability for: ${auto_boot_failures[*]}"
    echo "Proceeding to preflight checks with configured strictness."
  fi
}

run_preflight_checks() {
  local desktop_dir="$ROOT_DIR/desktop"
  local web_dir="$ROOT_DIR/web"
  local runner_path="$desktop_dir/scripts/ml_parity_runner.ts"
  local mobile_dir="$ROOT_DIR/mobile/apps/photos"
  local driver_path="$mobile_dir/test_driver/ml_parity_driver.dart"
  local -a preflight_errors=()
  local -a preflight_warnings=()

  for platform in "${selected_platforms[@]}"; do
    case "$platform" in
      desktop)
        if [[ ! -f "$runner_path" ]]; then
          preflight_errors+=("desktop parity runner not found at $runner_path")
        fi
        if [[ ! -d "$desktop_dir/node_modules" ]]; then
          preflight_errors+=("desktop dependencies missing: $desktop_dir/node_modules")
        fi
        if [[ ! -d "$web_dir/node_modules" ]]; then
          preflight_errors+=("web dependencies missing: $web_dir/node_modules")
        fi
        if ! command -v npx >/dev/null 2>&1; then
          preflight_errors+=("npx is required for desktop parity")
        fi
        if ! command -v yarn >/dev/null 2>&1; then
          preflight_errors+=("yarn is required for desktop parity compilation")
        fi
        ;;
      android|ios)
        if ! command -v flutter >/dev/null 2>&1; then
          preflight_errors+=("flutter is required for $platform parity")
          continue
        fi
        if [[ ! -f "$driver_path" ]]; then
          preflight_errors+=("mobile parity driver not found at $driver_path")
        fi

        local target_path=""
        local explicit_device_id=""
        if [[ "$platform" == "android" ]]; then
          target_path="$mobile_dir/integration_test/ml_parity_android_test.dart"
          explicit_device_id="${ML_PARITY_ANDROID_DEVICE_ID:-}"
        else
          target_path="$mobile_dir/integration_test/ml_parity_ios_test.dart"
          explicit_device_id="${ML_PARITY_IOS_DEVICE_ID:-}"
        fi
        if [[ ! -f "$target_path" ]]; then
          preflight_errors+=("$platform parity test target not found at $target_path")
        fi

        local device_available_exit=0
        if [[ -n "$explicit_device_id" ]]; then
          if preflight_platform_device_id_available "$platform" "$explicit_device_id"; then
            device_available_exit=0
          else
            device_available_exit=$?
          fi
          case "$device_available_exit" in
            0)
              ;;
            1)
              if $CONTINUE_ON_MISSING_DEVICES; then
                preflight_warnings+=(
                  "$platform device id '$explicit_device_id' is unavailable; continuing"
                )
              else
                preflight_errors+=(
                  "$platform device id '$explicit_device_id' is unavailable (strict mode requires available devices)"
                )
              fi
              ;;
            *)
              if $CONTINUE_ON_MISSING_DEVICES; then
                preflight_warnings+=(
                  "could not verify $platform device id '$explicit_device_id'; continuing"
                )
              else
                preflight_errors+=(
                  "could not verify $platform device id '$explicit_device_id' (strict mode requires available devices)"
                )
              fi
              ;;
          esac
        else
          if preflight_platform_device_available "$platform"; then
            device_available_exit=0
          else
            device_available_exit=$?
          fi

          case "$device_available_exit" in
            0)
              ;;
            1)
              if $CONTINUE_ON_MISSING_DEVICES; then
                preflight_warnings+=(
                  "no connected $platform device/simulator detected; continuing"
                )
              else
                preflight_errors+=(
                  "no connected $platform device/simulator detected (strict mode requires available devices)"
                )
              fi
              ;;
            *)
              if $CONTINUE_ON_MISSING_DEVICES; then
                preflight_warnings+=(
                  "could not determine $platform device availability; continuing"
                )
              else
                preflight_errors+=(
                  "could not determine $platform device availability (strict mode requires available devices)"
                )
              fi
              ;;
          esac
        fi
        ;;
    esac
  done

  if ((${#preflight_warnings[@]} > 0)); then
    echo "Preflight warnings:"
    for warning in "${preflight_warnings[@]}"; do
      echo "  - $warning"
    done
  fi

  if ((${#preflight_errors[@]} > 0)); then
    echo "Preflight failed:" >&2
    for error in "${preflight_errors[@]}"; do
      echo "  - $error" >&2
    done
    exit 1
  fi

  echo "Preflight checks passed"
}

echo "Ensuring selected mobile simulators/emulators are running"
ensure_selected_mobile_devices_running

echo "Running preflight checks"
run_preflight_checks

echo "Syncing local fixture directory (cached): $TEST_DATA_DIR"
mkdir -p "$TEST_DATA_DIR"
fixture_metadata_dir="$TEST_DATA_DIR/.source-metadata"
mkdir -p "$fixture_metadata_dir"

downloaded_count=0
reused_count=0
while IFS=$'\t' read -r source_rel source_url source_sha; do
  if [[ -z "$source_rel" ]]; then
    continue
  fi
  if [[ -z "$source_url" ]]; then
    echo "Manifest item missing source_url for source=$source_rel" >&2
    exit 1
  fi

  target_path="$ML_DIR/$source_rel"
  target_dir="$(dirname "$target_path")"
  mkdir -p "$target_dir"

  cache_key="$(cache_key_for_url "$source_url")"
  etag_path="$fixture_metadata_dir/$cache_key.etag"

  should_download=false
  reason=""

  if [[ ! -f "$target_path" ]]; then
    should_download=true
    reason="missing local fixture"
  fi

  if [[ -f "$target_path" && -n "$source_sha" ]]; then
    actual_sha="$(sha256_file "$target_path")"
    if [[ "$actual_sha" != "$source_sha" ]]; then
      should_download=true
      reason="local SHA-256 mismatch"
    fi
  fi

  remote_headers=""
  if remote_headers="$(curl -fsSI --retry 3 --retry-delay 1 "$source_url" 2>/dev/null)"; then
    remote_etag="$(
      printf '%s\n' "$remote_headers" | awk -F': ' 'tolower($1)=="etag"{print $2; exit}' | tr -d '\r'
    )"

    if [[ -n "$remote_etag" ]]; then
      local_etag=""
      if [[ -f "$etag_path" ]]; then
        local_etag="$(tr -d '\r\n' <"$etag_path")"
      fi
      if [[ "$local_etag" != "$remote_etag" ]]; then
        should_download=true
        if [[ -z "$reason" ]]; then
          reason="remote ETag changed"
        fi
      fi
    elif [[ -f "$target_path" && -z "$source_sha" ]]; then
      should_download=true
      if [[ -z "$reason" ]]; then
        reason="remote ETag unavailable"
      fi
    fi
  else
    if [[ -f "$target_path" && -z "$source_sha" ]]; then
      should_download=true
      if [[ -z "$reason" ]]; then
        reason="failed to fetch remote metadata"
      fi
    fi
    remote_etag=""
  fi

  if $should_download; then
    tmp_path="$target_path.tmp"
    if ! curl -fsSL --retry 3 --retry-delay 1 "$source_url" -o "$tmp_path"; then
      rm -f "$tmp_path"
      echo "Failed to download fixture from $source_url" >&2
      exit 1
    fi

    if [[ -n "$source_sha" ]]; then
      actual_sha="$(sha256_file "$tmp_path")"
      if [[ "$actual_sha" != "$source_sha" ]]; then
        rm -f "$tmp_path"
        echo "SHA-256 mismatch for $source_rel: expected $source_sha got $actual_sha" >&2
        exit 1
      fi
    fi

    mv "$tmp_path" "$target_path"
    downloaded_count=$((downloaded_count + 1))
    if [[ -n "$remote_etag" ]]; then
      printf '%s\n' "$remote_etag" >"$etag_path"
    else
      rm -f "$etag_path"
    fi

    if $VERBOSE; then
      echo "Downloaded fixture: $source_rel ($reason)"
    fi
  else
    reused_count=$((reused_count + 1))
    if $VERBOSE; then
      echo "Reused cached fixture: $source_rel"
    fi
  fi
done < <(
  python3 - "$MANIFEST_PATH" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
manifest = json.loads(manifest_path.read_text())
items = manifest.get("items", [])
for item in items:
    source = str(item.get("source", "")).strip()
    source_url = str(item.get("source_url", "")).strip()
    source_sha = str(item.get("source_sha256", "")).strip()
    print(f"{source}\t{source_url}\t{source_sha}")
PY
)
echo "Fixture sync summary: downloaded=$downloaded_count reused=$reused_count"

has_mobile_platform=false
for platform in "${selected_platforms[@]}"; do
  case "$platform" in
    android|ios)
      has_mobile_platform=true
      ;;
  esac
done

if $has_mobile_platform; then
  prepare_local_model_mirror_cache "$LOCAL_MODEL_MIRROR_DIR"
  if ! start_local_mirror_server "$ML_DIR" "$LOCAL_MIRROR_LOG"; then
    echo "Proceeding without local parity mirror."
  fi
fi

echo "Ensuring Python runtime dependencies for goldens are available"
if ! ensure_goldens_python_runtime_deps; then
  echo "Python dependency preflight failed; parity output not generated." >&2
  exit 1
fi

echo "Generating Python goldens"
goldens_log="$LOG_DIR/generate_goldens.log"
if $VERBOSE; then
  uv run --project "$UV_PROJECT_DIR" --no-sync python "$ML_DIR/tools/generate_goldens.py" \
    --manifest "infra/ml/test/ground_truth/manifest.json" \
    --output-dir "$PYTHON_OUTPUT_DIR"
else
  if ! uv run --project "$UV_PROJECT_DIR" --no-sync python "$ML_DIR/tools/generate_goldens.py" \
    --manifest "infra/ml/test/ground_truth/manifest.json" \
    --output-dir "$PYTHON_OUTPUT_DIR" >"$goldens_log" 2>&1; then
    echo "Python golden generation failed. Log: $goldens_log" >&2
    exit 1
  fi
fi

echo "Clearing stale platform output directories"
for platform in "${selected_platforms[@]}"; do
  platform_dir="$OUTPUT_DIR/$platform"
  rm -rf "$platform_dir"
  mkdir -p "$platform_dir"
done

run_desktop_runner() {
  local desktop_dir="$ROOT_DIR/desktop"
  local web_dir="$ROOT_DIR/web"
  local runner_path="$desktop_dir/scripts/ml_parity_runner.ts"
  local platform_output_dir="$OUTPUT_DIR/desktop"

  if [[ ! -f "$runner_path" ]]; then
    echo "Desktop parity runner not found at $runner_path; skipping desktop run."
    return 2
  fi

  if [[ ! -d "$desktop_dir/node_modules" ]]; then
    echo "Desktop dependencies are missing ($desktop_dir/node_modules); skipping desktop run."
    return 2
  fi

  if [[ ! -d "$web_dir/node_modules" ]]; then
    echo "Web dependencies are missing ($web_dir/node_modules); skipping desktop run."
    return 2
  fi

  if ! command -v npx >/dev/null 2>&1; then
    echo "npx is required to run the desktop parity runner; skipping desktop run."
    return 2
  fi

  echo "Compiling desktop TypeScript sources"
  if ! yarn --cwd "$desktop_dir" tsc; then
    echo "Desktop TypeScript compilation failed; desktop parity output not generated."
    return 1
  fi

  echo "Running desktop parity runner"
  if ! (
    cd "$web_dir"
    isDesktop=1 appName=photos desktopAppVersion=parity npx --yes tsx "$runner_path" \
      --manifest "$MANIFEST_PATH" \
      --output-dir "$platform_output_dir"
  ); then
    echo "Desktop parity runner failed; desktop parity output not generated."
    return 1
  fi

  return 0
}

run_mobile_runner() {
  local platform="$1"
  local target="$2"
  local device_id="${3:-}"

  local mobile_dir="$ROOT_DIR/mobile/apps/photos"
  local driver_path="$mobile_dir/test_driver/ml_parity_driver.dart"
  local target_path="$mobile_dir/$target"
  local platform_output_dir="$OUTPUT_DIR/$platform"
  local output_path="$platform_output_dir/results.json"
  local resolved_device_id="$device_id"
  local android_build_mode="${ML_PARITY_ANDROID_BUILD_MODE:-profile}"

  if [[ ! -f "$driver_path" ]]; then
    echo "Mobile parity driver not found at $driver_path; skipping $platform run."
    return 2
  fi

  if [[ ! -f "$target_path" ]]; then
    echo "Mobile parity test target not found at $target_path; skipping $platform run."
    return 2
  fi

  if ! command -v flutter >/dev/null 2>&1; then
    echo "flutter is required to run mobile parity; skipping $platform run."
    return 2
  fi

  if [[ -z "$resolved_device_id" ]]; then
    local platform_available_exit=0
    if preflight_platform_device_available "$platform"; then
      platform_available_exit=0
    else
      platform_available_exit=$?
    fi
    case "$platform_available_exit" in
      0)
        ;;
      1)
        echo "No connected $platform device/simulator detected; skipping $platform run."
        return 2
        ;;
      *)
        echo "Could not determine $platform device availability; skipping $platform run."
        return 2
        ;;
    esac
  fi

  local package_config_path="$mobile_dir/.dart_tool/package_config.json"
  local needs_pub_get=false
  if [[ ! -f "$package_config_path" ]]; then
    needs_pub_get=true
  else
    for dependency_file in "$mobile_dir/pubspec.yaml" "$mobile_dir/pubspec.lock" "$mobile_dir/pubspec_overrides.yaml"; do
      if [[ -f "$dependency_file" && "$dependency_file" -nt "$package_config_path" ]]; then
        needs_pub_get=true
        break
      fi
    done
  fi

  if $needs_pub_get; then
    echo "Running flutter pub get for mobile app"
    if ! (cd "$mobile_dir" && flutter pub get); then
      echo "flutter pub get failed; $platform parity output not generated."
      return 1
    fi
  fi

  local flavor=""
  case "$platform" in
    android)
      flavor="${ML_PARITY_ANDROID_FLAVOR:-independent}"
      case "$android_build_mode" in
        debug|profile|release)
          ;;
        *)
          echo "Invalid ML_PARITY_ANDROID_BUILD_MODE='$android_build_mode' (expected debug|profile|release)."
          return 1
          ;;
      esac
      ;;
    ios)
      flavor="${ML_PARITY_IOS_FLAVOR:-}"
      ;;
  esac

  local -a drive_cmd=(
    flutter drive
    --driver=test_driver/ml_parity_driver.dart
    --target="$target"
    --no-pub
  )
  if [[ "$platform" == "android" ]]; then
    drive_cmd+=(--"$android_build_mode")
  fi
  if [[ -n "$flavor" ]]; then
    drive_cmd+=(--flavor "$flavor")
  fi
  drive_cmd+=(
    --no-dds
    --dart-define=ML_PARITY_MANIFEST_B64="$MANIFEST_B64"
    --dart-define=ML_PARITY_CODE_REVISION="$CODE_REVISION"
    --dart-define=ML_PARITY_INTERNAL_USER="$INTERNAL_USER_ROUTE"
  )

  if [[ -z "$resolved_device_id" ]]; then
    if ! resolved_device_id="$(platform_device_id "$platform")"; then
      echo "Could not resolve a connected $platform device; skipping $platform run."
      return 2
    fi
  fi

  drive_cmd+=(-d "$resolved_device_id")

  local local_mirror_base_url=""
  if [[ -n "${LOCAL_MIRROR_PORT:-}" ]]; then
    case "$platform" in
      android)
        if [[ "$resolved_device_id" == emulator-* ]]; then
          local_mirror_base_url="http://10.0.2.2:$LOCAL_MIRROR_PORT"
        fi
        ;;
      ios)
        if ios_device_id_is_simulator_udid "$resolved_device_id"; then
          local_mirror_base_url="http://127.0.0.1:$LOCAL_MIRROR_PORT"
        fi
        ;;
    esac
  fi
  if [[ -n "$local_mirror_base_url" ]]; then
    drive_cmd+=(
      --dart-define=ML_PARITY_LOCAL_MIRROR_BASE_URL="$local_mirror_base_url"
    )
  fi

  local existing_app_url=""
  local application_binary=""
  case "$platform" in
    android)
      existing_app_url="${ML_PARITY_ANDROID_EXISTING_APP_URL:-}"
      if [[ -n "${ML_PARITY_ANDROID_APPLICATION_BINARY:-}" ]]; then
        application_binary="${ML_PARITY_ANDROID_APPLICATION_BINARY}"
      elif $REUSE_MOBILE_APPLICATION_BINARY; then
        local default_apk_path="$mobile_dir/build/app/outputs/flutter-apk/app-${flavor}-${android_build_mode}.apk"
        if [[ -f "$default_apk_path" ]]; then
          application_binary="$default_apk_path"
        fi
      fi
      ;;
    ios)
      existing_app_url="${ML_PARITY_IOS_EXISTING_APP_URL:-}"
      if [[ -n "${ML_PARITY_IOS_APPLICATION_BINARY:-}" ]]; then
        application_binary="${ML_PARITY_IOS_APPLICATION_BINARY}"
      fi
      ;;
  esac

  if [[ -n "$existing_app_url" ]]; then
    drive_cmd+=(--use-existing-app="$existing_app_url" --no-build)
    echo "Reusing existing $platform app via VM service URL."
  elif [[ -n "$application_binary" ]]; then
    if [[ -f "$application_binary" ]]; then
      drive_cmd+=(--use-application-binary="$application_binary")
      echo "Reusing prebuilt $platform binary: $application_binary"
    else
      echo "Configured $platform application binary does not exist at $application_binary; falling back to build."
    fi
  fi

  echo "Running $platform parity runner"
  if ! (
    cd "$mobile_dir"
    ML_PARITY_DRIVER_OUTPUT="$output_path" "${drive_cmd[@]}"
  ); then
    echo "$platform parity runner failed; $platform parity output not generated."
    return 1
  fi

  if [[ ! -f "$output_path" ]]; then
    echo "$platform parity runner finished without output at $output_path."
    return 1
  fi

  return 0
}

run_android_runner() {
  run_mobile_runner \
    "android" \
    "integration_test/ml_parity_android_test.dart" \
    "${ML_PARITY_ANDROID_DEVICE_ID:-}"
}

run_ios_runner() {
  run_mobile_runner \
    "ios" \
    "integration_test/ml_parity_ios_test.dart" \
    "${ML_PARITY_IOS_DEVICE_ID:-}"
}

run_platform_runner() {
  local platform="$1"
  case "$platform" in
    desktop)
      run_desktop_runner
      ;;
    android)
      run_android_runner
      ;;
    ios)
      run_ios_runner
      ;;
    *)
      echo "Unknown platform: $platform" >&2
      return 1
      ;;
  esac
}

render_file_level_report_tables() {
  local report_path="$1"
  python3 - "$report_path" <<'PY'
from __future__ import annotations

import json
import sys
from collections import OrderedDict
from pathlib import Path

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


report_path = Path(sys.argv[1])
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
PY
}

render_html_report() {
  local report_path="$1"
  local html_output_path="$OUTPUT_DIR/parity_report.html"
  local renderer_log="$LOG_DIR/render_html_report.log"
  local rendered_path=""

  if $VERBOSE; then
    if ! rendered_path="$(
      python3 "$ML_DIR/tools/render_parity_html_report.py" \
        --report "$report_path" \
        --output "$html_output_path"
    )"; then
      echo "Failed to render HTML parity report at $html_output_path."
      return 1
    fi
  else
    if ! rendered_path="$(
      python3 "$ML_DIR/tools/render_parity_html_report.py" \
        --report "$report_path" \
        --output "$html_output_path" \
        2>"$renderer_log"
    )"; then
      echo "Failed to render HTML parity report at $html_output_path. Log: $renderer_log"
      return 1
    fi
  fi

  LAST_HTML_REPORT="${rendered_path##*$'\n'}"
  if [[ -z "$LAST_HTML_REPORT" ]]; then
    LAST_HTML_REPORT="$html_output_path"
  fi
  if [[ ! -f "$LAST_HTML_REPORT" ]]; then
    if $VERBOSE; then
      echo "Failed to render HTML parity report at $html_output_path."
    else
      echo "Failed to render HTML parity report at $html_output_path. Log: $renderer_log"
    fi
    return 1
  fi
  return 0
}

render_markdown_report() {
  local report_path="$1"
  local markdown_output_path="$OUTPUT_DIR/parity_report.llm.md"
  local renderer_log="$LOG_DIR/render_markdown_report.log"
  local rendered_path=""

  if $VERBOSE; then
    if ! rendered_path="$(
      python3 "$ML_DIR/tools/render_parity_markdown_report.py" \
        --report "$report_path" \
        --output "$markdown_output_path"
    )"; then
      echo "Failed to render Markdown parity report at $markdown_output_path."
      return 1
    fi
  else
    if ! rendered_path="$(
      python3 "$ML_DIR/tools/render_parity_markdown_report.py" \
        --report "$report_path" \
        --output "$markdown_output_path" \
        2>"$renderer_log"
    )"; then
      echo "Failed to render Markdown parity report at $markdown_output_path. Log: $renderer_log"
      return 1
    fi
  fi

  LAST_MARKDOWN_REPORT="${rendered_path##*$'\n'}"
  if [[ -z "$LAST_MARKDOWN_REPORT" ]]; then
    LAST_MARKDOWN_REPORT="$markdown_output_path"
  fi
  if [[ ! -f "$LAST_MARKDOWN_REPORT" ]]; then
    echo "Markdown parity report was not generated at $LAST_MARKDOWN_REPORT."
    return 1
  fi
  return 0
}

render_compact_summary() {
  local report_path="$1"
  shift
  python3 - "$report_path" "$@" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

report_path = Path(sys.argv[1])
selected_platforms = sys.argv[2:]

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
PY
}

render_detection_overlays() {
  local overlays_log="$LOG_DIR/render_detection_overlays.log"
  local overlays_output_dir="$DETECTION_OVERLAYS_OUTPUT_DIR"
  local -a overlay_platforms=("${selected_platforms[@]}" "python")
  local -a overlay_cmd=(
    uv run --project "$UV_PROJECT_DIR" --no-sync
    python "$ML_DIR/tools/render_face_detection_overlays.py"
    --manifest "$MANIFEST_PATH"
    --parity-dir "$OUTPUT_DIR"
  )

  for platform in "${overlay_platforms[@]}"; do
    overlay_cmd+=(--platform "$platform")
  done

  if $VERBOSE; then
    "${overlay_cmd[@]}" 2>&1 | tee "$overlays_log"
    local overlay_exit=${PIPESTATUS[0]}
    if ((overlay_exit != 0)); then
      return "$overlay_exit"
    fi
  else
    if ! "${overlay_cmd[@]}" >"$overlays_log" 2>&1; then
      return 1
    fi
  fi

  return 0
}

comparison_report_passed() {
  local report_path="$1"
  python3 - "$report_path" <<'PY'
import json
import sys
from pathlib import Path

report_path = Path(sys.argv[1])
if not report_path.exists():
    sys.exit(2)

payload = json.loads(report_path.read_text())
sys.exit(0 if bool(payload.get("passed", False)) else 1)
PY
}

LAST_HTML_REPORT=""
LAST_MARKDOWN_REPORT=""
declare -a failed_platform_runners=()

run_platform_runner_and_capture_exit() {
  local platform="$1"
  local platform_log="$PLATFORM_LOG_DIR/$platform.log"
  local status_file="$LOG_DIR/.platform_runner_${platform}.status"

  set +e
  run_platform_runner_with_progress "$platform" "$platform_log"
  local platform_run_exit=$?
  set -e

  printf '%s\n' "$platform_run_exit" >"$status_file"
}

has_selected_android=false
has_selected_ios=false
for platform in "${selected_platforms[@]}"; do
  case "$platform" in
    android)
      has_selected_android=true
      ;;
    ios)
      has_selected_ios=true
      ;;
  esac
done

run_mobile_in_parallel=false
if $PARALLEL_MOBILE_RUNNERS && $has_selected_android && $has_selected_ios; then
  run_mobile_in_parallel=true
fi

if $run_mobile_in_parallel; then
  if [[ -z "${ML_PARITY_ANDROID_DEVICE_ID:-}" ]]; then
    resolved_parallel_android_device="$(platform_device_id "android" || true)"
    if [[ -n "$resolved_parallel_android_device" ]]; then
      export ML_PARITY_ANDROID_DEVICE_ID="$resolved_parallel_android_device"
    fi
  fi
  if [[ -z "${ML_PARITY_IOS_DEVICE_ID:-}" ]]; then
    resolved_parallel_ios_device="$(platform_device_id "ios" || true)"
    if [[ -n "$resolved_parallel_ios_device" ]]; then
      export ML_PARITY_IOS_DEVICE_ID="$resolved_parallel_ios_device"
    fi
  fi
fi

if $run_mobile_in_parallel; then
  echo "Running android and ios platform runners in parallel"

  for platform in "${selected_platforms[@]}"; do
    case "$platform" in
      android|ios)
        ;;
      *)
        run_platform_runner_and_capture_exit "$platform"
        ;;
    esac
  done

  declare -a mobile_runner_pids=()
  run_platform_runner_and_capture_exit "android" &
  mobile_runner_pids+=("$!")
  run_platform_runner_and_capture_exit "ios" &
  mobile_runner_pids+=("$!")

  for pid in "${mobile_runner_pids[@]}"; do
    wait "$pid" || true
  done
else
  for platform in "${selected_platforms[@]}"; do
    run_platform_runner_and_capture_exit "$platform"
  done
fi

for platform in "${selected_platforms[@]}"; do
  platform_log="$PLATFORM_LOG_DIR/$platform.log"
  status_file="$LOG_DIR/.platform_runner_${platform}.status"
  if [[ -f "$status_file" ]]; then
    platform_run_exit="$(tr -d '\r\n' <"$status_file")"
  else
    platform_run_exit=1
  fi

  case "$platform_run_exit" in
    0)
      echo "Platform runner completed for $platform."
      ;;
    1)
      echo "Platform runner failed for $platform. Log: $platform_log"
      failed_platform_runners+=("$platform(exit=1)")
      ;;
    2)
      echo "Platform runner unavailable for $platform. Log: $platform_log"
      ;;
    *)
      echo "Platform runner returned unexpected exit code $platform_run_exit for $platform. Log: $platform_log"
      failed_platform_runners+=("$platform(exit=$platform_run_exit)")
      ;;
  esac
done

if ((${#failed_platform_runners[@]} > 0)); then
  echo "One or more platform runners failed: ${failed_platform_runners[*]}" >&2
  if $FAIL_ON_PLATFORM_RUNNER_ERROR; then
    echo "Failing because --fail-on-platform-runner-error is set" >&2
    exit 1
  fi
  echo "Continuing with available platform outputs."
fi

declare -a compare_args=()
missing_platform_count=0

for platform in "${selected_platforms[@]}"; do
  platform_output="$OUTPUT_DIR/$platform/results.json"
  if [[ -f "$platform_output" ]]; then
    compare_args+=(--platform-result "$platform=$platform_output")
    if $VERBOSE; then
      echo "Using $platform output: $platform_output"
    fi
  else
    if $VERBOSE; then
      echo "Platform output unavailable for $platform at $platform_output"
    fi
    missing_platform_count=$((missing_platform_count + 1))
  fi
done

if $FAIL_ON_MISSING_PLATFORM && ((missing_platform_count > 0)); then
  echo "Missing platform outputs and --fail-on-missing-platform is set" >&2
  exit 1
fi

if ((${#compare_args[@]} == 0)); then
  if $ALLOW_EMPTY_COMPARISON; then
    echo "No platform outputs available; continuing because --allow-empty-comparison is set"
  else
    echo "No platform outputs available for comparison. Provide at least one platform result or use --allow-empty-comparison." >&2
    exit 1
  fi
fi

compare_output="$OUTPUT_DIR/comparison_report.json"
compare_log="$LOG_DIR/comparison.log"
compare_cmd=(
  uv run --project "$UV_PROJECT_DIR" --no-sync python "$ML_DIR/tools/compare_parity_outputs.py"
  --ground-truth "$PYTHON_OUTPUT_DIR/results.json"
  --output "$compare_output"
)
if ! $INCLUDE_PAIRWISE; then
  compare_cmd+=(--no-pairwise)
fi
if ((${#compare_args[@]} > 0)); then
  compare_cmd+=("${compare_args[@]}")
fi

set +e
if $VERBOSE; then
  "${compare_cmd[@]}" 2>&1 | tee "$compare_log"
  compare_exit=${PIPESTATUS[0]}
else
  "${compare_cmd[@]}" >"$compare_log" 2>&1
  compare_exit=$?
fi
set -e

if [[ -f "$compare_output" ]]; then
  if $VERBOSE; then
    render_file_level_report_tables "$compare_output"
  fi
  if ! render_html_report "$compare_output"; then
    echo "Continuing without HTML report due to renderer failure."
  fi
  if ! render_markdown_report "$compare_output"; then
    echo "Continuing without Markdown report due to renderer failure."
  fi
  echo
  render_compact_summary "$compare_output" "${selected_platforms[@]}"
fi

if $RENDER_DETECTION_OVERLAYS; then
  if ! render_detection_overlays; then
    echo "Failed to render detection overlays. Log: $LOG_DIR/render_detection_overlays.log" >&2
    exit 1
  fi
fi

if ((compare_exit != 0)); then
  echo "Parity comparison command failed. Log: $compare_log"
  exit "$compare_exit"
fi

if $REQUIRE_COMPARISON_PASS; then
  if comparison_report_passed "$compare_output"; then
    echo "Strict mode: comparison report passed."
  else
    comparison_pass_exit=$?
    if ((comparison_pass_exit == 2)); then
      echo "Strict mode failed: comparison report is missing at $compare_output" >&2
    else
      echo "Strict mode failed: comparison report contains parity failures." >&2
    fi
    exit 1
  fi
fi

echo
echo "Report artifacts"
print_kv "comparison report (JSON):" "$compare_output"
if [[ -n "$LAST_HTML_REPORT" ]]; then
  print_kv "html parity report:" "$LAST_HTML_REPORT"
  echo "  html parity report URLs:"
  print_html_report_urls "$LAST_HTML_REPORT"
fi
if [[ -n "$LAST_MARKDOWN_REPORT" ]]; then
  print_kv "markdown parity report (LLM):" "$LAST_MARKDOWN_REPORT"
  echo "  note: for extensive results beyond the printed summary, read the markdown report."
fi
if $RENDER_DETECTION_OVERLAYS; then
  print_kv "detection overlays:" "$DETECTION_OVERLAYS_OUTPUT_DIR"
fi
print_kv "detailed logs:" "$LOG_DIR"
echo "Parity comparison completed"
