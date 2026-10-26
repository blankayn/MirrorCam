#!/usr/bin/env python3
"""Embed a user's private iPhone pairing record into a locally built MirrorStore IPA."""

from __future__ import annotations

import argparse
import os
import plistlib
import re
import tempfile
import zipfile
from pathlib import Path


def read_pairing_file(path: Path) -> tuple[str, str]:
    raw = path.read_bytes()
    if not raw or len(raw) > 1_000_000:
        raise SystemExit("Pairing file is empty or unexpectedly large.")
    try:
        record = plistlib.loads(raw)
    except plistlib.InvalidFileException as error:
        raise SystemExit(f"Pairing file must be a valid XML or binary plist: {error}")
    if not isinstance(record, dict):
        raise SystemExit("Pairing file does not contain a plist dictionary.")

    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        # SideStore's native client expects plist text. Convert Apple's binary
        # plist representation to XML while preserving the parsed values.
        text = plistlib.dumps(record, fmt=plistlib.FMT_XML, sort_keys=False).decode("utf-8")

    udid = next((record.get(key) for key in ("UDID", "UniqueDeviceID", "UniqueDeviceId") if isinstance(record.get(key), str)), None)
    if not udid:
        udid = path.stem
    if not re.fullmatch(r"[A-Fa-f0-9-]{20,64}", udid):
        raise SystemExit("Could not safely identify the iPhone UDID from the pairing record or its filename.")
    if "HostID" not in record or "HostPrivateKey" not in record:
        raise SystemExit("Pairing plist is missing the lockdown host identity fields SideStore needs.")
    if not isinstance(record["HostID"], str) or not isinstance(record["HostPrivateKey"], (str, bytes)):
        raise SystemExit("Pairing plist contains invalid lockdown host identity fields.")
    return udid, text


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path, help="Unsigned MirrorStore IPA from the macOS build")
    parser.add_argument("pairing_file", type=Path, help="Your iPhone .mobiledevicepairing file")
    parser.add_argument("--output", type=Path, help="Output IPA path; defaults to <name>-device.ipa")
    args = parser.parse_args()

    source = args.ipa.resolve()
    pairing_path = args.pairing_file.resolve()
    output = (args.output or source.with_name(f"{source.stem}-device.ipa")).resolve()
    if not source.is_file() or not zipfile.is_zipfile(source):
        raise SystemExit(f"Not an IPA/ZIP file: {source}")
    if not pairing_path.is_file():
        raise SystemExit(f"Pairing file not found: {pairing_path}")
    if source == output:
        raise SystemExit("Output must be a new file; the original IPA is kept unchanged.")
    if output.exists():
        raise SystemExit(f"Output already exists; choose another path: {output}")

    udid, pairing_text = read_pairing_file(pairing_path)
    with zipfile.ZipFile(source, "r") as archive:
        bad_entry = archive.testzip()
        if bad_entry:
            raise SystemExit(f"Input IPA is corrupt at {bad_entry}.")
        candidates = [
            item for item in archive.infolist()
            if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", item.filename)
        ]
        if len(candidates) != 1:
            raise SystemExit("IPA must contain exactly one Payload/*.app/Info.plist.")
        info_entry = candidates[0]
        info = plistlib.loads(archive.read(info_entry.filename))
        if not isinstance(info, dict) or not info.get("CFBundleIdentifier"):
            raise SystemExit("App Info.plist is invalid or has no bundle identifier.")
        if info.get("CFBundleDisplayName") not in (None, "MirrorStore"):
            raise SystemExit("This does not appear to be a MirrorStore IPA.")
        info["CFBundleDisplayName"] = "MirrorStore"
        info["ALTDeviceID"] = udid
        info["ALTPairingFile"] = pairing_text
        info["ALTAppGroups"] = []
        replacement = plistlib.dumps(info, fmt=plistlib.FMT_XML, sort_keys=False)

        output.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temp_name = tempfile.mkstemp(prefix=".mirrorstore-", suffix=".ipa", dir=output.parent)
        os.close(descriptor)
        try:
            with zipfile.ZipFile(temp_name, "w") as rewritten:
                rewritten.comment = archive.comment
                for item in archive.infolist():
                    data = replacement if item.filename == info_entry.filename else archive.read(item.filename)
                    rewritten.writestr(item, data)
            os.replace(temp_name, output)
        except Exception:
            try:
                os.unlink(temp_name)
            except FileNotFoundError:
                pass
            raise

    print(f"Prepared device-specific IPA: {output}")
    print("It contains your pairing identity. Keep it private; do not upload or share it.")
    print("The IPA still needs to be signed with your Apple ID in Sideloadly.")


if __name__ == "__main__":
    main()
