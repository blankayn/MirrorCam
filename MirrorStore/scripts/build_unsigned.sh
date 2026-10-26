#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
"$REPO_ROOT/MirrorStore/scripts/bootstrap.sh"
SOURCE_DIR="$REPO_ROOT/MirrorStore/build/upstream"

command -v xcodebuild >/dev/null || { echo "Xcode is required to compile the iOS app." >&2; exit 1; }
command -v ldid >/dev/null || { echo "Install ldid with Homebrew before packaging the IPA." >&2; exit 1; }

cd "$SOURCE_DIR"
make build
python3 "$REPO_ROOT/MirrorStore/scripts/verify_ios12_transport.py" "$SOURCE_DIR/Dependencies"
make fakesign ipa
mkdir -p "$REPO_ROOT/MirrorStore/dist"
cp -f MirrorStore.ipa "$REPO_ROOT/MirrorStore/dist/MirrorStore-unsigned.ipa"
echo "Built $REPO_ROOT/MirrorStore/dist/MirrorStore-unsigned.ipa"
echo "Build completion does not confirm iOS 12 runtime compatibility; test on the iPhone 6."
