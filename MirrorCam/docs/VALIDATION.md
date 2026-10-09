# Validation record

Date: 9 October 2026 (Asia/Manila). Local environment: Windows, Python 3.11. Cloud build: GitHub-hosted macOS, Xcode 15.4.

Executed successfully:

- `python scripts/generate-icons.py`: generated eight opaque RGB PNG app icons; inspected the rendered icon visually.
- `python scripts/validate-project.py`: **100 structural/syntax checks passed across eight Swift source files** using tree-sitter 0.25.2 / tree-sitter-swift 0.7.4.
- `bash -n scripts/build-ipa.sh`: Bash script parses successfully using the installed Git Bash.

The validator parses the OpenStep project, resolves object references and source-phase membership, checks all deployment configurations, parses plist/storyboard/scheme XML, verifies privacy descriptions, and checks icon pixel dimensions. Swift parsing detects syntax errors only. It does not resolve Apple framework types, validate API availability, compile code, or exercise camera/PhotoKit behavior.

The [GitHub Actions run 37889696067](https://github.com/blankayn/MirrorCam/actions/runs/37889696067) successfully compiled the Release iOS app with Xcode 15.4 at commit `b6a3bb491de26685edca5c56537b6644d61093b4`. The log reports `BUILD SUCCEEDED`, a minimum OS version of `12.0`, and an `arm64` app executable. The build script packaged an unsigned IPA, including the embedded Swift compatibility libraries. The downloaded artifact ZIP matched GitHub's SHA-256 digest: `8f51304e5767b0637fc92e1eaabffe6721ebae081e84fa72ae3e6f0248644bb8`.

**Not performed:** code signing, installation, simulator execution, or any physical iPhone test. Hardware encoder behavior, camera format selection, photo mirroring metadata, audio sync, rolling-buffer timing and interruption recovery require the physical-device checklist in `DEVICE-TESTS.md`. A successful compilation does not establish these runtime behaviors.

## Version 1.1

- Local validation: **110 structural/syntax checks passed across ten Swift files**.
- [Cloud run 37899096832](https://github.com/blankayn/MirrorCam/actions/runs/37899096832) at commit `ac1b0abb2d16ed841f459348329f60df360df94b`: Xcode 15.4 Release iphoneos build succeeded; minimum OS 12.0, arm64, app version 1.1 (build 2).
- **172 synthetic media assertions passed** on macOS using the actual `FrameGeometry`, `RollingBuffer`, `ClipWriter` and `PhotoFraming` implementations. Checks covered portrait/landscape crops, no resolution upscaling, even encoder dimensions, four JPEG orientation values, normalized mirrored pixels, output sizes, bounded pre-roll, three-second clip duration, matching JPEG/MOV content identifiers, key-photo time at 1.4667 seconds, and PhotoKit recognition of 4:3, square and 16:9 pairs as Live Photos.
- Downloaded IPA archive integrity and Info.plist/version/arm64 checks passed. Artifact ZIP SHA-256: `8a38d5a2ed8c6e4e3b1e35b1c68f3fc5d220ffd78cba9882919c4d979d88ac43`, matching GitHub's digest.

The user confirmed version 1.0 installs and launches on the iPhone. No simulator test or physical-device test of version 1.1 was performed. Synthetic PhotoKit recognition on macOS does not establish iOS 12 Photos-library import, touch-and-hold playback, actual camera field of view, microphone sync or device performance. Run `DEVICE-TESTS.md` on the iPhone 6 after installation.

## Version 1.2

- Local validation: **118 structural/syntax checks passed across ten Swift files**. This includes Objective-C source membership and bridging-header references; Objective-C compilation is not validated on Windows.
- Iris12 0.0.2 was statically analyzed from the author's repository without executing its code. Package hash, filter, arm64 code and observed hook targets are recorded in `IRIS12-ANALYSIS.md`.
- Native Live Photo delegates, session reconfiguration, error cleanup and bridging were reviewed. No native-hook execution, simulator execution or physical iPhone test has been performed. The existing synthetic media tests exercise the software path, not the Iris12 hook or native camera pipeline.
- [Cloud run 37902485260](https://github.com/blankayn/MirrorCam/actions/runs/37902485260) at commit `fa9c41449822ead203973c8d5f8af684ec064f67`: Xcode 15.4 Release iphoneos build succeeded, including Objective-C runtime hooks and Swift bridging. Cloud structural validation passed 108 checks; all **172 software media assertions passed**. The local parser adds ten Swift syntax checks.
- Downloaded IPA: version 1.2 (build 3), arm64, minimum OS 12.0 in both Info.plist and Mach-O, embedded Swift libraries present, archive integrity verified. Artifact ZIP SHA-256: `3a9752f063497178faeb27c09ab4f0da31b8af5e0ea9c592b89c7cc549969659`, matching GitHub's digest.

## Version 1.3

- Windows validation passed **123 structural/syntax checks across eleven Swift files**.
- Camera layout follows a 44 + 500 + 123-point photo layout at standard iPhone 6 display size. No UIKit runtime/layout or physical-device check has been performed yet.
- [Cloud run 37947966167](https://github.com/blankayn/MirrorCam/actions/runs/37947966167) at commit `48a3c26bcb943978b906b4a3d8dfb7b051be4dad`: Xcode 15.4 Release iphoneos build succeeded. Cloud project validation passed 112 checks; all **194 synthetic media assertions passed** (172 existing media assertions and 22 added HDR assertions/fixture checks).
- New HDR checks executed the actual processor: horizontal and vertical translation, merge/tone mapping, clipped-highlight recovery, shadow detail, EXIF exposure ratios, mirror normalization, all three aspect crops, incomplete brackets and the 1600-pixel processing bound. Registration uses a bounded search on exposure-normalized 160-pixel thumbnails; full output framing remains anchored to the normal exposure.
- Downloaded IPA archive integrity passed; Info.plist and Mach-O verify version 1.3 (build 4), arm64 and minimum OS 12.0. Embedded Swift libraries are present. Artifact ZIP SHA-256 `3e00e2b0d0c14d9a5a5f40847f29ce628133a891b99262e4dcf5fd6613e1f493` matches GitHub's digest.

No simulator or physical iPhone 6 test of version 1.3 has been performed. Synthetic HDR inputs do not establish actual camera bracketing support, handheld image quality, latency, memory use or Photos saving. Screen geometry and library-header visibility require the device checklist.
