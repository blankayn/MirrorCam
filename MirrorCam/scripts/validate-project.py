"""Structural validation on Windows/macOS. This is NOT an iOS compiler or runtime test."""
from pathlib import Path
import json
import plistlib
import re
import struct
import sys
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
source = root / "MirrorCam"
project_path = root / "MirrorCam.xcodeproj/project.pbxproj"
project = project_path.read_text(encoding="utf-8")
checks = []

def check(condition, text):
    if not condition:
        raise SystemExit("FAIL: " + text)
    checks.append(text)

# Parse the complete OpenStep project, rather than relying only on text searches.
clean = re.sub(r"/\*.*?\*/|//[^\n]*", "", project, flags=re.S)
tokens = re.findall(r'"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+', clean)
index = 0
def consume(expected=None):
    global index
    token = tokens[index]
    index += 1
    if expected is not None and token != expected:
        raise SystemExit(f"FAIL: Project syntax: expected {expected}, got {token}")
    return token
def value():
    if tokens[index] == "{":
        consume("{")
        result = {}
        while tokens[index] != "}":
            key = consume().strip('"')
            consume("=")
            result[key] = value()
            consume(";")
        consume("}")
        return result
    if tokens[index] == "(":
        consume("(")
        result = []
        while tokens[index] != ")":
            result.append(value())
            if tokens[index] == ",": consume(",")
        consume(")")
        return result
    return consume().strip('"')

parsed = value()
check(index == len(tokens), "Xcode project parses as OpenStep")
objects = parsed["objects"]
check(parsed["rootObject"] in objects, "Root project object resolves")
for name, obj in objects.items():
    for key in ["fileRef", "buildConfigurationList", "productReference", "mainGroup", "productRefGroup"]:
        if key in obj: check(obj[key] in objects, f"Reference {name}.{key} resolves")
    for key in ["children", "buildPhases", "targets", "files", "buildConfigurations"]:
        for ref in obj.get(key, []): check(ref in objects, f"Reference {ref} resolves")

references = [obj for obj in objects.values() if obj.get("isa") == "PBXFileReference"]
for ref in references:
    if ref.get("sourceTree") == "<group>": check((source / ref["path"]).exists(), ref["path"] + " exists")
phase = next(obj for obj in objects.values() if obj.get("isa") == "PBXSourcesBuildPhase")
compiled = {objects[objects[ref]["fileRef"]]["path"] for ref in phase["files"]}
check(compiled == {p.name for p in source.iterdir() if p.suffix in {".swift", ".m"}}, "Every Swift/Objective-C file belongs to the app source phase")
for obj in objects.values():
    if obj.get("isa") == "XCBuildConfiguration":
        settings = obj["buildSettings"]
        check(settings["IPHONEOS_DEPLOYMENT_TARGET"] == "12.0", "Deployment target is iOS 12.0")
        if "SWIFT_VERSION" in settings:
            check(settings["SWIFT_VERSION"] == "5.0" and settings["TARGETED_DEVICE_FAMILY"] == "1", "Swift 5, iPhone target")

with (source / "Info.plist").open("rb") as stream:
    info = plistlib.load(stream)
check(all(info.get(key) for key in ["NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSPhotoLibraryUsageDescription", "NSPhotoLibraryAddUsageDescription"]), "All four privacy descriptions exist")
check("UIMainStoryboardFile" not in info and "UIApplicationSceneManifest" not in info, "Programmatic UIKit lifecycle for iOS 12")
ET.parse(source / "LaunchScreen.storyboard")
scheme = ET.parse(root / "MirrorCam.xcodeproj/xcshareddata/xcschemes/MirrorCam.xcscheme")
for ref in scheme.iter("BuildableReference"):
    check(ref.attrib["BlueprintIdentifier"] in objects, "Shared scheme target resolves")
check(True, "Launch storyboard and shared scheme XML parse")
catalog = source / "Assets.xcassets/AppIcon.appiconset"
for image in json.loads((catalog / "Contents.json").read_text())["images"]:
    data = (catalog / image["filename"]).read_bytes()
    check(data[:8] == b"\x89PNG\r\n\x1a\n", image["filename"] + " is PNG")
    expected = round(float(image["size"].split("x")[0]) * float(image["scale"][:-1]))
    check(struct.unpack(">II", data[16:24]) == (expected, expected), "Icon pixel dimensions match catalog")

swift = list(source.glob("*.swift"))
check(not any("import SwiftUI" in p.read_text(encoding="utf-8") for p in swift), "UIKit sources contain no SwiftUI import")
sys.path.insert(0, str(root / "build/validation-tools"))
try:
    import tree_sitter
    import tree_sitter_swift
except ImportError:
    print("Swift syntax parse skipped. Optional: pip install --target build/validation-tools tree-sitter==0.25.2 tree-sitter-swift==0.7.4")
else:
    parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
    for file in swift:
        tree = parser.parse(file.read_bytes())
        if tree.root_node.has_error:
            stack = [tree.root_node]
            while stack:
                node = stack.pop()
                if node.type == "ERROR" or node.is_missing:
                    print(f"{file.name}:{node.start_point.row + 1}: {node.type}: {node.text[:100]!r}")
                stack.extend(reversed(node.children))
        check(not tree.root_node.has_error, file.name + " passes Swift syntax parsing")
print(f"PASS: {len(checks)} structural/syntax checks; {len(swift)} Swift source files.")
print("No iOS build, SDK type-check, simulator test, or device test was performed.")
