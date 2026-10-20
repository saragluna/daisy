#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

build_only=0
universal=0

for argument in "$@"; do
    case "$argument" in
        --build-only) build_only=1 ;;
        --universal) universal=1 ;;
        *)
            echo "Unknown option: $argument" >&2
            exit 2
            ;;
    esac
done

temporary_dir=""
cleanup() {
    if [ -n "$temporary_dir" ] && [ -d "$temporary_dir" ]; then
        rm -rf "$temporary_dir"
    fi
}
trap cleanup EXIT

if [ "$universal" -eq 1 ]; then
    command -v lipo >/dev/null 2>&1 || {
        echo "lipo is required for a universal macOS build" >&2
        exit 1
    }

    temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/daisy-universal.XXXXXX")"

    for architecture in x86_64 arm64; do
        triple="${architecture}-apple-macosx14.0"
        swift build -c release --triple "$triple"
        architecture_output="$(swift build -c release --triple "$triple" --show-bin-path)"
        cp "$architecture_output/Daisy" "$temporary_dir/Daisy-$architecture"
        resource_output="$architecture_output/Daisy_Daisy.bundle"
    done
else
    swift build -c release
    build_output="$(swift build -c release --show-bin-path)"
    resource_output="$build_output/Daisy_Daisy.bundle"
fi

mkdir -p build/Daisy.app/Contents/{MacOS,Resources}

# Create Info.plist if missing
if [ ! -f build/Daisy.app/Contents/Info.plist ]; then
cat > build/Daisy.app/Contents/Info.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Daisy</string>
    <key>CFBundleIdentifier</key>
    <string>com.daisy.Daisy</string>
    <key>CFBundleName</key>
    <string>Daisy</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST
fi

/bin/rm -f build/Daisy.app/Contents/MacOS/Daisy
/bin/rm -rf build/Daisy.app/Contents/MacOS/Daisy_Daisy.bundle
/bin/rm -rf build/Daisy.app/Contents/Resources/Daisy_Daisy.bundle

if [ "$universal" -eq 1 ]; then
    lipo -create \
        "$temporary_dir/Daisy-x86_64" \
        "$temporary_dir/Daisy-arm64" \
        -output build/Daisy.app/Contents/MacOS/Daisy
else
    /bin/cp "$build_output/Daisy" build/Daisy.app/Contents/MacOS/Daisy
fi

/bin/cp -rf "$resource_output" build/Daisy.app/Contents/Resources/

resource_directory="$resource_output"
if [ -d "$resource_directory/Contents/Resources" ]; then
    resource_directory="$resource_directory/Contents/Resources"
fi
/bin/cp -f "$resource_directory/AppIcon.icns" build/Daisy.app/Contents/Resources/AppIcon.icns

bundled_resource_directory=build/Daisy.app/Contents/Resources/Daisy_Daisy.bundle
if [ -d "$bundled_resource_directory/Contents/Resources" ]; then
    bundled_resource_directory="$bundled_resource_directory/Contents/Resources"
fi

for runtime_file in litellm-requirements.txt litellm-runtime-version.txt; do
    if [ ! -f "$bundled_resource_directory/$runtime_file" ]; then
        echo "Missing bundled LiteLLM runtime file: $runtime_file" >&2
        exit 1
    fi
done

if [ "$build_only" -eq 1 ]; then
    exit 0
fi

killall Daisy 2>/dev/null && sleep 1 || true
open build/Daisy.app
