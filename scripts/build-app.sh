#!/bin/bash
set -euo pipefail

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_configuration="release"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) build_configuration="debug" ;;
        --help|-h)
            printf 'Usage: %s [--debug]\n' "$0"
            printf 'Builds dist/PortLens.app (release by default).\n'
            exit 0
            ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

if [[ "$(uname -s)" != "Darwin" ]]; then
    printf 'PortLens requires macOS 14 or later.\n' >&2
    exit 1
fi

swift build --package-path "$package_root" --configuration "$build_configuration" --product PortLens
executable_directory="$(swift build --package-path "$package_root" --configuration "$build_configuration" --show-bin-path)"
bundle_destination="$package_root/dist/PortLens.app"
bundle_staging="$package_root/dist/.PortLens.app.build.$$"

mkdir -p "$bundle_staging/Contents/MacOS" "$bundle_staging/Contents/Resources"
trap 'rm -rf "$bundle_staging"' EXIT
cp "$executable_directory/PortLens" "$bundle_staging/Contents/MacOS/PortLens"
cp "$package_root/Resources/Info.plist" "$bundle_staging/Contents/Info.plist"
cp "$package_root/Resources/AppIcon.icns" "$bundle_staging/Contents/Resources/AppIcon.icns"
chmod 755 "$bundle_staging/Contents/MacOS/PortLens"
plutil -lint "$bundle_staging/Contents/Info.plist"

if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - --timestamp=none "$bundle_staging"
    codesign --verify --strict "$bundle_staging"
    printf 'Applied an ad-hoc signature for local use; this is not notarization.\n'
fi

# Only replace the generated bundle after the new build has succeeded.
if [[ -e "$bundle_destination" ]]; then
    rm -rf "$bundle_destination"
fi
mv "$bundle_staging" "$bundle_destination"
printf '\nBuilt: %s\n' "$bundle_destination"
printf 'Launch with: open "%s"\n' "$bundle_destination"
