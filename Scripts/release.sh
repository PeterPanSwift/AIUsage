#!/bin/zsh
# Archive, export with Developer ID, notarize, staple, zip, and publish a GitHub release.
# One-time setup: xcrun notarytool store-credentials AIUsageNotary --apple-id <Apple ID> --team-id G4HL98LX6L
set -euo pipefail
cd "$(dirname "$0")/.."
PROFILE="${NOTARY_PROFILE:-AIUsageNotary}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Config/App-Info.plist)
ARCHIVE=build/AIUsage.xcarchive
EXPORT=build/export
ZIP="$EXPORT/AIUsage-$VERSION.zip"

xcodebuild -project AIUsage.xcodeproj -scheme AIUsage -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist Config/ExportOptions.plist \
  -exportPath "$EXPORT" -allowProvisioningUpdates

ditto -c -k --keepParent "$EXPORT/AIUsage.app" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$EXPORT/AIUsage.app"
rm -f "$ZIP"
ditto -c -k --keepParent "$EXPORT/AIUsage.app" "$ZIP"
spctl -a -vv -t exec "$EXPORT/AIUsage.app"

gh release create "v$VERSION" "$ZIP" --title "AI Usage $VERSION" --generate-notes "$@"
