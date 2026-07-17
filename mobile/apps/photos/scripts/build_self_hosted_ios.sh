#!/usr/bin/env bash

set -euo pipefail
umask 077

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly app_dir="$(cd "$script_dir/.." && pwd)"
readonly repository_root="$(cd "$app_dir/../../.." && pwd -P)"
readonly flutter_bin="${FLUTTER_BIN:-flutter}"
readonly dart_bin="${DART_BIN:-dart}"
readonly xcodebuild_bin="${XCODEBUILD_BIN:-xcodebuild}"
readonly security_bin="${SECURITY_BIN:-security}"
readonly plutil_bin="${PLUTIL_BIN:-plutil}"
readonly plist_buddy_bin="${PLIST_BUDDY_BIN:-/usr/libexec/PlistBuddy}"
readonly openssl_bin="${OPENSSL_BIN:-openssl}"
readonly date_bin="${DATE_BIN:-date}"
readonly self_hosted_scheme="selfhosted"
readonly expected_bundle_identifier="me.vanton.ente.photos.selfhosted"
readonly expected_distribution_certificate_sha256="8fcaf5f761acbcbeeae4710fb75370646071d8a905ac2a70ffeb46676c4a1e0c"

cleanup_dir=""
cleanup() {
  if [[ -n "$cleanup_dir" && -d "$cleanup_dir" ]]; then
    rm -rf -- "$cleanup_dir"
  fi
}
trap cleanup EXIT

fail_usage() {
  echo "$1" >&2
  exit 64
}

require_environment_value() {
  local variable_name="$1"
  if [[ -z "${!variable_name:-}" ]]; then
    fail_usage "$variable_name is required for an Ad Hoc archive export."
  fi
}

reject_repository_path() {
  local path="$1"
  local label="$2"
  case "$path" in
    "$repository_root" | "$repository_root"/*)
      fail_usage "$label must be outside the Git repository."
      ;;
  esac
}

resolve_existing_profile() {
  local path="$1"
  [[ "$path" == /* ]] || fail_usage "ENTE_IOS_ADHOC_PROFILE must be an absolute path."
  [[ -f "$path" ]] || fail_usage "ENTE_IOS_ADHOC_PROFILE must name an existing file."
  [[ ! -L "$path" ]] || fail_usage "ENTE_IOS_ADHOC_PROFILE must not be a symbolic link."
  [[ "$path" == *.mobileprovision ]] || fail_usage "ENTE_IOS_ADHOC_PROFILE must end in .mobileprovision."

  local directory
  directory="$(cd "$(dirname "$path")" && pwd -P)"
  local resolved_path="$directory/$(basename "$path")"
  reject_repository_path "$resolved_path" "ENTE_IOS_ADHOC_PROFILE"
  printf '%s\n' "$resolved_path"
}

resolve_new_output_path() {
  local path="$1"
  local label="$2"
  [[ "$path" == /* ]] || fail_usage "$label must be an absolute path."
  [[ ! -e "$path" ]] || fail_usage "$label already exists; archive exports never overwrite output."

  local parent="$(dirname "$path")"
  [[ -d "$parent" ]] || fail_usage "The parent directory for $label must already exist."
  [[ -w "$parent" ]] || fail_usage "The parent directory for $label is not writable."
  local resolved_parent
  resolved_parent="$(cd "$parent" && pwd -P)"
  local resolved_path="$resolved_parent/$(basename "$path")"
  reject_repository_path "$resolved_path" "$label"
  printf '%s\n' "$resolved_path"
}

validated_profile_name=""
validated_profile_uuid=""
validated_certificate_sha1=""
validated_profile_expiration=""

validate_adhoc_profile() {
  local profile_path="$1"
  local expected_team="$2"
  local expected_device_count="$3"
  local decoded_profile="$cleanup_dir/profile.plist"
  local certificate_der="$cleanup_dir/distribution-certificate.der"

  "$security_bin" cms -D -i "$profile_path" -o "$decoded_profile"
  "$plutil_bin" -lint "$decoded_profile" >/dev/null

  local profile_team
  profile_team="$("$plist_buddy_bin" -c 'Print :TeamIdentifier:0' "$decoded_profile")"
  [[ "$profile_team" == "$expected_team" ]] || fail_usage "The provisioning profile belongs to a different Apple team."

  local application_identifier
  application_identifier="$("$plist_buddy_bin" -c 'Print :Entitlements:application-identifier' "$decoded_profile")"
  [[ "$application_identifier" == "${expected_team}.${expected_bundle_identifier}" ]] || fail_usage "The provisioning profile does not match $expected_bundle_identifier."

  local entitlement_team
  entitlement_team="$("$plist_buddy_bin" -c 'Print :Entitlements:com.apple.developer.team-identifier' "$decoded_profile")"
  [[ "$entitlement_team" == "$expected_team" ]] || fail_usage "The provisioning profile entitlement team does not match the requested team."

  local get_task_allow
  get_task_allow="$("$plist_buddy_bin" -c 'Print :Entitlements:get-task-allow' "$decoded_profile")"
  [[ "$get_task_allow" == false ]] || fail_usage "The provisioning profile is debuggable and is not valid for Ad Hoc export."
  if "$plist_buddy_bin" -c 'Print :ProvisionsAllDevices' "$decoded_profile" >/dev/null 2>&1; then
    fail_usage "The provisioning profile is not a device-scoped Ad Hoc profile."
  fi

  local device_count
  device_count="$("$plutil_bin" -extract ProvisionedDevices xml1 -o - "$decoded_profile" | awk '/<string>/{count++} END {print count+0}')"
  [[ "$device_count" == "$expected_device_count" ]] || fail_usage "The provisioning profile device count does not match ENTE_IOS_EXPECTED_DEVICE_COUNT."

  local certificate_count
  certificate_count="$("$plutil_bin" -extract DeveloperCertificates xml1 -o - "$decoded_profile" | awk '/<data>/{count++} END {print count+0}')"
  [[ "$certificate_count" == 1 ]] || fail_usage "The provisioning profile must contain exactly one distribution certificate."

  validated_profile_name="$("$plist_buddy_bin" -c 'Print :Name' "$decoded_profile")"
  validated_profile_uuid="$("$plist_buddy_bin" -c 'Print :UUID' "$decoded_profile")"
  [[ "$validated_profile_uuid" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]] || fail_usage "The provisioning profile UUID is invalid."

  validated_profile_expiration="$("$plutil_bin" -extract ExpirationDate raw -o - "$decoded_profile")"
  local expiration_epoch
  expiration_epoch="$("$date_bin" -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$validated_profile_expiration" '+%s' 2>/dev/null)" || fail_usage "The provisioning profile expiration date is invalid."
  local current_epoch
  current_epoch="$("$date_bin" -u '+%s')"
  (( expiration_epoch > current_epoch )) || fail_usage "The provisioning profile has expired."

  "$plutil_bin" -extract DeveloperCertificates.0 raw -o - "$decoded_profile" |
    "$openssl_bin" base64 -d -A >"$certificate_der"
  "$openssl_bin" x509 -inform DER -in "$certificate_der" -checkend 0 -noout >/dev/null || fail_usage "The provisioning profile's distribution certificate has expired."

  local certificate_sha256_output
  certificate_sha256_output="$("$openssl_bin" x509 -inform DER -in "$certificate_der" -noout -fingerprint -sha256)"
  local certificate_sha256="${certificate_sha256_output#*=}"
  certificate_sha256="$(printf '%s' "$certificate_sha256" | tr -d ':' | tr '[:upper:]' '[:lower:]')"
  [[ "$certificate_sha256" == "$expected_distribution_certificate_sha256" ]] || fail_usage "The provisioning profile does not contain the pinned distribution certificate."

  local certificate_sha1_output
  certificate_sha1_output="$("$openssl_bin" x509 -inform DER -in "$certificate_der" -noout -fingerprint -sha1)"
  validated_certificate_sha1="${certificate_sha1_output#*=}"
  validated_certificate_sha1="$(printf '%s' "$validated_certificate_sha1" | tr -d ':' | tr '[:lower:]' '[:upper:]')"
  [[ "$validated_certificate_sha1" =~ ^[[:xdigit:]]{40}$ ]] || fail_usage "The distribution certificate SHA-1 fingerprint is invalid."

  local identities
  identities="$("$security_bin" find-identity -v -p codesigning)"
  printf '%s\n' "$identities" | grep -Fq "$validated_certificate_sha1" || fail_usage "The matching Apple Distribution private-key identity is not available in the local Keychain."
}

install_validated_profile() {
  local profile_path="$1"
  local install_directory="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  local installed_profile="$install_directory/$validated_profile_uuid.mobileprovision"
  mkdir -p "$install_directory"
  if [[ -e "$installed_profile" ]]; then
    cmp -s "$profile_path" "$installed_profile" || fail_usage "A different local profile already uses UUID $validated_profile_uuid."
  else
    install -m 600 "$profile_path" "$installed_profile"
  fi
}

write_export_options() {
  local path="$1"
  local team="$2"
  "$plutil_bin" -create xml1 "$path"
  "$plist_buddy_bin" -c 'Add :method string release-testing' "$path"
  "$plist_buddy_bin" -c 'Add :destination string export' "$path"
  "$plist_buddy_bin" -c 'Add :signingStyle string manual' "$path"
  "$plist_buddy_bin" -c "Add :teamID string $team" "$path"
  "$plist_buddy_bin" -c "Add :signingCertificate string $validated_certificate_sha1" "$path"
  "$plist_buddy_bin" -c 'Add :manageAppVersionAndBuildNumber bool false' "$path"
  "$plist_buddy_bin" -c 'Add :stripSwiftSymbols bool true' "$path"
  "$plist_buddy_bin" -c 'Add :provisioningProfiles dict' "$path"
  "$plist_buddy_bin" -c "Add :provisioningProfiles:$expected_bundle_identifier string $validated_profile_uuid" "$path"
}

if [[ -z "${ENTE_SELF_HOSTED_ENDPOINT:-}" ]]; then
  echo "ENTE_SELF_HOSTED_ENDPOINT is required." >&2
  exit 64
fi

cd "$app_dir"
canonical_endpoint="$(
  "$dart_bin" run --verbosity=error \
    scripts/validate_self_hosted_endpoint.dart \
    "$ENTE_SELF_HOSTED_ENDPOINT"
)"
readonly canonical_endpoint

if [[ "${1:-}" == "--validate-only" ]]; then
  if [[ "$#" -ne 1 ]]; then
    echo "--validate-only does not accept additional arguments." >&2
    exit 64
  fi
  echo "Validated configurable endpoint: $canonical_endpoint"
  exit 0
fi

adhoc_mode=""
for argument in "$@"; do
  case "$argument" in
    --adhoc) adhoc_mode="export" ;;
    --adhoc-preflight) adhoc_mode="preflight" ;;
  esac
done
if [[ -n "$adhoc_mode" && "$#" -ne 1 ]]; then
  fail_usage "--adhoc and --adhoc-preflight must be the only command-line argument; use the documented ENTE_IOS_* inputs."
fi

for argument in "$@"; do
  case "$argument" in
    -D | -D* | --dart-define | --dart-define=* | --dart-define-from-file | --dart-define-from-file=*)
      echo "The configurable build wrapper owns all Dart defines; remove '$argument'." >&2
      exit 64
      ;;
    --config-only | --no-config-only | --flavor | --flavor=*)
      echo "The configurable build wrapper owns Xcode configuration; remove '$argument'." >&2
      exit 64
      ;;
  esac
done

echo "Building configurable Ente Photos with default $canonical_endpoint"

is_simulator=false
configuration="Release"
for argument in "$@"; do
  case "$argument" in
    --simulator)
      is_simulator=true
      configuration="Debug"
      ;;
    --debug)
      configuration="Debug"
      ;;
    --profile)
      configuration="Profile"
      ;;
    --release)
      configuration="Release"
      ;;
  esac
done

readonly xcode_configuration="${configuration}-selfhosted"

configure_flutter() {
  "$flutter_bin" build ios \
    "$@" \
    --flavor "$self_hosted_scheme" \
    --config-only \
    --no-codesign \
    --dart-define=configurableEndpoint=true \
    --dart-define="endpoint=$canonical_endpoint"
}

run_adhoc_export() {
  local preflight_only="$1"
  require_environment_value ENTE_IOS_DISTRIBUTION_TEAM
  require_environment_value ENTE_IOS_ADHOC_PROFILE
  require_environment_value ENTE_IOS_EXPECTED_DEVICE_COUNT
  require_environment_value ENTE_IOS_MARKETING_VERSION
  require_environment_value ENTE_IOS_BUILD_NUMBER
  require_environment_value ENTE_IOS_ARCHIVE_PATH
  require_environment_value ENTE_IOS_EXPORT_PATH

  local distribution_team="$ENTE_IOS_DISTRIBUTION_TEAM"
  local expected_device_count="$ENTE_IOS_EXPECTED_DEVICE_COUNT"
  local marketing_version="$ENTE_IOS_MARKETING_VERSION"
  local build_number="$ENTE_IOS_BUILD_NUMBER"
  [[ "$distribution_team" =~ ^[A-Z0-9]{10}$ ]] || fail_usage "ENTE_IOS_DISTRIBUTION_TEAM must be a ten-character Apple Team ID."
  [[ "$expected_device_count" =~ ^[1-9][0-9]*$ ]] || fail_usage "ENTE_IOS_EXPECTED_DEVICE_COUNT must be a positive integer."
  [[ "$marketing_version" =~ ^[0-9]+([.][0-9]+){0,2}$ ]] || fail_usage "ENTE_IOS_MARKETING_VERSION must contain one to three numeric components."
  [[ "$build_number" =~ ^[1-9][0-9]*$ ]] || fail_usage "ENTE_IOS_BUILD_NUMBER must be a positive integer."

  local profile_path
  profile_path="$(resolve_existing_profile "$ENTE_IOS_ADHOC_PROFILE")"
  local archive_path
  archive_path="$(resolve_new_output_path "$ENTE_IOS_ARCHIVE_PATH" "ENTE_IOS_ARCHIVE_PATH")"
  [[ "$archive_path" == *.xcarchive ]] || fail_usage "ENTE_IOS_ARCHIVE_PATH must end in .xcarchive."
  local export_path
  export_path="$(resolve_new_output_path "$ENTE_IOS_EXPORT_PATH" "ENTE_IOS_EXPORT_PATH")"
  [[ "$archive_path" != "$export_path" ]] || fail_usage "Archive and export paths must be different."

  cleanup_dir="$(mktemp -d "${TMPDIR:-/tmp}/ente-self-hosted-ios.XXXXXX")"
  validate_adhoc_profile "$profile_path" "$distribution_team" "$expected_device_count"
  install_validated_profile "$profile_path"

  echo "Validated the pinned Ad Hoc profile ($validated_profile_uuid) with $expected_device_count authorized device(s)."
  if [[ "$preflight_only" == true ]]; then
    echo "Ad Hoc archive preflight passed without invoking Flutter or Xcode."
    return
  fi
  echo "Configuring configurable Ente Photos $marketing_version ($build_number) for Ad Hoc archive export."
  configure_flutter \
    --release \
    "--build-name=$marketing_version" \
    "--build-number=$build_number"

  local export_options="$cleanup_dir/ExportOptions.plist"
  write_export_options "$export_options" "$distribution_team"
  "$plutil_bin" -lint "$export_options" >/dev/null

  "$xcodebuild_bin" archive \
    -workspace ios/Runner.xcworkspace \
    -scheme "$self_hosted_scheme" \
    -configuration Release-selfhosted \
    -destination "generic/platform=iOS" \
    -archivePath "$archive_path" \
    -hideShellScriptEnvironment \
    CODE_SIGN_STYLE=Manual \
    "CODE_SIGN_IDENTITY=$validated_certificate_sha1" \
    "DEVELOPMENT_TEAM=$distribution_team" \
    "SELF_HOSTED_DEVELOPMENT_TEAM=$distribution_team" \
    "PROVISIONING_PROFILE_SPECIFIER=$validated_profile_uuid" \
    "MARKETING_VERSION=$marketing_version" \
    "CURRENT_PROJECT_VERSION=$build_number" \
    "FLUTTER_BUILD_NAME=$marketing_version" \
    "FLUTTER_BUILD_NUMBER=$build_number" \
    -quiet
  [[ -d "$archive_path" ]] || fail_usage "Xcode reported success without producing the requested archive."

  "$xcodebuild_bin" -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_path" \
    -exportOptionsPlist "$export_options" \
    -quiet

  shopt -s nullglob
  local ipa_paths=("$export_path"/*.ipa)
  shopt -u nullglob
  [[ "${#ipa_paths[@]}" -eq 1 ]] || fail_usage "Ad Hoc export must produce exactly one IPA."
  [[ -f "${ipa_paths[0]}" ]] || fail_usage "The exported IPA is not a regular file."
  echo "Created the manually signed Ad Hoc archive and IPA outside Git."
}

if [[ "$adhoc_mode" == "export" ]]; then
  run_adhoc_export false
  exit 0
fi
if [[ "$adhoc_mode" == "preflight" ]]; then
  run_adhoc_export true
  exit 0
fi

if [[ "$is_simulator" == true ]]; then
  configure_flutter "$@"

  "$xcodebuild_bin" \
    -workspace ios/Runner.xcworkspace \
    -scheme "$self_hosted_scheme" \
    -configuration "$xcode_configuration" \
    -sdk iphonesimulator \
    -destination "generic/platform=iOS Simulator" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_IDENTITY=- \
    "SYMROOT=$app_dir/build/ios" \
    -quiet \
    build

  echo "Built build/ios/${xcode_configuration}-iphonesimulator/SelfHostedRunner.app"
  exit 0
fi

codesigning_allowed=true
for argument in "$@"; do
  if [[ "$argument" == "--no-codesign" ]]; then
    codesigning_allowed=false
    break
  fi
done

if [[ "$codesigning_allowed" == true && -z "${ENTE_IOS_DEVELOPMENT_TEAM:-}" ]]; then
  echo "ENTE_IOS_DEVELOPMENT_TEAM is required for a signed device build." >&2
  exit 64
fi

configure_flutter "$@"

device_destination="generic/platform=iOS"
if [[ "$codesigning_allowed" == true && -n "${ENTE_IOS_DEVICE_ID:-}" ]]; then
  device_destination="id=$ENTE_IOS_DEVICE_ID"
fi

xcodebuild_arguments=(
  -workspace ios/Runner.xcworkspace
  -scheme "$self_hosted_scheme"
  -configuration "$xcode_configuration"
  -sdk iphoneos
  -destination "$device_destination"
  "SYMROOT=$app_dir/build/ios"
)

if [[ "$codesigning_allowed" == true ]]; then
  xcodebuild_arguments+=(
    "SELF_HOSTED_DEVELOPMENT_TEAM=$ENTE_IOS_DEVELOPMENT_TEAM"
    -allowProvisioningUpdates
    -allowProvisioningDeviceRegistration
  )
else
  xcodebuild_arguments+=(CODE_SIGNING_ALLOWED=NO)
fi

"$xcodebuild_bin" "${xcodebuild_arguments[@]}" -quiet build
echo "Built build/ios/${xcode_configuration}-iphoneos/SelfHostedRunner.app"
