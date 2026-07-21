#!/bin/bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly PROJECT_PATH="$REPO_ROOT/CodexBangs.xcodeproj"
readonly SCHEME="CodexBangs"
readonly APP_NAME="Codex-bangs.app"
readonly DERIVED_DATA_PATH="${CODEX_BANGS_DERIVED_DATA_PATH:-$HOME/Library/Developer/Xcode/DerivedData/CodexBangs}"

mode="signed"
version=""
build_number=""
output_dir="$REPO_ROOT/work/release"
stage_dir=""
mount_point=""
mount_attached=0
keychain_path=""
keychain_created=0
certificate_path=""
notary_key_path=""
signing_certificate_base64=""
signing_certificate_password=""
developer_id_application=""
apple_team_id=""
apple_api_key_id=""
apple_api_issuer_id=""
apple_api_private_key_base64=""

usage() {
  cat <<'EOF'
Usage: scripts/build-release.sh [options]

Build and package Codex-bangs for macOS.

Options:
  --unsigned-smoke       Build an unsigned local DMG and verify its contents.
  --version VERSION      Set CFBundleShortVersionString (defaults to Xcode settings).
  --build-number NUMBER  Set CFBundleVersion (defaults to Xcode settings).
  --output-dir PATH      Write the DMG to PATH (defaults to work/release).
  -h, --help             Show this help.

Signed mode requires the credential environment variables documented in
docs/distribution.md. It signs and notarizes both the app and DMG.
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

require_env() {
  local variable_name="$1"
  [[ -n "${!variable_name:-}" ]] || die "missing required environment variable: $variable_name"
}

require_option_value() {
  local option_name="$1"
  local option_value="${2:-}"
  [[ -n "$option_value" ]] || die "$option_name requires a value"
}

while (($# > 0)); do
  case "$1" in
    --unsigned-smoke)
      mode="unsigned"
      shift
      ;;
    --version)
      require_option_value "$1" "${2:-}"
      version="$2"
      shift 2
      ;;
    --build-number)
      require_option_value "$1" "${2:-}"
      build_number="$2"
      shift 2
      ;;
    --output-dir)
      require_option_value "$1" "${2:-}"
      output_dir="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

if [[ "$mode" == "signed" ]]; then
  require_env DEVELOPER_ID_CERTIFICATE_BASE64
  require_env DEVELOPER_ID_CERTIFICATE_PASSWORD
  require_env DEVELOPER_ID_APPLICATION
  require_env APPLE_TEAM_ID
  require_env APPLE_API_KEY_ID
  require_env APPLE_API_ISSUER_ID
  require_env APPLE_API_PRIVATE_KEY_BASE64

  signing_certificate_base64="$DEVELOPER_ID_CERTIFICATE_BASE64"
  signing_certificate_password="$DEVELOPER_ID_CERTIFICATE_PASSWORD"
  developer_id_application="$DEVELOPER_ID_APPLICATION"
  apple_team_id="$APPLE_TEAM_ID"
  apple_api_key_id="$APPLE_API_KEY_ID"
  apple_api_issuer_id="$APPLE_API_ISSUER_ID"
  apple_api_private_key_base64="$APPLE_API_PRIVATE_KEY_BASE64"

  unset DEVELOPER_ID_CERTIFICATE_BASE64
  unset DEVELOPER_ID_CERTIFICATE_PASSWORD
  unset DEVELOPER_ID_APPLICATION
  unset APPLE_TEAM_ID
  unset APPLE_API_KEY_ID
  unset APPLE_API_ISSUER_ID
  unset APPLE_API_PRIVATE_KEY_BASE64
fi

if [[ -z "$version" || -z "$build_number" ]]; then
  build_settings="$(
    xcodebuild \
      -project "$PROJECT_PATH" \
      -target "$SCHEME" \
      -configuration Release \
      CODE_SIGNING_ALLOWED=NO \
      -showBuildSettings
  )"
  if [[ -z "$version" ]]; then
    version="$(awk '$1 == "MARKETING_VERSION" && $2 == "=" { print $3; exit }' <<<"$build_settings")"
  fi
  if [[ -z "$build_number" ]]; then
    build_number="$(awk '$1 == "CURRENT_PROJECT_VERSION" && $2 == "=" { print $3; exit }' <<<"$build_settings")"
  fi
fi

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
  die "version must look like 1.2.3"
[[ "$build_number" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || \
  die "build number must contain one to three numeric components"

mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd -P)"
stage_dir="$(mktemp -d "$output_dir/.release-stage.XXXXXX")"
mount_point="$stage_dir/mount"

cleanup() {
  local exit_status=$?
  set +e

  if ((mount_attached)); then
    if ! hdiutil detach "$mount_point" >/dev/null; then
      echo "warning: could not detach release verification mount at $mount_point" >&2
      exit_status=1
    else
      mount_attached=0
    fi
  fi

  if ((keychain_created)); then
    if ! security delete-keychain "$keychain_path" >/dev/null 2>&1; then
      echo "warning: could not delete ephemeral release keychain" >&2
      rm -f -- "$keychain_path"
      exit_status=1
    fi
    keychain_created=0
  fi

  if [[ -n "$certificate_path" ]]; then
    rm -f -- "$certificate_path"
  fi
  if [[ -n "$notary_key_path" ]]; then
    rm -f -- "$notary_key_path"
  fi

  if ((! mount_attached)) && [[ "$stage_dir" == "$output_dir"/.release-stage.* ]]; then
    rm -rf -- "$stage_dir"
  fi

  exit "$exit_status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

setup_signing_credentials() {
  local keychain_password

  umask 077
  certificate_path="$stage_dir/developer-id.p12"
  keychain_path="$stage_dir/release.keychain-db"
  keychain_password="$(openssl rand -hex 32)"
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo "::add-mask::$keychain_password"
  fi

  printf '%s' "$signing_certificate_base64" | \
    /usr/bin/base64 -D -o "$certificate_path"

  security create-keychain -p "$keychain_password" "$keychain_path"
  keychain_created=1
  security set-keychain-settings -lut 21600 "$keychain_path"
  security unlock-keychain -p "$keychain_password" "$keychain_path"
  security import "$certificate_path" \
    -k "$keychain_path" \
    -P "$signing_certificate_password" \
    -T /usr/bin/codesign >/dev/null
  security set-key-partition-list \
    -S apple-tool:,apple: \
    -s \
    -k "$keychain_password" \
    "$keychain_path" >/dev/null

  security find-identity -v -p codesigning "$keychain_path" | \
    grep -F -- "$developer_id_application" >/dev/null || \
    die "Developer ID Application identity was not found in the imported certificate"

  notary_key_path="$stage_dir/AuthKey_${apple_api_key_id}.p8"
  printf '%s' "$apple_api_private_key_base64" | \
    /usr/bin/base64 -D -o "$notary_key_path"
  chmod 600 "$notary_key_path"

  signing_certificate_base64=""
  signing_certificate_password=""
  apple_api_private_key_base64=""
}

sign_code() {
  local path="$1"
  codesign \
    --force \
    --sign "$developer_id_application" \
    --keychain "$keychain_path" \
    --options runtime \
    --timestamp \
    "$path"
}

notarize() {
  local artifact_path="$1"
  local artifact_label="$2"
  local result_path="$stage_dir/notary-${artifact_label}.json"
  local submission_id=""
  local submission_status=""
  local -a auth_options=(
    --key "$notary_key_path"
    --key-id "$apple_api_key_id"
    --issuer "$apple_api_issuer_id"
  )

  if ! xcrun notarytool submit \
    "${auth_options[@]}" \
    --wait \
    --timeout 30m \
    --output-format json \
    "$artifact_path" >"$result_path"; then
    submission_id="$(plutil -extract id raw -o - "$result_path" 2>/dev/null || true)"
    if [[ -n "$submission_id" ]]; then
      xcrun notarytool log "${auth_options[@]}" "$submission_id" || true
    fi
    die "notarization request failed for $artifact_label"
  fi

  submission_id="$(plutil -extract id raw -o - "$result_path")"
  submission_status="$(plutil -extract status raw -o - "$result_path")"
  if [[ "$submission_status" != "Accepted" ]]; then
    xcrun notarytool log "${auth_options[@]}" "$submission_id" || true
    die "notarization was not accepted for $artifact_label (submission $submission_id)"
  fi

  echo "Notarization accepted for $artifact_label (submission $submission_id)."
}

verify_app_signature() {
  local app_path="$1"
  local signature_details

  codesign --verify --deep --strict --verbose=2 "$app_path"
  signature_details="$(codesign --display --verbose=4 "$app_path" 2>&1)"
  grep -F "Authority=$developer_id_application" <<<"$signature_details" >/dev/null || \
    die "app signature authority does not match the requested Developer ID identity"
  grep -F "TeamIdentifier=$apple_team_id" <<<"$signature_details" >/dev/null || \
    die "app signature team does not match APPLE_TEAM_ID"
  grep -E '^flags=.*runtime' <<<"$signature_details" >/dev/null || \
    die "app signature is missing the hardened runtime flag"
}

verify_dmg_readback() {
  local dmg_path="$1"
  local expected_signature="$2"
  local mounted_app
  local mounted_version
  local mounted_build_number

  mkdir "$mount_point"
  hdiutil attach \
    -readonly \
    -nobrowse \
    -mountpoint "$mount_point" \
    "$dmg_path" >/dev/null
  mount_attached=1

  mounted_app="$mount_point/$APP_NAME"
  [[ -d "$mounted_app" ]] || die "DMG readback is missing $APP_NAME"
  [[ -x "$mounted_app/Contents/MacOS/Codex-bangs" ]] || \
    die "DMG readback is missing the app executable"
  [[ -L "$mount_point/Applications" ]] || \
    die "DMG readback is missing the Applications shortcut"
  [[ "$(readlink "$mount_point/Applications")" == "/Applications" ]] || \
    die "DMG Applications shortcut has the wrong destination"

  mounted_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$mounted_app/Contents/Info.plist")"
  mounted_build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$mounted_app/Contents/Info.plist")"
  [[ "$mounted_version" == "$version" ]] || die "DMG readback has the wrong app version"
  [[ "$mounted_build_number" == "$build_number" ]] || die "DMG readback has the wrong build number"

  if [[ "$expected_signature" == "signed" ]]; then
    verify_app_signature "$mounted_app"
    xcrun stapler validate "$mounted_app"
    spctl --assess --type execute --verbose=4 "$mounted_app"
  fi

  hdiutil detach "$mount_point" >/dev/null
  mount_attached=0
}

echo "Building Codex-bangs $version ($build_number) in $mode mode..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=NO \
  build

readonly BUILT_APP="$DERIVED_DATA_PATH/Build/Products/Release/$APP_NAME"
[[ -d "$BUILT_APP" ]] || die "expected build product was not created at $BUILT_APP"

readonly STAGED_APP="$stage_dir/$APP_NAME"
ditto "$BUILT_APP" "$STAGED_APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$STAGED_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$STAGED_APP/Contents/Info.plist"

if [[ "$mode" == "signed" ]]; then
  setup_signing_credentials

  if [[ -d "$STAGED_APP/Contents/Frameworks" ]]; then
    while IFS= read -r -d '' nested_code; do
      sign_code "$nested_code"
    done < <(
      find "$STAGED_APP/Contents/Frameworks" -depth \
        \( \( -type f -name '*.dylib' \) -o \( -type d -name '*.framework' \) \) \
        -print0
    )
  fi
  sign_code "$STAGED_APP"
  verify_app_signature "$STAGED_APP"

  readonly APP_NOTARY_ARCHIVE="$stage_dir/Codex-bangs-notarization.zip"
  ditto -c -k --keepParent "$STAGED_APP" "$APP_NOTARY_ARCHIVE"
  notarize "$APP_NOTARY_ARCHIVE" app
  xcrun stapler staple "$STAGED_APP"
  xcrun stapler validate "$STAGED_APP"
  spctl --assess --type execute --verbose=4 "$STAGED_APP"
fi

readonly DMG_ROOT="$stage_dir/dmg-root"
readonly STAGED_DMG="$stage_dir/Codex-bangs-${version}.dmg"
readonly FINAL_DMG="$output_dir/Codex-bangs-${version}.dmg"
mkdir "$DMG_ROOT"
ditto "$STAGED_APP" "$DMG_ROOT/$APP_NAME"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create \
  -srcfolder "$DMG_ROOT" \
  -volname "Codex-bangs" \
  -format UDZO \
  -ov \
  "$STAGED_DMG"

if [[ "$mode" == "signed" ]]; then
  codesign \
    --force \
    --sign "$developer_id_application" \
    --keychain "$keychain_path" \
    --timestamp \
    "$STAGED_DMG"
  codesign --verify --verbose=2 "$STAGED_DMG"
  notarize "$STAGED_DMG" dmg
  xcrun stapler staple "$STAGED_DMG"
  xcrun stapler validate "$STAGED_DMG"
  spctl --assess \
    --type open \
    --context context:primary-signature \
    --verbose=4 \
    "$STAGED_DMG"
fi

hdiutil verify "$STAGED_DMG"
verify_dmg_readback "$STAGED_DMG" "$mode"
mv -f "$STAGED_DMG" "$FINAL_DMG"

echo "Release artifact: $FINAL_DMG"
