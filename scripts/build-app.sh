#!/bin/bash
set -euo pipefail

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_configuration="release"
build_universal=false
bundle_destination="$package_root/dist/PortLens.app"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) build_configuration="debug" ;;
        --universal) build_universal=true ;;
        --output)
            if [[ $# -lt 2 || "$2" != /* || "$2" != *.app ]]; then
                printf '%s\n' '--output requires an absolute .app path.' >&2
                exit 2
            fi
            bundle_destination="$2"
            shift
            ;;
        --help|-h)
            printf 'Usage: %s [--debug] [--universal] [--output /path/PortLens.app]\n' "$0"
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

build_architectures=("$(uname -m)")
if [[ "$build_universal" == true ]]; then
    build_architectures=(arm64 x86_64)
fi
mkdir -p "$(dirname "$bundle_destination")"
build_staging="$(mktemp -d "$(dirname "$bundle_destination")/.PortLens-build.XXXXXX")"
bundle_staging="$build_staging/PortLens.app"
mkdir -p "$bundle_staging/Contents/MacOS" "$bundle_staging/Contents/Resources"
trap 'rm -rf "$build_staging"' EXIT
build_executables=()
executable_directory=""
for build_architecture in "${build_architectures[@]}"; do
    swift build --package-path "$package_root" --configuration "$build_configuration" --arch "$build_architecture" --product PortLens
    architecture_directory="$(swift build --package-path "$package_root" --configuration "$build_configuration" --arch "$build_architecture" --show-bin-path)"
    # Some SwiftPM build systems share their product path across --arch builds.
    # Preserve each binary before the next build can replace that path.
    architecture_executable="$build_staging/PortLens-$build_architecture"
    cp "$architecture_directory/PortLens" "$architecture_executable"
    build_executables+=("$architecture_executable")
    if [[ -z "$executable_directory" ]]; then
        executable_directory="$architecture_directory"
    fi
done
if [[ "$build_universal" == true ]]; then
    xcrun lipo -create "${build_executables[@]}" -output "$bundle_staging/Contents/MacOS/PortLens"
else
    cp "${build_executables[0]}" "$bundle_staging/Contents/MacOS/PortLens"
fi
cp "$package_root/Resources/Info.plist" "$bundle_staging/Contents/Info.plist"
cp "$package_root/Resources/AppIcon.icns" "$bundle_staging/Contents/Resources/AppIcon.icns"
cp -R "$executable_directory/PortLens_PortLens.bundle" "$bundle_staging/Contents/Resources/"
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
