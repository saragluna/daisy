#!/bin/bash
set -e
cd "$(dirname "$0")"

swift build -c release

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
/bin/cp .build/release/Daisy build/Daisy.app/Contents/MacOS/Daisy
/bin/cp -rf .build/release/Daisy_Daisy.bundle build/Daisy.app/Contents/MacOS/

resource_directory=.build/release/Daisy_Daisy.bundle
if [ -d "$resource_directory/Contents/Resources" ]; then
    resource_directory="$resource_directory/Contents/Resources"
fi
/bin/cp -f "$resource_directory/AppIcon.icns" build/Daisy.app/Contents/Resources/AppIcon.icns

bundled_resource_directory=build/Daisy.app/Contents/MacOS/Daisy_Daisy.bundle
if [ -d "$bundled_resource_directory/Contents/Resources" ]; then
    bundled_resource_directory="$bundled_resource_directory/Contents/Resources"
fi

for runtime_file in litellm-requirements.txt litellm-runtime-version.txt; do
    if [ ! -f "$bundled_resource_directory/$runtime_file" ]; then
        echo "Missing bundled LiteLLM runtime file: $runtime_file" >&2
        exit 1
    fi
done

if [ "${1:-}" = "--build-only" ]; then
    exit 0
fi

killall Daisy 2>/dev/null && sleep 1 || true
open build/Daisy.app
