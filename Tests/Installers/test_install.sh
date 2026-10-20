#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "$0")/../.." && pwd)"
archive_under_test="${1:-}"
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/daisy-installer-test.XXXXXX")"
release_dir="$temporary_dir/release"
source_dir="$temporary_dir/source"
install_dir="$temporary_dir/Applications"
test_bin="$temporary_dir/bin"

cleanup() {
    rm -rf "$temporary_dir"
}
trap cleanup EXIT

mkdir -p "$test_bin"
if [ -z "$archive_under_test" ] || [ "${DAISY_REQUIRE_TRUSTED_ARCHIVE:-0}" != "1" ]; then
    cat > "$test_bin/codesign" <<'EOF'
#!/bin/sh
exit "${DAISY_TEST_CODESIGN_EXIT:-0}"
EOF
    cat > "$test_bin/spctl" <<'EOF'
#!/bin/sh
exit "${DAISY_TEST_SPCTL_EXIT:-0}"
EOF
    chmod +x "$test_bin/codesign" "$test_bin/spctl"
fi

create_release() {
    release_version="$1"
    rm -rf "$release_dir" "$source_dir"
    mkdir -p "$release_dir" "$source_dir/Daisy.app/Contents/MacOS"

    printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$release_version" \
        > "$source_dir/Daisy.app/Contents/MacOS/Daisy"
    chmod +x "$source_dir/Daisy.app/Contents/MacOS/Daisy"
    printf '%s\n' "$release_version" > "$source_dir/Daisy.app/version.txt"

    ditto -c -k --sequesterRsrc --keepParent \
        "$source_dir/Daisy.app" "$release_dir/Daisy-macOS.zip"
    (
        cd "$release_dir"
        shasum -a 256 Daisy-macOS.zip > SHA256SUMS
    )
}

run_installer() {
    PATH="$test_bin:$PATH" \
    DAISY_DOWNLOAD_BASE_URL="file://$release_dir" \
    DAISY_INSTALL_DIR="$install_dir" \
    DAISY_NO_LAUNCH=1 \
        bash "$repository_root/install.sh"
}

if [ -n "$archive_under_test" ]; then
    archive_under_test="$(cd "$(dirname "$archive_under_test")" && pwd)/$(basename "$archive_under_test")"
    mkdir -p "$release_dir"
    cp "$archive_under_test" "$release_dir/Daisy-macOS.zip"
    (
        cd "$release_dir"
        shasum -a 256 Daisy-macOS.zip > SHA256SUMS
    )
    run_installer
    test -x "$install_dir/Daisy.app/Contents/MacOS/Daisy"
    printf 'Packaged macOS installer test passed\n'
    exit 0
fi

create_release "first"
run_installer

test -x "$install_dir/Daisy.app/Contents/MacOS/Daisy"
test "$(cat "$install_dir/Daisy.app/version.txt")" = "first"

touch "$install_dir/Daisy.app/stale-file"
create_release "second"
run_installer

test "$(cat "$install_dir/Daisy.app/version.txt")" = "second"
test ! -e "$install_dir/Daisy.app/stale-file"

create_release "invalid-signature"
if DAISY_TEST_CODESIGN_EXIT=1 run_installer; then
    echo "installer accepted an app with an invalid Developer ID signature" >&2
    exit 1
fi

test "$(cat "$install_dir/Daisy.app/version.txt")" = "second"

create_release "untrusted"
if DAISY_TEST_SPCTL_EXIT=1 run_installer; then
    echo "installer accepted an app rejected by Gatekeeper" >&2
    exit 1
fi

test "$(cat "$install_dir/Daisy.app/version.txt")" = "second"

create_release "corrupt"
printf '%064d  Daisy-macOS.zip\n' 0 > "$release_dir/SHA256SUMS"

if run_installer; then
    echo "installer accepted a bad checksum" >&2
    exit 1
fi

test "$(cat "$install_dir/Daisy.app/version.txt")" = "second"
printf 'macOS installer tests passed\n'
