#!/bin/bash
# Builds Skypane in Release and packages it as a drag-to-Applications .dmg in dist/.
#
# Without settings, the app is signed only for this Mac (fine for testing).
# For a download that opens on other Macs, set both of these first:
#   DEVELOPER_ID   Your "Developer ID Application: Name (TEAMID)" signing identity
#   NOTARY_PROFILE A notarytool keychain profile, made once with:
#                  xcrun notarytool store-credentials <profile-name> --apple-id <email> --team-id <TEAMID>
# Example: DEVELOPER_ID="Developer ID Application: Jane Doe (ABCDE12345)" NOTARY_PROFILE=skypane scripts/make-dmg.sh
set -euo pipefail

cd "$(dirname "$0")/.."
build_directory="build/release"
output_directory="dist"

# Build in Release, signed with the Developer ID when one is given.
build_arguments=(-project Skypane.xcodeproj -scheme Skypane -configuration Release -destination "generic/platform=macOS" -derivedDataPath "$build_directory")
if [ -n "${DEVELOPER_ID:-}" ]; then
    build_arguments+=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$DEVELOPER_ID" "OTHER_CODE_SIGN_FLAGS=--timestamp")
fi
xcodebuild "${build_arguments[@]}" build | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" || true

app_path="$build_directory/Build/Products/Release/Skypane.app"
if [ ! -d "$app_path" ]; then
    echo "The build didn't produce Skypane.app; see the errors above." >&2
    exit 1
fi
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$app_path/Contents/Info.plist")

# Lay out the disk image: the app next to a shortcut to Applications.
staging_directory=$(mktemp -d)
trap 'rm -rf "$staging_directory"' EXIT
cp -R "$app_path" "$staging_directory/"
ln -s /Applications "$staging_directory/Applications"

mkdir -p "$output_directory"
disk_image="$output_directory/Skypane-$version.dmg"
rm -f "$disk_image"
if ! diskutil image create from --format UDZO --volumeName "Skypane" "$staging_directory" "$disk_image" >/dev/null 2>&1; then
    echo "Couldn't create the disk image." >&2
    exit 1
fi

# Sign and notarize the disk image so Gatekeeper accepts it on other Macs.
if [ -n "${DEVELOPER_ID:-}" ]; then
    codesign --sign "$DEVELOPER_ID" --timestamp "$disk_image"
fi
if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$disk_image" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$disk_image"
fi

echo "Created $disk_image"
if [ -z "${DEVELOPER_ID:-}" ] || [ -z "${NOTARY_PROFILE:-}" ]; then
    echo "Note: not signed with a Developer ID and notarized, so other Macs will block it. See the top of this script."
fi
