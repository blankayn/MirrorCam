#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_DIR="$REPO_ROOT/MirrorStore/build/upstream"
DEPENDENCIES="$SOURCE_DIR/Dependencies"
TRANSPORT_ROOT="$REPO_ROOT/MirrorStore/build/transport-sources"

# Pin source revisions instead of consuming mutable release assets built with
# whichever iOS SDK happens to be current at the time of the workflow run.
MINIMUXER_COMMIT="f9432a085b19de1bbcd744c600f510f499703a97"
EM_PROXY_COMMIT="6e117e140ca7cff4ff106bdefa18147552a0e592"
MINIMUXER_SOURCE="$TRANSPORT_ROOT/minimuxer"
EM_PROXY_SOURCE="$TRANSPORT_ROOT/em_proxy"

clone_at_commit() {
    local repository="$1"
    local destination="$2"
    local commit="$3"

    if [[ ! -d "$destination/.git" ]]; then
        git clone --no-checkout "$repository" "$destination"
    fi
    git -C "$destination" fetch --no-tags origin "$commit"
    git -C "$destination" checkout --detach "$commit"
}

command -v cargo >/dev/null || { echo "Rust Cargo is required to build the pinned iOS 12 transport libraries." >&2; exit 1; }
command -v rustup >/dev/null || { echo "Rustup is required to install the iOS target." >&2; exit 1; }
command -v xcrun >/dev/null || { echo "Xcode command-line tools are required to build the transport libraries." >&2; exit 1; }

mkdir -p "$TRANSPORT_ROOT" "$DEPENDENCIES/minimuxer" "$DEPENDENCIES/em_proxy"
rustup target add aarch64-apple-ios

clone_at_commit "https://github.com/SideStore/minimuxer.git" "$MINIMUXER_SOURCE" "$MINIMUXER_COMMIT"
clone_at_commit "https://github.com/SideStore/em_proxy.git" "$EM_PROXY_SOURCE" "$EM_PROXY_COMMIT"

cd "$MINIMUXER_SOURCE"
IPHONEOS_DEPLOYMENT_TARGET=12.2 cargo build --release --target aarch64-apple-ios
cp target/aarch64-apple-ios/release/libminimuxer.a "$DEPENDENCIES/minimuxer/libminimuxer-ios.a"
cp generated/* "$DEPENDENCIES/minimuxer/"

IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
cd "$EM_PROXY_SOURCE"
BINDGEN_EXTRA_CLANG_ARGS="--sysroot=$IOS_SDK" IPHONEOS_DEPLOYMENT_TARGET=12.2 cargo build --release --target aarch64-apple-ios
cp target/aarch64-apple-ios/release/libem_proxy.a "$DEPENDENCIES/em_proxy/libem_proxy-ios.a"
cp target/aarch64-apple-ios/release/libem_proxy.a "$DEPENDENCIES/em_proxy/libem_proxy.a"
cp include/EMProxy/em_proxy.h "$DEPENDENCIES/em_proxy/em_proxy.h"

# The Xcode subprojects otherwise replace these source-built archives with
# mutable release downloads during their build phases.
touch "$DEPENDENCIES/.skip-prebuilt-fetch-minimuxer"
touch "$DEPENDENCIES/.skip-prebuilt-fetch-em_proxy"

echo "Source-built iOS transport libraries from minimuxer $MINIMUXER_COMMIT and em_proxy $EM_PROXY_COMMIT."
echo "Their actual deployment metadata will be checked after the Xcode archive is built."
