#!/usr/bin/env python3
"""Apply the small, deterministic MirrorStore compatibility patch to SideStore 0.4.0."""

from __future__ import annotations

import argparse
import plistlib
import re
import subprocess
from pathlib import Path


UPSTREAM_COMMIT = "b3abf69a0280b4e86b56026e2741f43d6ef53c31"
APP_TARGET_CONFIGS = {
    "19104DB72909C06D00C49C7B", "19104DB82909C06D00C49C7B",  # em_proxy static library
    "191E5FB0290A5D92001A3B7C", "191E5FB1290A5D92001A3B7C",  # minimuxer static library
    "BF66EE872501AE50007EE018", "BF66EE882501AE50007EE018",  # AltStoreCore
    "BFD2477F2284B9A700981D42", "BFD247802284B9A700981D42",  # iOS app
}


def require_file(root: Path, relative: str) -> Path:
    path = root / relative
    if not path.is_file():
        raise SystemExit(f"Expected upstream file is missing: {relative}")
    return path


def set_text(path: Path, transform) -> None:
    original = path.read_text(encoding="utf-8")
    updated = transform(original)
    if updated != original:
        path.write_text(updated, encoding="utf-8", newline="")


def patch_project(project_file: Path) -> None:
    text = project_file.read_text(encoding="utf-8")
    for config_id in APP_TARGET_CONFIGS:
        pattern = re.compile(
            rf"(?ms)(^\t\t{config_id} /\* [^*]+ \*/ = \{{.*?^\t\t\}};)",
        )
        match = pattern.search(text)
        if match is None:
            raise SystemExit(f"Could not locate Xcode build configuration {config_id}.")
        block = match.group(1)
        if "IPHONEOS_DEPLOYMENT_TARGET = 14.0;" in block:
            block = block.replace("IPHONEOS_DEPLOYMENT_TARGET = 14.0;", "IPHONEOS_DEPLOYMENT_TARGET = 12.2;", 1)
        elif "IPHONEOS_DEPLOYMENT_TARGET = 12.2;" not in block:
            raise SystemExit(f"Unexpected deployment target in Xcode configuration {config_id}.")
        text = text[:match.start(1)] + block + text[match.end(1):]
    text = re.sub(r"\s*com\.apple\.Push = \{\s*enabled = 1;\s*\};", "", text, count=1)
    app_target = re.compile(r"(?ms)^\t\tBFD247692284B9A500981D42 /\* SideStore \*/ = \{.*?^\t\t\};")
    match = app_target.search(text)
    if match is None:
        raise SystemExit("Could not locate the iOS app target for compatibility changes.")
    block = match.group(0)
    block = re.sub(r"(?m)^\t{4}BF989176250AABF4002ACF50 /\* PBXTargetDependency \*/,\r?\n", "", block)
    text = text[:match.start()] + block + text[match.end():]
    text = text.replace("\t\t\t\tBF989177250AABF4002ACF50 /* AltWidgetExtension.appex in Embed App Extensions */,\n", "")
    project_file.write_text(text, encoding="utf-8", newline="")


def patch_info_plist(path: Path) -> None:
    with path.open("rb") as stream:
        info = plistlib.load(stream)
    info["CFBundleDisplayName"] = "MirrorStore"
    info["ALTDeviceID"] = "DEVICE-ID-SET-DURING-IPA-PREPARATION"
    info["ALTPairingFile"] = "PAIRING-FILE-SET-DURING-IPA-PREPARATION"
    info["ALTAppGroups"] = []
    info["ALTAnisetteURL"] = "https://ani.sidestore.io"
    info["NSLocalNetworkUsageDescription"] = "MirrorStore uses the local network for its on-device app refresh connection."
    info["UIBackgroundModes"] = [mode for mode in info.get("UIBackgroundModes", []) if mode != "remote-notification"]
    info.pop("NSAppTransportSecurity", None)
    with path.open("wb") as stream:
        plistlib.dump(info, stream, fmt=plistlib.FMT_XML, sort_keys=False)


def clear_free_account_entitlements(path: Path) -> None:
    # The free Personal Team cannot provision Siri, push, or App Group entitlements.
    with path.open("wb") as stream:
        plistlib.dump({}, stream, fmt=plistlib.FMT_XML, sort_keys=False)


def patch_launch_controller(path: Path) -> None:
    source = path.read_text(encoding="utf-8")
    source = source.replace("import UniformTypeIdentifiers\n", "import MobileCoreServices\n")
    old = '''                var types = UTType.types(tag: "plist", tagClass: UTTagClass.filenameExtension, conformingTo: nil)
                types.append(contentsOf: UTType.types(tag: "mobiledevicepairing", tagClass: UTTagClass.filenameExtension, conformingTo: UTType.data))
                types.append(.xml)
                let documentPickerController = UIDocumentPickerViewController(forOpeningContentTypes: types)'''
    new = '''                let types = ["public.xml", "public.data", "org.sidestore.mobiledevicepairing"]
                let documentPickerController = UIDocumentPickerViewController(documentTypes: types, in: .import)'''
    if old in source:
        source = source.replace(old, new, 1)
    elif "UIDocumentPickerViewController(documentTypes: types, in: .import)" not in source:
        raise SystemExit("Could not find the iOS 14 pairing-file picker code to backport.")
    old_path = 'let documentsPath = fm.documentsDirectory.appendingPathComponent("/\\(filename)")'
    source = source.replace(old_path, 'let documentsPath = fm.documentsDirectory.appendingPathComponent(filename)')
    old_info_pair = '''        } else if let plistString = Bundle.main.object(forInfoDictionaryKey: "ALTPairingFile") as? String, !plistString.isEmpty, !plistString.contains("insert pairing file here"){
            print("Loaded ALTPairingFile from Info.plist")
            return plistString'''
    new_info_pair = '''        } else if let plistString = Bundle.main.object(forInfoDictionaryKey: "ALTPairingFile") as? String, !plistString.isEmpty, !plistString.contains("PAIRING-FILE-SET-DURING-IPA-PREPARATION") {
            let pairingFile = fm.documentsDirectory.appendingPathComponent(filename)
            do {
                try plistString.write(to: pairingFile, atomically: true, encoding: .utf8)
            } catch {
                displayError("Unable to save the pairing file into MirrorStore.")
                return nil
            }
            print("Loaded the embedded pairing file and saved a local copy.")
            return plistString'''
    if old_info_pair in source:
        source = source.replace(old_info_pair, new_info_pair, 1)
    elif "Loaded the embedded pairing file and saved a local copy." not in source:
        raise SystemExit("Could not add the local pairing-file copy used by background refresh.")
    path.write_text(source, encoding="utf-8", newline="")


def patch_analytics(path: Path) -> None:
    # Keep call sites source-compatible while disabling the upstream App Center event stream.
    replacement = '''// MirrorStore does not send install or usage analytics.
import Foundation
import AltStoreCore

final class AnalyticsManager
{
    enum Event
    {
        case installedApp(InstalledApp)
        case updatedApp(InstalledApp)
        case refreshedApp(InstalledApp)
    }

    static let shared = AnalyticsManager()
    private init() {}

    func start() {}
    func trackEvent(_ event: Event) {}
}
'''
    original = path.read_text(encoding="utf-8")
    if "import AppCenter" in original:
        path.write_text(replacement, encoding="utf-8", newline="")
    elif "does not send install or usage analytics" not in original:
        raise SystemExit("Unexpected AnalyticsManager source; refusing to overwrite it.")


def redact_anisette_logs(path: Path) -> None:
    source = path.read_text(encoding="utf-8")
    replacements = [
        (r'print\("Anisette used:.*', 'print("Anisette response parsed; values redacted.")'),
        (r'print\("Original JSON:.*', '// Never log raw Anisette server responses.'),
        (r'print\("Apple didn.t give valid URLs! Got response:.*', 'print("Apple did not return valid provisioning URLs.")'),
        (r'print\("Apple didn.t give valid start provisioning data! Got response:.*', 'print("Apple did not return valid provisioning start data.")'),
        (r'print\("Apple didn.t give valid end provisioning data! Got response:.*', 'print("Apple did not return valid provisioning completion data.")'),
        (r'print\("Client-Info:.*', 'print("Anisette client info received; value redacted.")'),
        (r'print\("User-Agent:.*', 'print("Anisette user-agent received; value redacted.")'),
        (r'print\("X-Apple-I-MD-LU:.*', 'print("Anisette local user identifier generated; value redacted.")'),
        (r'print\("X-Mme-Device-Id:.*', 'print("Anisette device identifier generated; value redacted.")'),
    ]
    for pattern, replacement in replacements:
        source, count = re.subn(rf"(?m)^(\s*){pattern}", rf"\1{replacement}", source, count=1)
        if count == 0 and replacement not in source:
            raise SystemExit("Could not redact one expected Anisette diagnostic; check the source revision.")
    path.write_text(source, encoding="utf-8", newline="")


def patch_branding(root: Path) -> None:
    xcconfig = require_file(root, "AltStore.xcconfig")
    set_text(xcconfig, lambda s: s.replace("$(ORG_PREFIX).SideStore", "$(ORG_PREFIX).MirrorStore"))

    build = require_file(root, "Build.xcconfig")
    def update_build(s: str) -> str:
        s = s.replace("DEVELOPMENT_TEAM = S32Z3HMYVQ", "DEVELOPMENT_TEAM =")
        s = s.replace("ORG_IDENTIFIER = com.SideStore", "ORG_IDENTIFIER = com.blankayn")
        s = re.sub(r"(\$\(ORG_PREFIX\)\.)SideStore", r"\1MirrorStore", s)
        return s
    set_text(build, update_build)

    makefile = require_file(root, "Makefile")
    set_text(makefile, lambda s: s.replace("ORG_IDENTIFIER=com.SideStore", "ORG_IDENTIFIER=com.blankayn").replace("SideStore.ipa", "MirrorStore.ipa"))

    for relative in (
        "AltStore/Authentication/Authentication.storyboard",
        "AltStore/Settings/Settings.storyboard",
    ):
        path = require_file(root, relative)
        def update_storyboard(s: str) -> str:
            s = re.sub(r'(text="[^"]*)SideStore', r'\1MirrorStore', s)
            s = s.replace(
                "Enable MirrorStore VPN in Wireguard and be able to use Sidestore on the go.",
                "Enable the MirrorStore VPN in WireGuard before refreshing apps on this iPhone.",
            )
            return s
        set_text(path, update_storyboard)


def patch_transport_fetcher(root: Path) -> None:
    fetcher = require_file(root, "Dependencies/fetch-prebuilt.sh")
    def pin_legacy_asset_route(source: str) -> str:
        source = source.replace("/releases/latest/download/", "/releases/download/build/")
        if "/releases/download/build/" not in source:
            raise SystemExit("Could not route legacy transport binary downloads to the build release tag.")
        return source
    set_text(fetcher, pin_legacy_asset_route)


def verify_clean_patch(root: Path) -> None:
    launch = require_file(root, "AltStore/LaunchViewController.swift").read_text(encoding="utf-8")
    anisette = require_file(root, "AltStore/Operations/FetchAnisetteDataOperation.swift").read_text(encoding="utf-8")
    info = plistlib.loads(require_file(root, "AltStore/Info.plist").read_bytes())
    if "UniformTypeIdentifiers" in launch or "UTType." in launch or "forOpeningContentTypes" in launch:
        raise SystemExit("iOS 14 document-picker APIs remain in LaunchViewController.swift.")
    if "Original JSON:" in anisette or "Anisette used:" in anisette:
        raise SystemExit("Anisette secrets are still logged.")
    if info.get("ALTDeviceID") != "DEVICE-ID-SET-DURING-IPA-PREPARATION":
        raise SystemExit("MirrorStore Info.plist does not contain the pairing setup placeholder.")
    if info.get("ALTAnisetteURL") != "https://ani.sidestore.io":
        raise SystemExit("Anisette URL is not HTTPS.")
    build = require_file(root, "Build.xcconfig").read_text(encoding="utf-8")
    if "PRODUCT_BUNDLE_IDENTIFIER   = $(ORG_PREFIX).MirrorStore" not in build:
        raise SystemExit("MirrorStore bundle identifier was not applied to the app build settings.")
    if "PRODUCT_BUNDLE_IDENTIFIER[config=Debug] = $(ORG_PREFIX).MirrorStore.$(DEVELOPMENT_TEAM)" not in build:
        raise SystemExit("MirrorStore debug bundle identifier was not applied to the app build settings.")
    fetcher = require_file(root, "Dependencies/fetch-prebuilt.sh").read_text(encoding="utf-8")
    if "/releases/latest/download/" in fetcher or "/releases/download/build/" not in fetcher:
        raise SystemExit("Legacy transport assets are not being fetched from the expected build release route.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True, help="Path to the clean SideStore 0.4.0 checkout")
    args = parser.parse_args()
    root = args.source.resolve()
    try:
        revision = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    except (OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Could not read the upstream Git revision: {error}")
    if revision != UPSTREAM_COMMIT:
        raise SystemExit(f"Expected SideStore commit {UPSTREAM_COMMIT}, got {revision}. No files changed.")

    patch_project(require_file(root, "AltStore.xcodeproj/project.pbxproj"))
    patch_info_plist(require_file(root, "AltStore/Info.plist"))
    clear_free_account_entitlements(require_file(root, "AltStore/AltStore.entitlements"))
    clear_free_account_entitlements(require_file(root, "AltStore/Resources/ReleaseEntitlements.plist"))
    patch_launch_controller(require_file(root, "AltStore/LaunchViewController.swift"))
    patch_analytics(require_file(root, "AltStore/Analytics/AnalyticsManager.swift"))
    redact_anisette_logs(require_file(root, "AltStore/Operations/FetchAnisetteDataOperation.swift"))
    patch_branding(root)
    patch_transport_fetcher(root)
    verify_clean_patch(root)
    print("MirrorStore compatibility patch applied and static checks passed.")
    print("This is not an Xcode build or an iPhone test.")


if __name__ == "__main__":
    main()
