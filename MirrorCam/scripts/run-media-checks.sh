#!/bin/bash
set -euo pipefail
mkdir -p build
cat MirrorCam/FrameGeometry.swift MirrorCam/RollingBuffer.swift MirrorCam/ClipWriter.swift scripts/media-checks.swift > build/media-checks.swift
xcrun swiftc build/media-checks.swift -o build/media-checks
build/media-checks
