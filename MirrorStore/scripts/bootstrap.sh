#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_DIR="$REPO_ROOT/MirrorStore/build/upstream"
UPSTREAM_URL="https://github.com/SideStore/SideStore.git"
UPSTREAM_COMMIT="b3abf69a0280b4e86b56026e2741f43d6ef53c31"

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
    mkdir -p "$(dirname "$SOURCE_DIR")"
    git clone --no-checkout "$UPSTREAM_URL" "$SOURCE_DIR"
fi

git -C "$SOURCE_DIR" fetch --no-tags origin "$UPSTREAM_COMMIT"
git -C "$SOURCE_DIR" checkout --detach "$UPSTREAM_COMMIT"
git -C "$SOURCE_DIR" submodule sync --recursive
git -C "$SOURCE_DIR" submodule update --init --recursive

python3 "$REPO_ROOT/MirrorStore/scripts/patch_ios12.py" --source "$SOURCE_DIR"
