#!/usr/bin/env bash

set -euo pipefail

app_path="${1:-build/Daisy.app}"

fail() {
    printf 'macOS release signing: %s\n' "$*" >&2
    exit 1
}

required_environment=(
    MACOS_CERTIFICATE_BASE64
    MACOS_CERTIFICATE_PASSWORD
    APPLE_API_KEY_BASE64
    APPLE_API_KEY_ID
    APPLE_API_ISSUER_ID
)

for variable_name in "${required_environment[@]}"; do
    [ -n "${!variable_name:-}" ] || fail "missing required environment variable: $variable_name"
done

[ -d "$app_path" ] || fail "app bundle not found: $app_path"

for command_name in base64 codesign ditto openssl security spctl xcrun; do
    command -v "$command_name" >/dev/null 2>&1 || fail "required command not found: $command_name"
done

working_dir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/daisy-signing.XXXXXX")"
keychain_path="$working_dir/daisy-signing.keychain-db"
certificate_path="$working_dir/developer-id-application.p12"
api_key_path="$working_dir/AuthKey_${APPLE_API_KEY_ID}.p8"
notary_archive="$working_dir/Daisy-notarization.zip"
keychain_password="$(openssl rand -hex 32)"

cleanup() {
    security delete-keychain "$keychain_path" >/dev/null 2>&1 || true
    rm -rf "$working_dir"
}
trap cleanup EXIT

printf '%s' "$MACOS_CERTIFICATE_BASE64" | base64 -D > "$certificate_path"
printf '%s' "$APPLE_API_KEY_BASE64" | base64 -D > "$api_key_path"
chmod 600 "$certificate_path" "$api_key_path"

security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$certificate_path" \
    -k "$keychain_path" \
    -P "$MACOS_CERTIFICATE_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "$keychain_password" \
    "$keychain_path" >/dev/null

signing_identity="$(
    security find-identity -v -p codesigning "$keychain_path" \
        | awk '/"Developer ID Application:/{print $2; exit}'
)"
[ -n "$signing_identity" ] || fail "the certificate does not contain a Developer ID Application identity"

codesign --force \
    --options runtime \
    --timestamp \
    --keychain "$keychain_path" \
    --sign "$signing_identity" \
    "$app_path/Contents/MacOS/Daisy"
codesign --force \
    --options runtime \
    --timestamp \
    --keychain "$keychain_path" \
    --sign "$signing_identity" \
    "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

ditto -c -k --sequesterRsrc --keepParent "$app_path" "$notary_archive"
xcrun notarytool submit "$notary_archive" \
    --key "$api_key_path" \
    --key-id "$APPLE_API_KEY_ID" \
    --issuer "$APPLE_API_ISSUER_ID" \
    --wait

xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"
spctl --assess --type execute --verbose=4 "$app_path"

printf 'Signed, notarized, and stapled %s\n' "$app_path"
