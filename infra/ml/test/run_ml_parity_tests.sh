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
PARITY_HELPERS="$ML_DIR/tools/parity_shell_helpers.py"

PLATFORMS="all"
OUTPUT_DIR="$ROOT_DIR/infra/ml/test/out/parity"
VERBOSE=false
RENDER_DETECTION_OVERLAYS=false
REUSE_MOBILE_APPLICATION_BINARY=false
PARALLEL_MOBILE_RUNNERS=true

LOCAL_MIRROR_PORT=""
LOCAL_MIRROR_PID=""
LOCAL_MIRROR_LOG=""
LOCAL_MODEL_MIRROR_DIR=""

usage() {
  cat <<EOF
Usage: infra/ml/test/run_ml_parity_tests.sh [flags]

Flags:
  --platforms all|desktop|android|ios   (default: all)
  --output-dir <path>                   (default: infra/ml/test/out/parity)
  --verbose                             (default: disabled)
  --render-detection-overlays           (default: disabled; render annotated face detection images to out/parity/detections/<platform>/)
  --reuse-mobile-application-binary     (default: disabled; reuse an existing built mobile binary when available)
  --no-parallel-mobile-runners          (default: disabled; run android/ios runners sequentially)
EOF
}

while (($# > 0)); do
  case "$1" in
    --platforms)
      PLATFORMS="$2"
      shift 2
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
MANIFEST_B64="$(python3 "$PARITY_HELPERS" b64-file "$MANIFEST_PATH")"
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
  python3 "$PARITY_HELPERS" reserve-port
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
print_kv "render_detection_overlays:" "$RENDER_DETECTION_OVERLAYS"
print_kv "android_build_mode:" "${ML_PARITY_ANDROID_BUILD_MODE:-profile}"
print_kv "reuse_mobile_application_binary:" "$REUSE_MOBILE_APPLICATION_BINARY"
print_kv "parallel_mobile_runners:" "$PARALLEL_MOBILE_RUNNERS"
print_kv "mobile_ml_route:" "rust"

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
  python3 "$PARITY_HELPERS" sha256-file "$1"
}

platform_device_id() {
  local platform="$1"
  local requested_device_id="${2:-}"
  local selected
  selected="$(
    python3 "$PARITY_HELPERS" pick-device "$platform" "$requested_device_id"
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
  python3 "$PARITY_HELPERS" pick-ios-simulator "${1:-}"
}

wait_for_ios_simulator_boot() {
  python3 "$PARITY_HELPERS" wait-ios-boot "$1" "${2:-180}"
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
  python3 "$PARITY_HELPERS" is-ios-simulator-udid "$1"
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
  python3 "$PARITY_HELPERS" list-android-emulators "$1"
}

wait_for_android_emulator_boot() {
  python3 "$PARITY_HELPERS" wait-android-boot "$1" "${2:-300}" "${3:-}"
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
    echo "Proceeding to preflight checks."
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
        if ! command -v npm >/dev/null 2>&1; then
          preflight_errors+=("npm is required for desktop parity compilation")
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
              preflight_warnings+=(
                "$platform device id '$explicit_device_id' is unavailable; continuing"
              )
              ;;
            *)
              preflight_warnings+=(
                "could not verify $platform device id '$explicit_device_id'; continuing"
              )
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
              preflight_warnings+=(
                "no connected $platform device/simulator detected; continuing"
              )
              ;;
            *)
              preflight_warnings+=(
                "could not determine $platform device availability; continuing"
              )
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
  if [[ -z "$source_sha" ]]; then
    echo "Manifest item missing source_sha256 for source=$source_rel" >&2
    exit 1
  fi

  target_path="$ML_DIR/$source_rel"
  target_dir="$(dirname "$target_path")"
  mkdir -p "$target_dir"

  should_download=false
  reason=""

  if [[ ! -f "$target_path" ]]; then
    should_download=true
    reason="missing local fixture"
  fi

  if [[ -f "$target_path" ]]; then
    actual_sha="$(sha256_file "$target_path")"
    if [[ "$actual_sha" != "$source_sha" ]]; then
      should_download=true
      reason="local SHA-256 mismatch"
    fi
  fi

  if $should_download; then
    tmp_path="$target_path.tmp"
    if ! curl -fsSL --retry 3 --retry-delay 1 "$source_url" -o "$tmp_path"; then
      rm -f "$tmp_path"
      echo "Failed to download fixture from $source_url" >&2
      exit 1
    fi

    actual_sha="$(sha256_file "$tmp_path")"
    if [[ "$actual_sha" != "$source_sha" ]]; then
      rm -f "$tmp_path"
      echo "SHA-256 mismatch for $source_rel: expected $source_sha got $actual_sha" >&2
      exit 1
    fi

    mv "$tmp_path" "$target_path"
    downloaded_count=$((downloaded_count + 1))

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
  python3 "$PARITY_HELPERS" manifest-fixtures "$MANIFEST_PATH"
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

  echo "Compiling desktop TypeScript sources"
  if ! (cd "$desktop_dir" && npm exec -- tsc); then
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
  local platform_output_dir="$OUTPUT_DIR/$platform"
  local output_path="$platform_output_dir/results.json"
  local resolved_device_id="$device_id"
  local android_build_mode="${ML_PARITY_ANDROID_BUILD_MODE:-profile}"

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

  local workspace_dir="$ROOT_DIR/mobile"
  local package_config_path="$workspace_dir/.dart_tool/package_config.json"
  local needs_pub_get=false
  if [[ ! -f "$package_config_path" ]]; then
    needs_pub_get=true
  else
    for dependency_file in "$mobile_dir/pubspec.yaml" "$workspace_dir/pubspec.yaml" "$workspace_dir/pubspec.lock"; do
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

render_compact_summary() {
  python3 "$PARITY_HELPERS" compact-summary "$@"
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

LAST_HTML_REPORT=""
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
  echo "Continuing with available platform outputs."
fi

declare -a compare_args=()

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
  fi
done

if ((${#compare_args[@]} == 0)); then
  echo "No platform outputs available for comparison." >&2
  exit 1
fi

compare_output="$OUTPUT_DIR/comparison_report.json"
compare_log="$LOG_DIR/comparison.log"
compare_cmd=(
  uv run --project "$UV_PROJECT_DIR" --no-sync python "$ML_DIR/tools/compare_parity_outputs.py"
  --ground-truth "$PYTHON_OUTPUT_DIR/results.json"
  --output "$compare_output"
)
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
    python3 "$PARITY_HELPERS" file-level-tables "$compare_output"
  fi
  if ! render_html_report "$compare_output"; then
    echo "Continuing without HTML report due to renderer failure."
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

echo
echo "Report artifacts"
print_kv "comparison report (JSON):" "$compare_output"
if [[ -n "$LAST_HTML_REPORT" ]]; then
  print_kv "html parity report:" "$LAST_HTML_REPORT"
  print_kv "html parity report URL:" "$(python3 "$PARITY_HELPERS" file-url "$LAST_HTML_REPORT")"
fi
if $RENDER_DETECTION_OVERLAYS; then
  print_kv "detection overlays:" "$DETECTION_OVERLAYS_OUTPUT_DIR"
fi
print_kv "detailed logs:" "$LOG_DIR"
echo "Parity comparison completed"
