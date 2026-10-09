#!/bin/bash
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then
    printf '%s\n' 'IPA builds require macOS with Xcode. Use validate-project.py on Windows.' >&2
    exit 1
fi

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
build_mode="${1:-sideload}"
bundle_id="${3:-com.example.MirrorCam}"
xcode_major="$(xcodebuild -version | awk '/Xcode / {split($2, parts, "."); print parts[1]}')"
if [[ "$xcode_major" != 14 && "$xcode_major" != 15 ]]; then
    printf '%s\n' 'Use Xcode 14 or 15 for iOS 12. Xcode 15.4 is recommended. Select it with DEVELOPER_DIR.' >&2
    exit 1
fi
mkdir -p build
common=(-project MirrorCam.xcodeproj -scheme MirrorCam -configuration Release
        -destination 'generic/platform=iOS' ARCHS=arm64 ONLY_ACTIVE_ARCH=NO
        IPHONEOS_DEPLOYMENT_TARGET=12.0 "PRODUCT_BUNDLE_IDENTIFIER=$bundle_id")

if [[ "$build_mode" == sideload ]]; then
    xcodebuild "${common[@]}" -derivedDataPath build/DerivedData build \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
    app="$project_dir/build/DerivedData/Build/Products/Release-iphoneos/MirrorCam.app"
    test -f "$app/MirrorCam"
    /usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$app/Info.plist"
    xcrun lipo -info "$app/MirrorCam"
    package_dir="$(mktemp -d "$project_dir/build/package.XXXXXX")"
    mkdir -p "$package_dir/Payload"
    ditto "$app" "$package_dir/Payload/MirrorCam.app"
    ditto -c -k --keepParent "$package_dir/Payload" "$project_dir/build/MirrorCam-unsigned.ipa"
    printf '%s\n' 'Built build/MirrorCam-unsigned.ipa. Sideloadly must sign it before installation.'
elif [[ "$build_mode" == signed ]]; then
    team_id="${2:?Usage: bash scripts/build-ipa.sh signed TEAM_ID your.unique.bundle.id}"
    if [[ ! "$team_id" =~ ^[A-Z0-9]{10}$ ]]; then
        printf '%s\n' 'Expected a 10-character Apple Developer team ID.' >&2
        exit 1
    fi
    xcodebuild "${common[@]}" -archivePath build/MirrorCam.xcarchive \
        -allowProvisioningUpdates "DEVELOPMENT_TEAM=$team_id" archive
    cat > build/ExportOptions.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>development</string>
<key>signingStyle</key><string>automatic</string>
<key>teamID</key><string>$team_id</string>
<key>compileBitcode</key><false/>
<key>thinning</key><string>&lt;none&gt;</string>
</dict></plist>
EOF
    xcodebuild -exportArchive -archivePath build/MirrorCam.xcarchive \
        -exportPath build/Signed -exportOptionsPlist build/ExportOptions.plist -allowProvisioningUpdates
    printf '%s\n' 'Built build/Signed/MirrorCam.ipa. The development profile must include the target device.'
else
    printf '%s\n' 'Usage: bash scripts/build-ipa.sh [sideload | signed TEAM_ID BUNDLE_ID]' >&2
    exit 1
fi
