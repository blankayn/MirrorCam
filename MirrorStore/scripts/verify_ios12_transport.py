#!/usr/bin/env python3
"""Reject source-built device transport archives that declare iOS > 12.2."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


MAXIMUM_IOS = (12, 2)


def version_tuple(value: str) -> tuple[int, ...]:
    return tuple(int(part) for part in value.split("."))


def archive_minimums(path: Path) -> list[tuple[int, ...]]:
    file_result = subprocess.run(["file", "-b", str(path)], check=True, capture_output=True, text=True)
    if "archive" not in file_result.stdout.lower():
        return []

    result = subprocess.run(["otool", "-l", str(path)], check=True, capture_output=True, text=True)
    minima: list[tuple[int, ...]] = []
    for block in re.split(r"(?=^Load command \d+\s*$)", result.stdout, flags=re.MULTILINE):
        if "cmd LC_BUILD_VERSION" in block:
            match = re.search(r"(?m)^\s*minos\s+(\d+(?:\.\d+){1,2})\s*$", block)
        elif "cmd LC_VERSION_MIN_IPHONEOS" in block:
            match = re.search(r"(?m)^\s*version\s+(\d+(?:\.\d+){1,2})\s*$", block)
        else:
            continue
        if match:
            minima.append(version_tuple(match.group(1)))
    return minima


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dependencies", type=Path, help="SideStore Dependencies directory after xcodebuild")
    args = parser.parse_args()
    if sys.platform != "darwin":
        raise SystemExit("Transport minimum-version inspection requires macOS Xcode command-line tools.")

    archives = [
        args.dependencies / "minimuxer" / "libminimuxer-ios.a",
        args.dependencies / "em_proxy" / "libem_proxy-ios.a",
        args.dependencies / "em_proxy" / "libem_proxy.a",
    ]
    missing = [path for path in archives if not path.is_file()]
    if missing:
        raise SystemExit("Required source-built transport archive is missing: " + ", ".join(map(str, missing)))

    failures: list[str] = []
    for archive in sorted(archives):
        minima = archive_minimums(archive)
        if not minima:
            failures.append(f"{archive}: no iOS minimum-version metadata found")
            continue
        incompatible = [value for value in minima if value > MAXIMUM_IOS]
        if incompatible:
            displayed = ", ".join(".".join(map(str, value)) for value in sorted(set(incompatible)))
            failures.append(f"{archive}: requires iOS {displayed}; MirrorStore targets iOS 12.2")
        else:
            print(f"iOS 12.2 compatible metadata: {archive}")

    if failures:
        raise SystemExit("Transport compatibility check failed:\n- " + "\n- ".join(failures))

    print("All discovered device transport archives declare a minimum OS of iOS 12.2 or earlier.")
    print("This checks deployment metadata only; it does not prove runtime compatibility.")


if __name__ == "__main__":
    main()
