#!/bin/bash
set -euo pipefail

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$package_root/Resources/Info.plist")"
release_directory="$package_root/dist/releases"
archive_name="PortLens-$release_version-universal.zip"
checksum_name="PortLens-$release_version-SHA256SUMS.txt"

"$package_root/scripts/build-app.sh" --universal
bundle="$package_root/dist/PortLens.app"
codesign --verify --strict "$bundle"
xcrun lipo "$bundle/Contents/MacOS/PortLens" -verify_arch arm64 x86_64

mkdir -p "$release_directory"
temporary_archive="$release_directory/.$archive_name.$$"
trap 'rm -f "$temporary_archive"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$bundle" "$temporary_archive"
unzip -tq "$temporary_archive"
mv "$temporary_archive" "$release_directory/$archive_name"
(
    cd "$release_directory"
    shasum -a 256 "$archive_name" > "$checksum_name"
    shasum -a 256 -c "$checksum_name"
)
printf '\nRelease archive: %s\nChecksums: %s\n' "$release_directory/$archive_name" "$release_directory/$checksum_name"
