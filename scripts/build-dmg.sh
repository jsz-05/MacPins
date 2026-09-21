#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_path="${1:-$project_dir/dist/MacPins.app}"
output_path="${2:-$project_dir/dist/MacPins.dmg}"

if [[ ! -d "$app_path" ]]; then
    echo "App bundle not found: $app_path" >&2
    exit 1
fi

staging_dir="$(mktemp -d)"
trap 'rm -rf "$staging_dir"' EXIT

ditto "$app_path" "$staging_dir/MacPins.app"
ln -s /Applications "$staging_dir/Applications"

hdiutil create \
    -volname "MacPins" \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDZO \
    "$output_path"

echo "$output_path"
