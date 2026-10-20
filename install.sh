#!/usr/bin/env bash

set -euo pipefail

repository="${DAISY_REPOSITORY:-saragluna/daisy}"
version="${DAISY_VERSION:-latest}"
install_dir="${DAISY_INSTALL_DIR:-$HOME/Applications}"
download_base_url="${DAISY_DOWNLOAD_BASE_URL:-}"
no_launch="${DAISY_NO_LAUNCH:-0}"

usage() {
    cat <<'EOF'
Install Daisy for macOS from GitHub Releases.

Usage:
  install.sh [--version VERSION] [--install-dir DIRECTORY] [--no-launch]

Environment variables:
  DAISY_REPOSITORY         GitHub repository (default: saragluna/daisy)
  DAISY_VERSION            Release tag or latest (default: latest)
  DAISY_INSTALL_DIR        Destination directory (default: ~/Applications)
  DAISY_DOWNLOAD_BASE_URL  Override release asset base URL
  DAISY_NO_LAUNCH=1        Do not launch Daisy after installation
EOF
}

fail() {
    printf 'Daisy installer: %s\n' "$*" >&2
    exit 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version)
            [ "$#" -ge 2 ] || fail "--version requires a value"
            version="$2"
            shift 2
            ;;
        --install-dir)
            [ "$#" -ge 2 ] || fail "--install-dir requires a value"
            install_dir="$2"
            shift 2
            ;;
        --no-launch)
            no_launch=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown option: $1"
            ;;
    esac
done

for command_name in codesign curl ditto shasum spctl unzip; do
    command -v "$command_name" >/dev/null 2>&1 || fail "required command not found: $command_name"
done

case "$(uname -s)" in
    Darwin) ;;
    *) fail "this installer is for macOS; use install.ps1 on Windows" ;;
esac

case "$(uname -m)" in
    arm64|x86_64) ;;
    *) fail "unsupported Mac architecture: $(uname -m)" ;;
esac

if [ -z "$download_base_url" ]; then
    if [ "$version" = "latest" ]; then
        download_base_url="https://github.com/$repository/releases/latest/download"
    else
        download_base_url="https://github.com/$repository/releases/download/$version"
    fi
fi
download_base_url="${download_base_url%/}"

case "$download_base_url" in
    https://*|file://*) ;;
    *) fail "download URL must use HTTPS" ;;
esac

archive_name="Daisy-macOS.zip"
checksum_name="SHA256SUMS"
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/daisy-install.XXXXXX")"
staged_app=""

cleanup() {
    rm -rf "$temporary_dir"
    if [ -n "$staged_app" ] && [ -e "$staged_app" ]; then
        rm -rf "$staged_app"
    fi
}
trap cleanup EXIT

download() {
    source_url="$1"
    destination="$2"
    case "$source_url" in
        https://*)
            curl --fail --location --silent --show-error \
                --proto '=https' --tlsv1.2 \
                "$source_url" --output "$destination"
            ;;
        file://*)
            curl --fail --location --silent --show-error \
                "$source_url" --output "$destination"
            ;;
    esac
}

archive_path="$temporary_dir/$archive_name"
checksum_path="$temporary_dir/$checksum_name"

printf 'Downloading Daisy %s...\n' "$version"
download "$download_base_url/$archive_name" "$archive_path"
download "$download_base_url/$checksum_name" "$checksum_path"

expected_checksum="$({
    awk -v asset="$archive_name" '$2 == asset || $2 == "*" asset { print tolower($1); exit }' "$checksum_path"
} || true)"
[ -n "$expected_checksum" ] || fail "$checksum_name does not contain $archive_name"

actual_checksum="$(shasum -a 256 "$archive_path" | awk '{ print tolower($1) }')"
[ "$actual_checksum" = "$expected_checksum" ] || fail "checksum verification failed for $archive_name"

extracted_dir="$temporary_dir/extracted"
mkdir -p "$extracted_dir"
unzip -q "$archive_path" -d "$extracted_dir"

source_app="$extracted_dir/Daisy.app"
[ -x "$source_app/Contents/MacOS/Daisy" ] || fail "release archive does not contain a valid Daisy.app"

codesign --verify --deep --strict "$source_app" >/dev/null 2>&1 \
    || fail "release app has an invalid Developer ID signature"
spctl --assess --type execute "$source_app" >/dev/null 2>&1 \
    || fail "release app is not accepted by macOS Gatekeeper"

mkdir -p "$install_dir"
target_app="$install_dir/Daisy.app"
staged_app="$install_dir/.Daisy.app.install.$$"
backup_app="$install_dir/.Daisy.app.backup.$$"

rm -rf "$staged_app" "$backup_app"
ditto "$source_app" "$staged_app"

had_previous=0
if [ -e "$target_app" ]; then
    mv "$target_app" "$backup_app"
    had_previous=1
fi

if ! mv "$staged_app" "$target_app"; then
    if [ "$had_previous" -eq 1 ] && [ -e "$backup_app" ]; then
        mv "$backup_app" "$target_app"
    fi
    fail "could not install Daisy.app"
fi
staged_app=""

if [ "$had_previous" -eq 1 ]; then
    rm -rf "$backup_app"
fi

printf 'Installed Daisy at %s\n' "$target_app"

if [ "$no_launch" != "1" ]; then
    open "$target_app"
fi
