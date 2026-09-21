#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
output_dir="$project_dir/dist"
app_dir="$output_dir/MacPins.app"

cd "$project_dir"
swift build -c release --scratch-path .build-arm64 --triple arm64-apple-macosx14.0
swift build -c release --scratch-path .build-x86_64 --triple x86_64-apple-macosx14.0

mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Resources"
lipo -create \
    ".build-arm64/release/MacPins" \
    ".build-x86_64/release/MacPins" \
    -output "$app_dir/Contents/MacOS/MacPins"
cp "Info.plist" "$app_dir/Contents/Info.plist"
iconset_dir="$project_dir/.build-icon/AppIcon.iconset"
swift "$project_dir/Tools/GenerateIcon.swift" "$iconset_dir"
iconutil -c icns "$iconset_dir" -o "$app_dir/Contents/Resources/AppIcon.icns"
signing_identity="${MACPINS_CODE_SIGN_IDENTITY:-Apple Development: jeffreyzhou3@icloud.com (84Z3774UP9)}"
if ! security find-identity -v -p codesigning | grep -Fq "\"$signing_identity\""; then
    echo "Required stable code-signing identity was not found: $signing_identity" >&2
    exit 1
fi
codesign --force --deep --timestamp=none --identifier app.macpins.utility \
    --sign "$signing_identity" "$app_dir"

echo "$app_dir"
