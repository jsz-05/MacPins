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
signing_identity="${MACPINS_CODE_SIGN_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
    signing_identity="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -n 1)"
fi
if [[ -z "$signing_identity" ]]; then
    signing_identity="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -n 1)"
fi
if [[ -z "$signing_identity" ]]; then
    signing_identity="-"
fi

if [[ "$signing_identity" == Developer\ ID\ Application:* ]]; then
    codesign --force --deep --options runtime --timestamp \
        --identifier app.macpins.utility --sign "$signing_identity" "$app_dir"
else
    codesign --force --deep --timestamp=none --identifier app.macpins.utility \
        --sign "$signing_identity" "$app_dir"
fi

echo "$app_dir"
