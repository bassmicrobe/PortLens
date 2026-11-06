#!/bin/bash
set -euo pipefail

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    printf 'Usage: SIGNING_IDENTITY=<SHA1> TEAM_ID=<team> NOTARY_PROFILE=<profile> [SIGNING_KEYCHAIN=<path>] %s\n' "$0"
    printf 'Builds, signs, notarizes and verifies a Universal ZIP in dist/notarization/run-*/.\n'
    exit 0
fi
if [[ $# -ne 0 ]]; then
    printf 'Unexpected argument: %s\n' "$1" >&2
    exit 2
fi
: "${SIGNING_IDENTITY:?Set the Developer ID Application certificate SHA-1.}"
: "${TEAM_ID:?Set the expected Apple Developer Team ID.}"
: "${NOTARY_PROFILE:?Set an existing notarytool keychain profile.}"
if [[ ! "$SIGNING_IDENTITY" =~ ^[[:xdigit:]]{40}$ ]]; then
    printf 'SIGNING_IDENTITY must be a certificate SHA-1 fingerprint.\n' >&2
    exit 2
fi

signing_arguments=(--force --sign "$SIGNING_IDENTITY" --options runtime --timestamp)
if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then
    signing_arguments+=(--keychain "$SIGNING_KEYCHAIN")
    security find-identity -v -p codesigning "$SIGNING_KEYCHAIN" | grep -F "$SIGNING_IDENTITY" | grep -F 'Developer ID Application:'
else
    security find-identity -v -p codesigning | grep -F "$SIGNING_IDENTITY" | grep -F 'Developer ID Application:'
fi
xcrun notarytool --version

mkdir -p "$package_root/dist/notarization"
run_directory="$(mktemp -d "$package_root/dist/notarization/run-$(date +%Y%m%d-%H%M%S).XXXXXX")"
bundle="$run_directory/PortLens.app"
printf 'Notarization work directory: %s\n' "$run_directory"
trap 'result=$?; if [[ $result -ne 0 ]]; then printf "Stopped; work and Apple submission details are retained in %s\n" "$run_directory" >&2; fi' EXIT
{
    git -C "$package_root" rev-parse HEAD
    git -C "$package_root" status --short
    xcrun swift --version
} > "$run_directory/build-context.txt"

"$package_root/scripts/build-app.sh" --universal --output "$bundle"
for architecture in arm64 x86_64; do
    xcrun lipo "$bundle/Contents/MacOS/PortLens" -verify_arch "$architecture"
done

# This app currently has one executable and resource-only bundles. If embedded
# code is added, define its signing order and entitlements before releasing it.
while IFS= read -r -d '' bundle_file; do
    if [[ "$bundle_file" != "$bundle/Contents/MacOS/PortLens" ]] && file -b "$bundle_file" | grep -q 'Mach-O'; then
        printf 'Embedded executable needs an explicit signing policy: %s\n' "$bundle_file" >&2
        exit 1
    fi
done < <(find "$bundle" -type f -print0)

codesign "${signing_arguments[@]}" "$bundle"
codesign --verify --deep --strict --verbose=2 "$bundle"
codesign -d --verbose=4 "$bundle" 2> "$run_directory/signature.txt"
grep -Fx "TeamIdentifier=$TEAM_ID" "$run_directory/signature.txt"
grep -F 'Authority=Developer ID Application:' "$run_directory/signature.txt"
grep -E '^flags=.*runtime|^CodeDirectory .*flags=.*runtime' "$run_directory/signature.txt"
grep -E '^Timestamp=' "$run_directory/signature.txt"

ditto -c -k --sequesterRsrc --keepParent "$bundle" "$run_directory/submission.zip"
xcrun notarytool submit "$run_directory/submission.zip" --keychain-profile "$NOTARY_PROFILE" --output-format json > "$run_directory/submission.json"
submission_id="$(plutil -extract id raw -o - "$run_directory/submission.json")"
printf 'Apple submission: %s\n' "$submission_id"
if ! xcrun notarytool wait "$submission_id" --keychain-profile "$NOTARY_PROFILE" --timeout 30m --output-format json > "$run_directory/status.json"; then
    printf 'Check or resume the existing submission with notarytool info/wait %s; do not resubmit it.\n' "$submission_id" >&2
    exit 1
fi
xcrun notarytool log "$submission_id" --keychain-profile "$NOTARY_PROFILE" "$run_directory/notary-log.json"
status="$(plutil -extract status raw -o - "$run_directory/status.json")"
if [[ "$status" != Accepted ]]; then
    printf 'Apple status: %s. See notary-log.json.\n' "$status" >&2
    exit 1
fi

xcrun stapler staple "$bundle"
xcrun stapler validate "$bundle"
codesign --verify --deep --strict --verbose=2 "$bundle"
spctl --assess --type execute --verbose=2 "$bundle" 2> "$run_directory/gatekeeper.txt"
grep -F 'source=Notarized Developer ID' "$run_directory/gatekeeper.txt"

release_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$bundle/Contents/Info.plist")"
archive_name="PortLens-$release_version-universal-notarized.zip"
checksum_name="PortLens-$release_version-notarized-SHA256SUMS.txt"
ditto -c -k --sequesterRsrc --keepParent "$bundle" "$run_directory/$archive_name"
unzip -tq "$run_directory/$archive_name"
(
    cd "$run_directory"
    shasum -a 256 "$archive_name" > "$checksum_name"
    shasum -a 256 -c "$checksum_name"
)

mkdir "$run_directory/extracted"
ditto -x -k "$run_directory/$archive_name" "$run_directory/extracted"
extracted_bundle="$run_directory/extracted/PortLens.app"
xcrun stapler validate "$extracted_bundle"
codesign --verify --deep --strict --verbose=2 "$extracted_bundle"
for architecture in arm64 x86_64; do
    xcrun lipo "$extracted_bundle/Contents/MacOS/PortLens" -verify_arch "$architecture"
done
spctl --assess --type execute --verbose=2 "$extracted_bundle" 2> "$run_directory/extracted-gatekeeper.txt"
grep -F 'source=Notarized Developer ID' "$run_directory/extracted-gatekeeper.txt"
printf '\nApple status: Accepted\nVerified release archive: %s\nChecksums: %s\n' "$run_directory/$archive_name" "$run_directory/$checksum_name"
